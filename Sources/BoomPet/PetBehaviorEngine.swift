import Foundation

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

        let options = PetDialogueStore.shared.messages(
            for: event,
            isChinese: language.isChinese
        )
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

}
