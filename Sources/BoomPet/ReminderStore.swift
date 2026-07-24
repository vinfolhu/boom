import Combine
import Foundation

final class ReminderStore: ObservableObject {
    static let didChangeNotification = Notification.Name("BoomPet.ReminderStoreDidChange")

    @Published private(set) var reminders: [Reminder] = []

    private let defaultsKey: String

    init(defaultsKey: String = "BoomPet.reminders.v1") {
        self.defaultsKey = defaultsKey
        load()
    }

    func add(title: String, intervalMinutes: Int) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutes = max(1, intervalMinutes)
        let reminder = Reminder(
            title: cleanTitle.isEmpty ? "休息一下" : cleanTitle,
            intervalMinutes: minutes,
            isEnabled: true,
            nextFireDate: alignedNextFireDate(from: Date(), intervalMinutes: minutes)
        )
        reminders.append(reminder)
        save()
    }

    func delete(id: UUID) {
        reminders.removeAll { $0.id == id }
        save()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isEnabled = enabled
        reminders[index].nextFireDate = enabled
            ? alignedNextFireDate(
                from: Date(),
                intervalMinutes: reminders[index].intervalMinutes
            )
            : nil
        save()
    }

    func setInterval(id: UUID, minutes: Int) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].intervalMinutes = max(1, minutes)
        if reminders[index].isEnabled {
            reminders[index].nextFireDate = alignedNextFireDate(
                from: Date(),
                intervalMinutes: reminders[index].intervalMinutes
            )
        }
        save()
    }

    func setTitle(id: UUID, title: String) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        reminders[index].title = cleanTitle
        save()
    }

    func dueReminders(at date: Date) -> [Reminder] {
        var due: [Reminder] = []
        for index in reminders.indices {
            guard reminders[index].isEnabled else { continue }
            if reminders[index].nextFireDate == nil {
                reminders[index].nextFireDate = alignedNextFireDate(
                    from: date,
                    intervalMinutes: reminders[index].intervalMinutes
                )
                continue
            }
            if let fireDate = reminders[index].nextFireDate, fireDate <= date {
                due.append(reminders[index])
                var nextDate = fireDate
                let interval = TimeInterval(reminders[index].intervalMinutes * 60)
                repeat {
                    nextDate = nextDate.addingTimeInterval(interval)
                } while nextDate <= date
                reminders[index].nextFireDate = nextDate
            }
        }
        if !due.isEmpty {
            save()
        }
        return due
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else {
            reminders = []
            return
        }
        let now = Date()
        reminders = saved.map { reminder in
            var migrated = reminder
            if reminder.isEnabled {
                let minuteAligned = reminder.nextFireDate.flatMap {
                    Calendar.current.dateInterval(of: .minute, for: $0)?.start
                }
                migrated.nextFireDate = if let minuteAligned, minuteAligned > now {
                    minuteAligned
                } else {
                    alignedNextFireDate(
                        from: now,
                        intervalMinutes: reminder.intervalMinutes
                    )
                }
            }
            return migrated
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func alignedNextFireDate(from date: Date, intervalMinutes: Int) -> Date {
        let calendar = Calendar.current
        let minuteStart = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        return calendar.date(
            byAdding: .minute,
            value: max(1, intervalMinutes),
            to: minuteStart
        ) ?? minuteStart.addingTimeInterval(TimeInterval(max(1, intervalMinutes) * 60))
    }
}
