import Combine
import Foundation

enum PetInteractionEvent: String, Codable, CaseIterable, Identifiable {
    case hover
    case drag
    case tap
    case roam
    case idle
    case returnFromDock

    var id: String { rawValue }

    func title(language: LanguageStore) -> String {
        switch self {
        case .hover: return language.text("鼠标经过", "Hover")
        case .drag: return language.text("拖拽", "Drag")
        case .tap: return language.text("点击", "Tap")
        case .roam: return language.text("自主巡游", "Roaming")
        case .idle: return language.text("发呆", "Idle")
        case .returnFromDock: return language.text("从边缘回来", "Return from edge")
        }
    }
}

private struct PetDialogueConfiguration: Codable {
    var chinese: [String: [String]]
    var english: [String: [String]]
}

final class PetDialogueStore: ObservableObject {
    static let shared = PetDialogueStore()

    @Published private var configuration: PetDialogueConfiguration
    private let defaultsKey = "BoomPet.petDialogues.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(PetDialogueConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = Self.defaults
        }
    }

    func messages(for event: PetInteractionEvent, isChinese: Bool) -> [String] {
        let selected = isChinese ? configuration.chinese : configuration.english
        let fallback = isChinese ? Self.defaults.chinese : Self.defaults.english
        let values = selected[event.rawValue] ?? fallback[event.rawValue] ?? []
        return values.isEmpty ? (fallback[event.rawValue] ?? []) : values
    }

    func editableText(for event: PetInteractionEvent, isChinese: Bool) -> String {
        messages(for: event, isChinese: isChinese).joined(separator: "\n")
    }

    func update(event: PetInteractionEvent, isChinese: Bool, text: String) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if isChinese {
            configuration.chinese[event.rawValue] = lines
        } else {
            configuration.english[event.rawValue] = lines
        }
        save()
    }

    func reset() {
        configuration = Self.defaults
        save()
    }

    private func save() {
        objectWillChange.send()
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static let defaults = PetDialogueConfiguration(
        chinese: [
            "hover": ["主人，我好痒啊～", "你是不是想摸摸我？", "嘿！被我发现你啦。", "再靠近一点点嘛～"],
            "drag": ["快来救救我呀！", "主人要卖掉我了？", "呜呜呜……我要去哪？", "慢一点，我会晕车的！"],
            "tap": ["嘿嘿，再摸一下～", "嗯？是在夸我可爱吗？", "本宠批准这次摸摸。", "咕噜咕噜……"],
            "roam": ["我去巡逻一下！", "这块屏幕都是我的地盘。", "追不上我吧～", "我闻到了冒险的味道！"],
            "idle": ["主人忙完了吗？", "我只占用你三秒钟～", "你的鼠标要去哪里呀？", "哈欠……我只眯一下。", "今天也要捣蛋一下。"],
            "returnFromDock": ["锵锵！我又回来啦。", "躲猫猫结束～", "你果然舍不得我吧？"]
        ],
        english: [
            "hover": ["I'm itchy, human…", "Were you going to pet me?", "Hey! I spotted you.", "Come a tiny bit closer…"],
            "drag": ["Somebody save me!", "Are you selling me?!", "Nooo… where are we going?", "Slow down, I get motion sick!"],
            "tap": ["Hehe, pet me again!", "Are you calling me cute?", "This petting is officially approved.", "Prrrr…"],
            "roam": ["Time for patrol!", "This whole screen is my territory.", "Can't catch me!", "I smell an adventure!"],
            "idle": ["Are you done working yet?", "I only need three seconds!", "Where is your cursor going?", "Yawn… just a tiny nap.", "Time for a little mischief."],
            "returnFromDock": ["Ta-da! I'm back.", "Hide-and-seek is over!", "You missed me, didn't you?"]
        ]
    )
}
