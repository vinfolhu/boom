import AppKit
import SwiftUI

final class OCRCoordinator {
    let history = OCRHistoryStore()
    let settings = OCRSettingsStore()

    private let language: LanguageStore
    private let capture = ScreenRegionCapture()
    private let stickyController = StickyImageController()
    private let onCaptureVisibility: (Bool) -> Void
    private let onOpenSettings: () -> Void
    private let onCheckUpdates: () -> Void
    private var resultWindow: NSWindow?
    private var historyPopup: OCRHistoryPopupPanel?
    private var popupResignObserver: NSObjectProtocol?
    private var popupShownAt = Date.distantPast

    init(
        language: LanguageStore,
        onCaptureVisibility: @escaping (Bool) -> Void,
        onOpenSettings: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void
    ) {
        self.language = language
        self.onCaptureVisibility = onCaptureVisibility
        self.onOpenSettings = onOpenSettings
        self.onCheckUpdates = onCheckUpdates
        history.setMaximumCount(settings.historyMax)
    }

    func startOCR() {
        beginCapture(for: .ocr) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let capture):
                guard capture.purpose == .ocr else {
                    self.showError("截图任务类型异常。", purpose: .ocr)
                    return
                }
                Task { await self.recognize(capture.image) }
            case .failure(let error):
                self.handleCaptureError(error, purpose: .ocr)
            }
        }
    }

    func startStickyCapture() {
        beginCapture(for: .sticky) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let capture):
                guard capture.purpose == .sticky else {
                    self.showError("贴图任务类型异常。", purpose: .sticky)
                    return
                }
                stickyController.show(image: capture.image)
            case .failure(let error):
                handleCaptureError(error, purpose: .sticky)
            }
        }
    }

    func showCenter() {
        onOpenSettings()
    }

    func toggleHistoryPopup() {
        if historyPopup?.isVisible == true {
            hideHistoryPopup()
        } else {
            showHistoryPopup()
        }
    }

    func hideHistoryPopup() {
        historyPopup?.orderOut(nil)
    }

    private func showHistoryPopup() {
        let panel: OCRHistoryPopupPanel
        if let historyPopup {
            panel = historyPopup
        } else {
            let view = OCRHistoryPopupView(
                history: history,
                language: language,
                onClose: { [weak self] in self?.hideHistoryPopup() },
                onSettings: { [weak self] in
                    self?.hideHistoryPopup()
                    self?.onOpenSettings()
                },
                onClear: { [weak self] in self?.confirmClearHistory() },
                onCheckUpdate: { [weak self] in
                    self?.hideHistoryPopup()
                    self?.onCheckUpdates()
                },
                onQuit: { NSApp.terminate(nil) },
                onOCR: { [weak self] in
                    self?.hideHistoryPopup()
                    self?.startOCR()
                },
                onSticky: { [weak self] in
                    self?.hideHistoryPopup()
                    self?.startStickyCapture()
                },
                onCopyAndClose: { [weak self] text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    ClipboardMonitor.markAppWrite()
                    self?.hideHistoryPopup()
                }
            )
            let hosting = NSHostingController(rootView: view)
            panel = OCRHistoryPopupPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 440),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hosting
            panel.isReleasedWhenClosed = false
            historyPopup = panel

            popupResignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                guard let self,
                      Date().timeIntervalSince(popupShownAt) > 0.3 else {
                    return
                }
                hideHistoryPopup()
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - 12,
            y: frame.maxY - panel.frame.height - 12
        ))
        popupShownAt = Date()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = language.text(
            "清空所有未置顶记录？",
            "Clear all unpinned history?"
        )
        alert.addButton(withTitle: language.text("清空", "Clear"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            history.clearUnpinned()
        }
    }

    private func beginCapture(
        for purpose: ScreenCapturePurpose,
        completion: @escaping (Result<CapturedScreenRegion, Error>) -> Void
    ) {
        hideHistoryPopup()
        resultWindow?.orderOut(nil)
        onCaptureVisibility(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.capture.capture(for: purpose) { result in
                self?.onCaptureVisibility(false)
                completion(result)
            }
        }
    }

    @MainActor
    private func recognize(_ image: CGImage) async {
        do {
            let text = try await VisionOCRService.recognize(image)
            history.add(source: .ocr, text: text)
            guard let item = history.items.first else { return }

            var translation = ""
            if settings.autoTranslate, settings.provider != .disabled {
                do {
                    translation = try await TranslationService.translate(
                        text,
                        configuration: settings.configuration
                    )
                    history.updateTranslation(id: item.id, translation: translation)
                } catch {
                    showError(error.localizedDescription)
                }
            }
            showResult(itemID: item.id, text: text, translation: translation)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showResult(itemID: UUID, text: String, translation: String) {
        let view = OCRResultView(
            itemID: itemID,
            originalText: text,
            translatedText: translation,
            settings: settings,
            history: history,
            language: language
        )
        let controller = NSHostingController(rootView: view)
        let window = resultWindow ?? NSWindow(contentViewController: controller)
        window.contentViewController = controller
        window.title = language.text("OCR 结果", "OCR Result")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        resultWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func handleCaptureError(
        _ error: Error,
        purpose: ScreenCapturePurpose
    ) {
        if case CaptureError.cancelled = error { return }
        showError(error.localizedDescription, purpose: purpose)
    }

    private func showError(
        _ message: String,
        purpose: ScreenCapturePurpose = .ocr
    ) {
        let alert = NSAlert()
        switch purpose {
        case .ocr:
            alert.messageText = language.text("OCR 失败", "OCR Failed")
        case .sticky:
            alert.messageText = language.text("贴图失败", "Sticky Capture Failed")
        }
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

final class StickyImageController {
    private var windows: [NSWindow] = []

    func show(image: CGImage) {
        let imageSize = NSSize(width: image.width, height: image.height)
        let scale = min(1, 560 / max(imageSize.width, imageSize.height))
        let size = NSSize(
            width: max(180, imageSize.width * scale),
            height: max(120, imageSize.height * scale)
        )
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(cgImage: image, size: size)
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        window.title = "BoomPet Sticky"
        window.contentView = imageView
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        windows.append(window)
        window.makeKeyAndOrderFront(nil)
    }
}
