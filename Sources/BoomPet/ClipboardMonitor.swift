import AppKit

final class ClipboardMonitor {
    static let didWriteClipboardNotification = Notification.Name(
        "BoomPet.didWriteClipboard"
    )

    private let history: OCRHistoryStore
    private let settings: OCRSettingsStore
    private var timer: Timer?
    private var writeObserver: NSObjectProtocol?
    private var lastChangeCount = NSPasteboard.general.changeCount

    init(history: OCRHistoryStore, settings: OCRSettingsStore) {
        self.history = history
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        writeObserver = NotificationCenter.default.addObserver(
            forName: Self.didWriteClipboardNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastChangeCount = NSPasteboard.general.changeCount
        }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let writeObserver {
            NotificationCenter.default.removeObserver(writeObserver)
        }
        writeObserver = nil
    }

    static func markAppWrite() {
        NotificationCenter.default.post(
            name: didWriteClipboardNotification,
            object: nil
        )
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard settings.clipboardHistoryEnabled,
              let text = pasteboard.string(forType: .string) else {
            return
        }
        history.add(source: .clipboard, text: text)
    }
}
