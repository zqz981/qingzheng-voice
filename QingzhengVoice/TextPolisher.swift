import Foundation

protocol TextPolisher: Sendable {
    func polish(_ text: String) async throws -> String
}

enum PolishBackend: String, CaseIterable, Identifiable, Hashable {
    case auto
    case mock
    case apple
    case openai

    var id: String { rawValue }
}

enum PolisherFactory {
    static func make(settings: SettingsStore) -> any TextPolisher {
        guard settings.polishEnabled else { return PassthroughPolisher() }
        switch settings.polishBackend {
        case .mock:
            return MockPolisher()
        case .apple:
            return AppleOrMockPolisher()
        case .openai:
            return OpenAIPolisher(settings: settings.settingsCopy())
        case .auto:
            if !settings.apiKey().isEmpty {
                return OpenAIPolisher(settings: settings.settingsCopy())
            }
            return AppleOrMockPolisher()
        }
    }
}

struct PassthroughPolisher: TextPolisher {
    func polish(_ text: String) async throws -> String { text }
}

struct MockPolisher: TextPolisher {
    func polish(_ text: String) async throws -> String {
        Self.normalize(text)
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken: [(String, String)] = [
            ("新段落", "\n\n"),
            ("new paragraph", "\n\n"),
            ("换行", "\n"),
            ("換行", "\n"),
            ("new line", "\n"),
            ("newline", "\n"),
            ("句号", "。"),
            ("句號", "。"),
            ("逗号", "，"),
            ("逗號", "，"),
            ("顿号", "、"),
            ("頓號", "、"),
            ("问号", "？"),
            ("問號", "？"),
            ("感叹号", "！"),
            ("感嘆號", "！"),
            ("惊叹号", "！"),
            ("冒号", "："),
            ("冒號", "："),
            ("分号", "；"),
            ("分號", "；"),
            ("省略号", "……"),
            ("省略號", "……"),
            ("question mark", "?"),
            ("exclamation mark", "!"),
            ("exclamation point", "!"),
            ("full stop", "."),
            ("period", "."),
            ("comma", ","),
            ("colon", ":"),
            ("semicolon", ";")
        ]
        for (from, to) in spoken {
            text = text.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        for filler in ["嗯嗯", "嗯", "啊", "呃", "那个", "um", "uh"] {
            text = text.replacingOccurrences(of: " \(filler) ", with: " ", options: .caseInsensitive)
        }
        while let range = text.range(of: #"([\u{4E00}-\u{9FFF}]) +([\u{4E00}-\u{9FFF}])"#, options: .regularExpression) {
            let compact = text[range].replacingOccurrences(of: " ", with: "")
            text.replaceSubrange(range, with: compact)
        }
        text = text.replacingOccurrences(of: #"([，。！？；：、]) "#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AppleOrMockPolisher: TextPolisher {
    func polish(_ text: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                return try await AppleIntelligencePolisher().polish(text)
            } catch {
                return MockPolisher.normalize(text)
            }
        }
        #endif
        return MockPolisher.normalize(text)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
struct AppleIntelligencePolisher: TextPolisher {
    func polish(_ text: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return MockPolisher.normalize(text)
        }
        let session = LanguageModelSession(instructions: PolishPrompt.system)
        let response = try await session.respond(to: text)
        let content = String(describing: response.content)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MockPolisher.normalize(text) : trimmed
    }
}
#endif

struct OpenAIPolisher: TextPolisher {
    let settings: PolishSettings

    func polish(_ text: String) async throws -> String {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return MockPolisher.normalize(text) }

        let root = settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = root.hasSuffix("/chat/completions") ? root : root + "/chat/completions"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(
            model: settings.model,
            temperature: 0.2,
            messages: [
                .init(role: "system", content: PolishPrompt.system),
                .init(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "QingzhengVoice",
                code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                userInfo: [NSLocalizedDescriptionKey: "云端整理失败 \(detail.prefix(120))"]
            )
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return content.isEmpty ? MockPolisher.normalize(text) : content
    }
}

enum PolishPrompt {
    static let system = """
    你是语音输入的文本整理器，服务对象是中文用户「清正」。
    把语音识别的原始文本整理成可以直接粘贴进当前应用的最终文本。
    规则：
    - 只保留原意，不扩写、不总结、不回答问题
    - 中文为主，英文专有名词、代码标识符保持原样
    - 去掉口头禅和重复（嗯、啊、那个、就是说）
    - 加上合适的中英文标点与换行
    - 用户说了「句号」「逗号」「换行」等指令时，转成对应符号
    - 只输出整理后的文本，不要引号或解释
    """
}

struct PolishSettings: Sendable {
    var baseURL: String
    var model: String
    var apiKey: String
}

private struct ChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double
    let messages: [Message]
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }

    let choices: [Choice]
}
