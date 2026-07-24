import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reminderStore = ReminderStore()
    private let languageStore = LanguageStore()
    private lazy var boomController = BoomController()
    private var petController: PetController?
    private var scheduler: ReminderScheduler?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "BoomPet.petAutoRoam": true
        ])

        scheduler = ReminderScheduler(store: reminderStore) { [weak self] reminder in
            guard let self else { return }
            boomController.show(
                message: reminder.title,
                headline: languageStore.text("BOOM时间到。", "BOOM time!")
            )
        }

        petController = PetController(
            onOpenSettings: { [weak self] in self?.showSettings() },
            onTestBoom: { [weak self] in
                guard let self else { return }
                boomController.show(
                    message: languageStore.text(
                        "休息一下，活动活动吧！",
                        "Take a break and move around!"
                    ),
                    headline: languageStore.text("BOOM时间到。", "BOOM time!")
                )
            },
            languageStore: languageStore
        )

        petController?.show()
        scheduler?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
        petController?.stop()
    }

    private func showSettings() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            store: reminderStore,
            language: languageStore,
            onTestBoom: { [weak self] message in
                guard let self else { return }
                boomController.show(
                    message: message,
                    headline: languageStore.text("BOOM时间到。", "BOOM time!")
                )
            },
            onChoosePetImage: { [weak self] in
                if PetAssetStore.chooseImage() {
                    self?.petController?.reloadImage()
                }
            },
            onRestoreDefaultPet: { [weak self] in
                PetAssetStore.restoreDefault()
                self?.petController?.reloadImage()
            }
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = languageStore.text("BoomPet 设置", "BoomPet Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.minSize = NSSize(width: 520, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
