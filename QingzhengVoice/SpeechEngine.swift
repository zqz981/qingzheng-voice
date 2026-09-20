import Foundation
import Speech

@MainActor
protocol SpeechEngine: AnyObject {
    func prepareLocale(_ locale: Locale, onProgress: @escaping (Double) -> Void) async throws -> Double?
    func start(locale: Locale, onPartial: @escaping (String) -> Void) async throws
    func stop() async throws -> String
    func cancel()
}

enum SpeechEngineFactory {
    @MainActor
    static func make() -> SpeechEngine {
        if #available(macOS 26.0, *) {
            return ModernSpeechEngine()
        }
        return LegacySpeechEngine()
    }
}

enum SpeechFailure: LocalizedError {
    case microphoneDenied
    case speechDenied
    case localeUnavailable
    case noAudioFormat
    case notRecording
    case empty

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "没有麦克风权限"
        case .speechDenied: return "没有语音识别权限"
        case .localeUnavailable: return "当前系统没有可用的中文或英文语音模型"
        case .noAudioFormat: return "无法匹配麦克风音频格式"
        case .notRecording: return "当前没有在录音"
        case .empty: return "没听清，请再试一次"
        }
    }
}

enum LocaleResolver {
    static func preferred(_ identifier: String) -> Locale {
        if identifier == "system" {
            return Locale.current
        }
        return Locale(identifier: identifier)
    }

    static func candidates(_ preferred: Locale) -> [Locale] {
        let id = preferred.identifier
        var list = [preferred]
        if id.lowercased().hasPrefix("zh") {
            list.append(contentsOf: [
                Locale(identifier: "zh-CN"),
                Locale(identifier: "zh_CN"),
                Locale(identifier: "zh-Hans"),
                Locale(identifier: "zh-Hans-CN")
            ])
        }
        list.append(Locale(identifier: "en-US"))
        var seen = Set<String>()
        return list.filter { seen.insert($0.identifier).inserted }
    }
}
