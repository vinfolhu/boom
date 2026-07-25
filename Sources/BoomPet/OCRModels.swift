import Combine
import Foundation
import Security

enum OCRDataPaths {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".vinfol", isDirectory: true)
    static let settings = directory.appendingPathComponent("ocr_trans.json")
    static let history = directory.appendingPathComponent("history.json")

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }
}

enum OCRHistorySource: String, Codable {
    case ocr
    case clipboard
}

struct OCRHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var source: OCRHistorySource
    var originalText: String
    var translatedText: String?
    var isPinned: Bool
    var remark: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: OCRHistorySource,
        originalText: String,
        translatedText: String? = nil,
        isPinned: Bool = false,
        remark: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.originalText = originalText
        self.translatedText = translatedText
        self.isPinned = isPinned
        self.remark = remark
    }
}

final class OCRHistoryStore: ObservableObject {
    @Published private(set) var items: [OCRHistoryItem] = []
    private let defaultsKey = "BoomPet.ocrHistory.v1"
    private let maximumCountKey = "BoomPet.ocr.historyMax"

    private var maximumCount: Int {
        let saved = UserDefaults.standard.integer(forKey: maximumCountKey)
        return min(2_000, max(20, saved > 0 ? saved : 200))
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([OCRHistoryItem].self, from: data) {
            items = saved
        }
        migrateLegacyHistoryIfNeeded()
        mirrorLegacyHistoryFile()
    }

    func add(source: OCRHistorySource, text: String, translation: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = items.firstIndex(where: {
            normalizedForDeduplication($0.originalText)
                == normalizedForDeduplication(trimmed)
        }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            existing.source = source
            existing.originalText = trimmed
            if let translation, !translation.isEmpty {
                existing.translatedText = translation
            }
            items.insert(existing, at: 0)
            sortAndSave()
            return
        }
        items.insert(
            OCRHistoryItem(
                source: source,
                originalText: trimmed,
                translatedText: translation
            ),
            at: 0
        )
        trimAndSave()
    }

