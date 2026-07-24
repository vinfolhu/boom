import Foundation

struct Reminder: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var intervalMinutes: Int
    var isEnabled: Bool
    var nextFireDate: Date?

    init(
        id: UUID = UUID(),
        title: String,
        intervalMinutes: Int,
        isEnabled: Bool = true,
        nextFireDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.intervalMinutes = intervalMinutes
        self.isEnabled = isEnabled
        self.nextFireDate = nextFireDate
    }
}
