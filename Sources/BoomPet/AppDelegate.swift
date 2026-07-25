import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let reminderStore = ReminderStore()
    private let languageStore = LanguageStore()
    private let settingsTabStore = SettingsTabStore()
    private let updateService = UpdateService()
    private lazy var boomController = BoomController()
    private var petController: PetController?
    private var scheduler: ReminderScheduler?
    private lazy var ocrCoordinator = OCRCoordinator(
        language: languageStore,
        onCaptureVisibility: { [weak self] hidden in
            self?.petController?.setTemporarilyHidden(hidden)
            if hidden {
                self?.settingsWindow?.orderOut(nil)
            }
        },
        onOpenSettings: { [weak self] in self?.showSettings(selectedTab: .ocr) },
        onCheckUpdates: { [weak self] in self?.checkForUpdates(silent: false) }
    )
    private lazy var clipboardMonitor = ClipboardMonitor(
        history: ocrCoordinator.history,
        settings: ocrCoordinator.settings
    )
    private let hotKeyManager = GlobalHotKeyManager()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "BoomPet.petAutoRoam": true,
            "BoomPet.petDialogueEnabled": true,
            "BoomPet.petSize": 154.0,
            BoomPreferences.autoCloseKey: true,
            BoomPreferences.autoCloseSecondsKey: 4.5,
            BoomPreferences.effectLevelKey: BoomEffectLevel.balanced.rawValue
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
            onStartOCR: { [weak self] in self?.ocrCoordinator.startOCR() },
            onShowOCRHistory: { [weak self] in self?.ocrCoordinator.toggleHistoryPopup() },
            onStartSticky: { [weak self] in self?.ocrCoordinator.startStickyCapture() },
            onCheckUpdates: { [weak self] in self?.checkForUpdates(silent: false) },
            languageStore: languageStore
        )

        petController?.show()
        scheduler?.start()
        clipboardMonitor.start()
        hotKeyManager.registerDefaults(
            onHistory: { [weak self] in self?.ocrCoordinator.toggleHistoryPopup() },
            onOCR: { [weak self] in self?.ocrCoordinator.startOCR() },
            onSticky: { [weak self] in self?.ocrCoordinator.startStickyCapture() }
        )
        scheduleAutomaticUpdateCheck()
    }

    func applicationWillTerminate(_ notification: Notification) {
        scheduler?.stop()
        clipboardMonitor.stop()
        petController?.stop()
    }

    private func showSettings(selectedTab: AppSettingsTab? = nil) {
        if let selectedTab {
            settingsTabStore.selected = selectedTab
        }
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(
            store: reminderStore,
            ocrHistory: ocrCoordinator.history,
            ocrSettings: ocrCoordinator.settings,
            language: languageStore,
            tabStore: settingsTabStore,
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
            },
            onPetSizeChange: { [weak self] size in
                self?.petController?.updateSize(size)
            },
            onImportPetRig: { [weak self] in
                self?.importPetRig()
            },
            onRestoreDefaultRig: { [weak self] in
                PetRigStore.restoreDefault()
                self?.petController?.reloadRig()
            },
            onRevealPetRig: {
                PetRigStore.revealActiveDirectory()
            },
            onStartOCR: { [weak self] in self?.ocrCoordinator.startOCR() },
            onStartSticky: { [weak self] in
                self?.ocrCoordinator.startStickyCapture()
            }
        )
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = languageStore.text("BoomPet 设置", "BoomPet Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 650))
        window.minSize = NSSize(width: 680, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func importPetRig() {
        switch PetRigStore.importRig() {
        case .success:
            petController?.reloadRig()
        case .failure(let error):
            let alert = NSAlert(error: error)
            alert.messageText = languageStore.text(
                "无法导入宠物动作包",
                "Unable to Import Pet Rig"
            )
            alert.runModal()
        }
    }

    private func scheduleAutomaticUpdateCheck() {
        let key = "BoomPet.lastAutomaticUpdateCheck"
        let lastCheck = UserDefaults.standard.object(forKey: key) as? Date
        guard lastCheck == nil
                || Date().timeIntervalSince(lastCheck!) >= 24 * 60 * 60 else {
            return
        }
        UserDefaults.standard.set(Date(), forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
    }

    private func checkForUpdates(silent: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await updateService.checkForUpdates()
                await MainActor.run {
                    self.handleUpdateResult(result, silent: silent)
                }
            } catch {
                guard !silent else { return }
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = self.languageStore.text(
                        "检查更新失败",
                        "Update Check Failed"
                    )
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    private func handleUpdateResult(_ result: UpdateCheckResult, silent: Bool) {
        switch result {
        case .updateAvailable(let update):
            if silent {
                petController?.showSystemMessage(languageStore.text(
                    "发现新版本 v\(update.version)！右键我，选择“检查更新”就能下载～",
                    "Version \(update.version) is ready! Right-click me and choose Check for Updates."
                ))
            } else {
                showUpdateAlert(update)
            }
        case .upToDate(let latestVersion):
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = languageStore.text(
                "已经是最新版本",
                "BoomPet Is Up to Date"
            )
            alert.informativeText = languageStore.text(
                "当前版本：\(UpdateService.currentVersion)\n最新版本：\(latestVersion)",
                "Current: \(UpdateService.currentVersion)\nLatest: \(latestVersion)"
            )
            alert.runModal()
        case .noPublishedRelease:
            guard !silent else { return }
            let alert = NSAlert()
            alert.messageText = languageStore.text(
                "暂时没有正式版本",
                "No Published Release Yet"
            )
            alert.informativeText = languageStore.text(
                "GitHub Releases 目前为空。创建第一个 v 开头的正式 Release 后即可在线检测。",
                "GitHub Releases is empty. Publish the first v-prefixed release to enable updates."
            )
            alert.addButton(withTitle: languageStore.text("查看 Releases", "Open Releases"))
            alert.addButton(withTitle: languageStore.text("关闭", "Close"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(UpdateService.releasesURL)
            }
        }
    }

    private func showUpdateAlert(_ update: AppUpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = languageStore.text(
            "发现 BoomPet v\(update.version)",
            "BoomPet \(update.version) Is Available"
        )
        if update.downloadURL != nil {
            alert.informativeText = languageStore.text(
                "点击“下载更新”会直接下载 \(update.assetName ?? "BoomPet.dmg")。下载后打开安装包，将 BoomPet 拖入“应用程序”并替换旧版本。",
                "Download \(update.assetName ?? "BoomPet.dmg"), open it, then drag BoomPet into Applications and replace the old version."
            )
            alert.addButton(withTitle: languageStore.text("下载更新", "Download Update"))
            alert.addButton(withTitle: languageStore.text("版本说明", "Release Notes"))
        } else {
            alert.informativeText = languageStore.text(
                "这个 Release 没有找到 macOS 通用版 ZIP，请前往版本页面下载。",
                "No universal macOS ZIP was found. Open the release page to download manually."
            )
            alert.addButton(withTitle: languageStore.text("打开版本页面", "Open Release Page"))
        }
        alert.addButton(withTitle: languageStore.text("稍后", "Later"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.downloadURL ?? update.releasePageURL)
        } else if update.downloadURL != nil,
                  response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(update.releasePageURL)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
