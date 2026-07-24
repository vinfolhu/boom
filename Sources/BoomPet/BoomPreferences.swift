import Foundation

enum BoomEffectLevel: Int, CaseIterable, Identifiable {
    case light = 0
    case balanced = 1
    case sparkle = 2

    var id: Int { rawValue }

    var rayCount: Int {
        switch self {
        case .light: return 12
        case .balanced: return 20
        case .sparkle: return 26
        }
    }

    var particleCount: Int {
        switch self {
        case .light: return 14
        case .balanced: return 24
        case .sparkle: return 30
        }
    }

    var animationDuration: TimeInterval {
        switch self {
        case .light: return 1.55
        case .balanced: return 1.9
        case .sparkle: return 2.2
        }
    }

    var framesPerSecond: TimeInterval {
        switch self {
        case .light: return 18
        case .balanced: return 24
        case .sparkle: return 30
        }
    }
}

enum BoomPreferences {
    static let autoCloseKey = "BoomPet.boomAutoClose"
    static let autoCloseSecondsKey = "BoomPet.boomAutoCloseSeconds"
    static let effectLevelKey = "BoomPet.boomEffectLevel"

    static var autoClose: Bool {
        UserDefaults.standard.bool(forKey: autoCloseKey)
    }

    static var autoCloseSeconds: TimeInterval {
        min(15, max(2, UserDefaults.standard.double(forKey: autoCloseSecondsKey)))
    }

    static var effectLevel: BoomEffectLevel {
        BoomEffectLevel(
            rawValue: UserDefaults.standard.integer(forKey: effectLevelKey)
        ) ?? .balanced
    }
}
