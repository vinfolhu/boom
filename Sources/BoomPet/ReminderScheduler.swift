import AppKit

final class ReminderScheduler {
    private let store: ReminderStore
    private let onFire: (Reminder) -> Void
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var changeObserver: NSObjectProtocol?

    init(store: ReminderStore, onFire: @escaping (Reminder) -> Void) {
        self.store = store
        self.onFire = onFire
    }

    func start() {
        guard timer == nil, wakeObserver == nil else { return }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }

        changeObserver = NotificationCenter.default.addObserver(
            forName: ReminderStore.didChangeNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleNextFire()
        }
        scheduleNextFire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        wakeObserver = nil
        changeObserver = nil
    }

    private func tick() {
        let due = store.dueReminders(at: Date())
        for reminder in due {
            onFire(reminder)
        }
        scheduleNextFire()
    }

    private func scheduleNextFire() {
        timer?.invalidate()
        timer = nil

        guard let nextDate = store.reminders
            .filter(\.isEnabled)
            .compactMap(\.nextFireDate)
            .min() else {
            return
        }

        let safeDate = max(nextDate, Date().addingTimeInterval(0.01))
        let timer = Timer(fire: safeDate, interval: 0, repeats: false) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