    func updateTranslation(id: UUID, translation: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].translatedText = translation
        save()
    }

    func setRemark(id: UUID, remark: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = remark?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        items[index].remark = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        sortAndSave()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        save()
    }

    func setMaximumCount(_ count: Int) {
        UserDefaults.standard.set(
            min(2_000, max(20, count)),
            forKey: maximumCountKey
        )
        trimAndSave()
    }

    private func trimAndSave() {
        if items.count > maximumCount {
            let pinned = items.filter(\.isPinned)
            let unpinned = items.filter { !$0.isPinned }
            items = pinned + Array(unpinned.prefix(max(0, maximumCount - pinned.count)))
        }
        save()
    }

    private func sortAndSave() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        trimAndSave()
    }

    private func normalizedForDeduplication(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        mirrorLegacyHistoryFile()
    }

    private func mirrorLegacyHistoryFile() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let records: [[String: Any]] = items.map { item in
            var record: [String: Any] = [
                "id": item.id.uuidString,
                "content": item.originalText,
                "original_text": item.originalText,
                "pinned": item.isPinned,
                "kind": item.source == .ocr ? "ocr" : "clipboard",
                "created_at": formatter.string(from: item.createdAt)
            ]
            if let translated = item.translatedText {
                record["translated_text"] = translated
            }
            if let remark = item.remark {
                record["remark"] = remark
            }
            return record
        }
        guard let data = try? JSONSerialization.data(
            withJSONObject: records,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        do {
            try OCRDataPaths.ensureDirectory()
            try data.write(to: OCRDataPaths.history, options: .atomic)
        } catch {
            // UserDefaults remains the authoritative fallback if the mirror is unavailable.
        }
    }

    private func migrateLegacyHistoryIfNeeded() {
        let migrationKey = "BoomPet.ocrLegacyHistoryMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey),
              items.isEmpty else {
            return
        }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vinfol/history.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let rawItems = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatter = ISO8601DateFormatter()
        items = rawItems.compactMap { raw in
            let original = (raw["original_text"] as? String)
                ?? (raw["content"] as? String)
                ?? ""
            guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let kind = raw["kind"] as? String
            let source: OCRHistorySource = kind == "ocr" ? .ocr : .clipboard
            let date = (raw["created_at"] as? String)
                .flatMap {
                    fractionalFormatter.date(from: $0) ?? isoFormatter.date(from: $0)
                } ?? Date()
            return OCRHistoryItem(
                id: (raw["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                createdAt: date,
                source: source,
                originalText: original,
                translatedText: raw["translated_text"] as? String,
                isPinned: raw["pinned"] as? Bool ?? false,
                remark: raw["remark"] as? String
            )
        }
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        trimAndSave()
    }
}

enum TranslationProvider: String, CaseIterable, Identifiable {
    case disabled
    case baidu
    case openAI
    case deepL
    case libreTranslate

    var id: String { rawValue }
}

struct TranslationConfiguration {
    let provider: TranslationProvider
    let apiURL: String
    let apiKey: String
    let apiSecret: String
    let model: String
    let targetLanguage: String
}

final class OCRSettingsStore: ObservableObject {
    @Published var provider: TranslationProvider {
        didSet { save() }
    }
    @Published var apiURL: String {
        didSet { save() }
    }
    @Published var apiKey: String {
        didSet {
            guard secretsLoaded else { return }
            KeychainStore.set(apiKey, account: "translation-api-key")
        }
    }
    @Published var apiSecret: String {
        didSet {
            guard secretsLoaded else { return }
            KeychainStore.set(apiSecret, account: "translation-api-secret")
        }
    }
    @Published var model: String {
        didSet { save() }
    }
    @Published var targetLanguage: String {
        didSet { save() }
    }
    @Published var autoTranslate: Bool {
        didSet { save() }
    }
    @Published var clipboardHistoryEnabled: Bool {
        didSet { save() }
    }
    @Published var historyMax: Int {
        didSet {
            let clamped = min(2_000, max(20, historyMax))
            if historyMax != clamped {
                historyMax = clamped
                return
            }
            save()
        }
    }

    private let prefix = "BoomPet.ocr."
    private var secretsLoaded = false
    private var pendingLegacyAPIKey = ""
    private var pendingLegacyAPISecret = ""

    init() {
        provider = TranslationProvider(
            rawValue: UserDefaults.standard.string(forKey: prefix + "provider") ?? ""
        ) ?? .disabled
        apiURL = UserDefaults.standard.string(forKey: prefix + "apiURL")
            ?? "https://api.openai.com/v1/chat/completions"
        // Do not touch Keychain during application launch. Ad-hoc development
        // builds may have a different code identity after each update, and an
        // eager read would show a password prompt before translation is used.
        apiKey = ""
        apiSecret = ""
        model = UserDefaults.standard.string(forKey: prefix + "model") ?? "gpt-4o-mini"
        targetLanguage = UserDefaults.standard.string(forKey: prefix + "targetLanguage") ?? "auto"
        autoTranslate = UserDefaults.standard.bool(forKey: prefix + "autoTranslate")
        clipboardHistoryEnabled = UserDefaults.standard.bool(
            forKey: prefix + "clipboardHistoryEnabled"
        )
        let savedHistoryMax = UserDefaults.standard.integer(forKey: prefix + "historyMax")
        historyMax = savedHistoryMax > 0 ? savedHistoryMax : 200
        migrateLegacySettingsIfNeeded()
        mirrorLegacySettingsFile()
    }

    var configuration: TranslationConfiguration {
        loadSecretsIfNeeded()
        return TranslationConfiguration(
            provider: provider,
            apiURL: apiURL,
            apiKey: apiKey,
            apiSecret: apiSecret,
            model: model,
            targetLanguage: targetLanguage
        )
    }

    func loadSecretsIfNeeded() {
        guard !secretsLoaded else { return }
        let keychainAPIKey = KeychainStore.get(account: "translation-api-key")
        let keychainAPISecret = KeychainStore.get(
            account: "translation-api-secret"
        )
        apiKey = keychainAPIKey ?? pendingLegacyAPIKey
        apiSecret = keychainAPISecret ?? pendingLegacyAPISecret
        secretsLoaded = true
        if keychainAPIKey == nil, !pendingLegacyAPIKey.isEmpty {
            KeychainStore.set(
                pendingLegacyAPIKey,
                account: "translation-api-key"
            )
        }
        if keychainAPISecret == nil, !pendingLegacyAPISecret.isEmpty {
            KeychainStore.set(
                pendingLegacyAPISecret,
                account: "translation-api-secret"
            )
        }
        pendingLegacyAPIKey = ""
        pendingLegacyAPISecret = ""
    }

    func applyDefaults(for provider: TranslationProvider) {
        self.provider = provider
        switch provider {
        case .disabled:
            break
        case .baidu:
            apiURL = "https://fanyi-api.baidu.com/api/trans/vip/translate"
        case .openAI:
            apiURL = "https://api.openai.com/v1/chat/completions"
            model = "gpt-4o-mini"
        case .deepL:
            apiURL = "https://api-free.deepl.com/v2/translate"
        case .libreTranslate:
            apiURL = "https://libretranslate.com/translate"
        }
    }

    private func save() {
        UserDefaults.standard.set(provider.rawValue, forKey: prefix + "provider")
        UserDefaults.standard.set(apiURL, forKey: prefix + "apiURL")
        UserDefaults.standard.set(model, forKey: prefix + "model")
        UserDefaults.standard.set(targetLanguage, forKey: prefix + "targetLanguage")
        UserDefaults.standard.set(autoTranslate, forKey: prefix + "autoTranslate")
        UserDefaults.standard.set(
            clipboardHistoryEnabled,
            forKey: prefix + "clipboardHistoryEnabled"
        )
        UserDefaults.standard.set(historyMax, forKey: prefix + "historyMax")
        mirrorLegacySettingsFile()
    }

    private func mirrorLegacySettingsFile() {
        var root = (try? Data(contentsOf: OCRDataPaths.settings))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [:]
        var translate = root["translate"] as? [String: Any] ?? [:]
        let providerName: String
        switch provider {
        case .disabled:
            providerName = translate["provider"] as? String ?? "open_ai"
        case .baidu:
            providerName = "baidu"
        case .openAI:
            providerName = "open_ai"
        case .deepL:
            providerName = "deep_l"
        case .libreTranslate:
            providerName = "libre_translate"
        }
        translate["provider"] = providerName
        translate["api_url"] = apiURL
        translate["source_lang"] = "auto"
        translate["target_lang"] = targetLanguage
        translate["model"] = model
        if translate["api_key"] == nil {
            translate["api_key"] = ""
        }
        if translate["api_secret"] == nil {
            translate["api_secret"] = ""
        }
        root["translate"] = translate
        if root["ocr"] == nil {
            root["ocr"] = [
                "provider": "mac_vision",
                "api_url": "",
                "api_key": "",
                "api_secret": "",
                "language": "chs",
                "custom_response_path": ""
            ]
        }
        root["history_max"] = historyMax
        root["auto_translate_after_ocr"] = autoTranslate
        root["boompet_translation_disabled"] = provider == .disabled

        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return
        }
        do {
            try OCRDataPaths.ensureDirectory()
            try data.write(to: OCRDataPaths.settings, options: .atomic)
        } catch {
            // UserDefaults/Keychain remain available if the compatibility mirror fails.
        }
    }

    private func migrateLegacySettingsIfNeeded() {
        let migrationKey = prefix + "legacySettingsMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey),
              UserDefaults.standard.string(forKey: prefix + "provider") == nil else {
            return
        }
        defer { UserDefaults.standard.set(true, forKey: migrationKey) }

        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vinfol/ocr_trans.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translate = json["translate"] as? [String: Any] else {
            return
        }

        let legacyProvider = translate["provider"] as? String ?? ""
        switch legacyProvider {
        case "baidu":
            provider = .baidu
        case "open_ai":
            provider = .openAI
        case "deep_l":
            provider = .deepL
        case "libre_translate":
            provider = .libreTranslate
        default:
            provider = .disabled
        }
        apiURL = translate["api_url"] as? String ?? apiURL
        pendingLegacyAPIKey = translate["api_key"] as? String ?? ""
        pendingLegacyAPISecret = translate["api_secret"] as? String ?? ""
        apiKey = pendingLegacyAPIKey
        apiSecret = pendingLegacyAPISecret
        model = translate["model"] as? String ?? model
        targetLanguage = translate["target_lang"] as? String ?? "auto"
        autoTranslate = json["auto_translate_after_ocr"] as? Bool ?? false
        historyMax = json["history_max"] as? Int ?? 200
        save()
    }
}

enum KeychainStore {
    private static let service = "com.vinfol.boom"
    private static let legacyService = "com.local.BoomPet"

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        if let value = get(account: account, service: service) {
            return value
        }

        // This runs only when translation secrets are explicitly requested.
        // Migrate credentials created before the Bundle ID became permanent.
        if let legacyValue = get(account: account, service: legacyService) {
            set(legacyValue, account: account)
            return legacyValue
        }
        return nil
    }

    private static func get(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
