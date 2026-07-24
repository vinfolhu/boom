import AppKit
import CoreGraphics

final class ScreenRegionCapture {
    private var selectionPanel: RegionSelectionPanel?

    func capture(completion: @escaping (Result<CGImage, Error>) -> Void) {
        guard ensurePermission() else {
            completion(.failure(CaptureError.permissionDenied))
            return
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(mouse, $0.frame, false)
        }) ?? NSScreen.main,
        let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID,
        let screenshot = CGDisplayCreateImage(displayID) else {
            completion(.failure(CaptureError.captureFailed))
            return
        }

        let panel = RegionSelectionPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let selectionView = RegionSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screenshot: screenshot
        )
        selectionView.onCancel = { [weak self, weak panel] in
            panel?.close()
            self?.selectionPanel = nil
            completion(.failure(CaptureError.cancelled))
        }
        selectionView.onSelection = { [weak self, weak panel] rect in
            panel?.close()
            self?.selectionPanel = nil
            let scaleX = CGFloat(screenshot.width) / selectionView.bounds.width
            let scaleY = CGFloat(screenshot.height) / selectionView.bounds.height
            let cropRect = CGRect(
                x: rect.minX * scaleX,
                y: (selectionView.bounds.height - rect.maxY) * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            ).integral
            guard let cropped = screenshot.cropping(to: cropRect) else {
                completion(.failure(CaptureError.captureFailed))
                return
            }
            completion(.success(cropped))
        }
        panel.contentView = selectionView
        selectionPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(selectionView)
    }

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case captureFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要开启“屏幕录制”权限后重新启动应用。"
        case .captureFailed:
            return "无法截取当前屏幕。"
        case .cancelled:
            return "已取消"
        }
    }
}

final class RegionSelectionPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class RegionSelectionView: NSView {
    let screenshot: CGImage
    var onSelection: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, screenshot: CGImage) {
        self.screenshot = screenshot
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let image = NSImage(cgImage: screenshot, size: bounds.size)
        image.draw(in: bounds)

        NSColor.black.withAlphaComponent(0.48).setFill()
        bounds.fill()

        if let selectionRect {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selectionRect).addClip()
            image.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemYellow.setStroke()
            let border = NSBezierPath(rect: selectionRect)
            border.lineWidth = 2
            border.stroke()

            let sizeText = "\(Int(selectionRect.width)) × \(Int(selectionRect.height))"
            let label = NSAttributedString(
                string: sizeText,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .backgroundColor: NSColor.black.withAlphaComponent(0.72)
                ]
            )
            label.draw(at: NSPoint(x: selectionRect.minX, y: selectionRect.maxY + 5))
        } else {
            let prompt = NSAttributedString(
                string: "拖拽选择 OCR 区域 · Esc 取消",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
            )
            let size = prompt.size()
            prompt.draw(at: NSPoint(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2
            ))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 5, rect.height >= 5 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        onSelection?(rect.intersection(bounds))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}
