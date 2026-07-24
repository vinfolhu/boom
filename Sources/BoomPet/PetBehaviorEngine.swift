import Foundation

enum PetInteractionEvent {
    case hover
    case drag
    case tap
    case roam
    case idle
    case returnFromDock
}

final class PetBehaviorEngine {
    private enum Mood {
        case playful
        case needy
        case curious
        case sleepy
    }

    private var mood: Mood = .curious
    private var lastMessageDate = Date.distantPast
    private var interactionCount = 0

    func message(
        for event: PetInteractionEvent,
        language: LanguageStore,
        bypassCooldown: Bool = false
    ) -> String? {
        let now = Date()
        let minimumGap: TimeInterval = event == .drag ? 0.6 : 2.2
        guard bypassCooldown || now.timeIntervalSince(lastMessageDate) >= minimumGap else {
            return nil
        }

        interactionCount += 1
        updateMood(for: event)
        lastMessageDate = now

        let chinese: [String]
        let english: [String]
        switch event {
        case .hover:
            chinese = [
                "主人，我好痒啊～",
                "你是不是想摸摸我？",
                "嘿！被我发现你啦。",
                "再靠近一点点嘛～"
            ]
            english = [
                "I'm itchy, human…",
                "Were you going to pet me?",
                "Hey! I spotted you.",
                "Come a tiny bit closer…"
            ]
        case .drag:
            chinese = [
                "快来救救我呀！",
                "主人要卖掉我了？",
                "呜呜呜……我要去哪？",
                "慢一点，我会晕车的！"
            ]
            english = [
                "Somebody save me!",
                "Are you selling me?!",
                "Nooo… where are we going?",
                "Slow down, I get motion sick!"
            ]
        case .tap:
            chinese = [
                "嘿嘿，再摸一下～",
                "嗯？是在夸我可爱吗？",
                "本宠批准这次摸摸。",
                "咕噜咕噜……"
            ]
            english = [
                "Hehe, pet me again!",
                "Hmm? Are you calling me cute?",
                "This petting is officially approved.",
                "Prrrr…"
            ]
        case .roam:
            chinese = [
                "我去巡逻一下！",
                "这块屏幕都是我的地盘。",
                "追不上我吧～",
                "我闻到了冒险的味道！"
            ]
            english = [
                "Time for patrol!",
                "This whole screen is my territory.",
                "Can't catch me!",
                "I smell an adventure!"
            ]
        case .idle:
            chinese = idleChineseMessages()
            english = idleEnglishMessages()
        case .returnFromDock:
            chinese = [
                "锵锵！我又回来啦。",
                "躲猫猫结束～",
                "你果然舍不得我吧？"
            ]
            english = [
                "Ta-da! I'm back.",
                "Hide-and-seek is over!",
                "You missed me, didn't you?"
            ]
        }

        let options = language.isChinese ? chinese : english
        return options.randomElement()
    }

    var shouldSpeakWhileRoaming: Bool {
        Int.random(in: 0..<100) < 32
    }

    var shouldStartLongRoam: Bool {
        switch mood {
        case .playful:
            return Int.random(in: 0..<100) < 48
        case .curious:
            return Int.random(in: 0..<100) < 34
        case .needy:
            return Int.random(in: 0..<100) < 20
        case .sleepy:
            return Int.random(in: 0..<100) < 10
        }
    }

    private func updateMood(for event: PetInteractionEvent) {
        switch event {
        case .hover, .tap, .returnFromDock:
            mood = interactionCount.isMultiple(of: 3) ? .playful : .needy
        case .drag, .roam:
            mood = .playful
        case .idle:
            mood = [.sleepy, .curious, .needy].randomElement() ?? .curious
        }
    }

    private func idleChineseMessages() -> [String] {
        switch mood {
        case .playful:
            return ["来追我呀！", "今天也要捣蛋一下。", "我的尾巴是不是超帅？"]
        case .needy:
            return ["主人忙完了吗？", "我只占用你三秒钟～", "这里有一只宠物需要关注。"]
        case .curious:
            return ["这个窗口里藏着什么？", "你的鼠标要去哪里呀？", "我正在研究人类。"]
        case .sleepy:
            return ["哈欠……我只眯一下。", "今天适合打个小盹。", "如果我睡着了要叫我哦。"]
        }
    }

    private func idleEnglishMessages() -> [String] {
        switch mood {
        case .playful:
            return ["Catch me if you can!", "Time for a little mischief.", "Isn't my tail amazing?"]
        case .needy:
            return ["Are you done working yet?", "I only need three seconds!", "A pet here requires attention."]
        case .curious:
            return ["What's hiding in that window?", "Where is your cursor going?", "I'm studying humans."]
        case .sleepy:
            return ["Yawn… just a tiny nap.", "Perfect weather for a snooze.", "Wake me if I fall asleep."]
        }
    }
}
