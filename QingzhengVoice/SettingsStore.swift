import Combine
import Foundation
import Security
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("localeIdentifier") var localeIdentifier = "zh-CN"
    @AppStorage("polishEnabled") var polishEnabled = true
    @AppStorage("openaiBaseURL") var openaiBaseURL = "https://api.openai.com/v1"
    @AppStorage("openaiModel") var openaiModel = "gpt-4o-mini"
    @Published var polishBackend: PolishBackend {
        didSet { UserDefaults.standard.set(polishBackend.rawValue, forKey: backendKey) }
    }
    @Published var apiKeyDraft = ""

    private let backendKey = "polishBackend"
    private let keychain = KeychainStore(service: "com.qingzheng.voice", account: "openai-api-key")

    init() {
        let raw = UserDefaults.standard.string(forKey: backendKey) ?? PolishBackend.auto.rawValue
        polishBackend = PolishBackend(rawValue: raw) ?? .auto
        apiKeyDraft = keychain.read() ?? ""
    }

    func resolvedLocale() -> Locale {
        LocaleResolver.preferred(localeIdentifier)
    }

    func apiKey() -> String {
        keychain.read() ?? apiKeyDraft
    }

    func loadAPIKey() {
        apiKeyDraft = keychain.read() ?? apiKeyDraft
    }

    func saveAPIKey() {
        UserDefaults.standard.set(polishBackend.rawValue, forKey: backendKey)
        if apiKeyDraft.isEmpty {
            keychain.delete()
        } else {
            keychain.save(apiKeyDraft)
        }
    }

    func settingsCopy() -> PolishSettings {
        PolishSettings(baseURL: openaiBaseURL, model: openaiModel, apiKey: apiKey())
    }
}

final class KeychainStore: Sendable {
    let service: String
    let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) {
        delete()
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
