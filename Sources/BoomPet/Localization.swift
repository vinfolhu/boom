import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }
}

final class LanguageStore: ObservableObject {
    @Published var selection: AppLanguage {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: defaultsKey)
        }
    }

    private let defaultsKey = "BoomPet.language"
    private var localeObserver: NSObjectProtocol?

    init() {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        selection = AppLanguage(rawValue: rawValue) ?? .system
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    deinit {
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }

    var isChinese: Bool {
        switch selection {
        case .chinese:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
    }

    func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    func choiceName(_ choice: AppLanguage) -> String {
        switch choice {
        case .system:
            return text("跟随系统", "System")
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}
