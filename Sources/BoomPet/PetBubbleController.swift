import AppKit

final class PetBubbleController {
    private let panel: PetBubblePanel
    private let bubbleView: PetBubbleView
    private var hideTimer: Timer?

    init() {
        let size = NSSize(width: 286, height: 104)
        panel = PetBubblePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        bubbleView = PetBubbleView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = bubbleView
    }

    func show(message: String, near petFrame: NSRect, on screen: NSScreen) {
        hideTimer?.invalidate()
        bubbleView.message = message
        resize(for: petFrame, on: screen)
        position(near: petFrame, on: screen)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) {
            [weak self] _ in
            self?.hide()
        }
    }

    func reposition(near petFrame: NSRect, on screen: NSScreen) {
        guard panel.isVisible else { return }
        resize(for: petFrame, on: screen)
        position(near: petFrame, on: screen)
    }

    private func resize(for petFrame: NSRect, on screen: NSScreen) {
        let requestedScale = petFrame.width / 154
        let maximumScale = (screen.visibleFrame.width - 16) / 286
        let scale = min(maximumScale, max(0.5, requestedScale))
        panel.setContentSize(NSSize(width: 286 * scale, height: 104 * scale))
        bubbleView.scale = scale
    }

    private func position(near petFrame: NSRect, on screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let roomAbove = screenFrame.maxY - petFrame.maxY
        let appearsAbove = roomAbove >= size.height + 10
        bubbleView.pointsDown = appearsAbove

        let unclampedX = petFrame.midX - size.width / 2
        let x = min(
            max(unclampedX, screenFrame.minX + 8),
            screenFrame.maxX - size.width - 8
        )
        let y = appearsAbove
            ? petFrame.maxY + 4
            : petFrame.minY - size.height - 4

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak panel] in
                panel?.orderOut(nil)
            }
        )
    }
}

final class PetBubblePanel: NSPanel {
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
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetBubbleView: NSView {
    var scale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }
    var message = "" {
        didSet { needsDisplay = true }
    }
    var pointsDown = true {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        let mainRect = NSRect(
            x: 8,
            y: pointsDown ? 25 : 8,
            width: 286 - 16,
            height: 70
        )

        NSColor.white.withAlphaComponent(0.97).setFill()
        let bubble = NSBezierPath(roundedRect: mainRect, xRadius: 24, yRadius: 24)
        bubble.fill()
        NSColor(calibratedWhite: 0.18, alpha: 0.16).setStroke()
        bubble.lineWidth = 1.5
        bubble.stroke()

        let cloudY: CGFloat = pointsDown ? 14 : 91
        let cloudX: CGFloat = 143 + 38
        NSColor.white.withAlphaComponent(0.97).setFill()
        NSBezierPath(ovalIn: NSRect(x: cloudX, y: cloudY, width: 17, height: 17)).fill()
        NSBezierPath(
            ovalIn: NSRect(
                x: cloudX + 20,
                y: pointsDown ? cloudY - 8 : cloudY + 3,
                width: 10,
                height: 10
            )
        ).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(
            string: "☁️  \(message)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
                .paragraphStyle: paragraph
            ]
        )
        text.draw(
            in: NSRect(
                x: mainRect.minX + 16,
                y: mainRect.minY + 22,
                width: mainRect.width - 32,
                height: 28
            )
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
