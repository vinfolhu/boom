import AppKit
import QuartzCore

final class BoomController {
    private var overlay: BoomPanel?
    private var queuedMessages: [String] = []

    func show(message: String, headline: String) {
        if overlay != nil {
            queuedMessages.append("\(headline)\u{1F}\(message)")
            return
        }
        present(message: message, headline: headline)
    }

    private func present(message: String, headline: String) {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
                ?? NSScreen.main else {
            return
        }

        let panel = BoomPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let view = BoomView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.message = message
        view.headline = headline
        view.petImage = AssetLoader.petImage()
        view.onFinished = { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.close()
            self?.overlay = nil
            if let queued = self?.queuedMessages.first {
                self?.queuedMessages.removeFirst()
                let parts = queued.split(
                    separator: "\u{1F}",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                )
                let nextHeadline = parts.first.map(String.init) ?? "BOOM time!"
                let nextMessage = parts.count > 1 ? String(parts[1]) : queued
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self?.present(message: nextMessage, headline: nextHeadline)
                }
            }
        }
        panel.contentView = view
        overlay = panel
        panel.orderFrontRegardless()
        view.start()
    }
}

final class BoomPanel: NSPanel {
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
        hasShadow = false
        level = .screenSaver
        hidesOnDeactivate = false
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

final class BoomView: NSView {
    var message = "休息一下"
    var headline = "BOOM时间到。"
    var petImage = NSImage()
    var onFinished: (() -> Void)?

    private var displayTimer: Timer?
    private var startTime: CFTimeInterval = 0
    private let duration: CFTimeInterval = 4.6

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayTimer?.invalidate()
    }

    func start() {
        startTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func mouseDown(with event: NSEvent) {
        finish()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let elapsed = CACurrentMediaTime() - startTime
        let impactProgress = max(0, min(1, CGFloat((elapsed - 0.52) / 0.55)))
        let shakeStrength = max(0, 1 - impactProgress) * 18
        let center = CGPoint(
            x: bounds.midX + sin(CGFloat(elapsed) * 83) * shakeStrength,
            y: bounds.midY + cos(CGFloat(elapsed) * 67) * shakeStrength
        )

        drawBackdrop(elapsed: elapsed)
        drawComicRays(center: center, elapsed: elapsed)
        drawExplosion(center: center, elapsed: elapsed)
        drawPet(center: center, elapsed: elapsed)
        drawText(center: center, elapsed: elapsed)
        drawDismissHint()
    }

    private func drawBackdrop(elapsed: CFTimeInterval) {
        let fadeIn = min(1, CGFloat(elapsed / 0.22))
        let fadeOut = elapsed > 4.0 ? max(0, CGFloat((duration - elapsed) / 0.6)) : 1
        NSColor(
            calibratedRed: 0.035,
            green: 0.018,
            blue: 0.075,
            alpha: 0.94 * fadeIn * fadeOut
        ).setFill()
        bounds.fill()

        let glowProgress = min(1, CGFloat(elapsed / 0.75))
        let glowRect = bounds.insetBy(
            dx: bounds.width * (0.06 + glowProgress * 0.08),
            dy: bounds.height * (0.06 + glowProgress * 0.08)
        )
        let glow = NSGradient(colors: [
            NSColor.systemPurple.withAlphaComponent(0.26 * fadeOut),
            NSColor.clear
        ])
        glow?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
    }

    private func drawComicRays(center: CGPoint, elapsed: CFTimeInterval) {
        guard elapsed > 0.42 else { return }
        let progress = min(1, CGFloat((elapsed - 0.42) / 0.45))
        let outerRadius = hypot(bounds.width, bounds.height) * 0.65
        let innerRadius = 105 + progress * 62

        for index in 0..<28 {
            let baseAngle = CGFloat(index) / 28 * .pi * 2
            let halfWidth: CGFloat = index.isMultiple(of: 3) ? 0.045 : 0.022
            let path = NSBezierPath()
            path.move(to: CGPoint(
                x: center.x + cos(baseAngle - halfWidth) * innerRadius,
                y: center.y + sin(baseAngle - halfWidth) * innerRadius
            ))
            path.line(to: CGPoint(
                x: center.x + cos(baseAngle) * outerRadius * progress,
                y: center.y + sin(baseAngle) * outerRadius * progress
            ))
            path.line(to: CGPoint(
                x: center.x + cos(baseAngle + halfWidth) * innerRadius,
                y: center.y + sin(baseAngle + halfWidth) * innerRadius
            ))
            path.close()
            let alpha = index.isMultiple(of: 2) ? 0.34 : 0.18
            NSColor.systemYellow.withAlphaComponent(alpha * progress).setFill()
            path.fill()
        }
    }

    private func drawExplosion(center: CGPoint, elapsed: CFTimeInterval) {
        guard elapsed > 0.5 else { return }
        let progress = min(1, CGFloat((elapsed - 0.5) / 1.15))
        let eased = 1 - pow(1 - progress, 3)

        for ring in 0..<3 {
            let ringProgress = max(0, min(1, progress * 1.45 - CGFloat(ring) * 0.2))
            let radius = 45 + ringProgress * (190 + CGFloat(ring) * 75)
            let oval = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            oval.lineWidth = max(2, 22 * (1 - ringProgress))
            NSColor.white.withAlphaComponent(0.72 * (1 - ringProgress)).setStroke()
            oval.stroke()
        }

        for index in 0..<34 {
            let angle = CGFloat(index) / 34 * .pi * 2 + CGFloat(index % 5) * 0.08
            let distance = eased * min(bounds.width, bounds.height) * 0.48
            let particleRadius = 7 + CGFloat(index % 5) * 5
            let point = CGPoint(
                x: center.x + cos(angle) * distance * (0.62 + CGFloat(index % 4) * 0.11),
                y: center.y + sin(angle) * distance * (0.62 + CGFloat(index % 4) * 0.11)
            )
            let color: NSColor = index.isMultiple(of: 3)
                ? .systemPink
                : (index.isMultiple(of: 2) ? .systemYellow : .systemOrange)
            color.withAlphaComponent(1 - progress * 0.72).setFill()

            let diamond = NSBezierPath()
            diamond.move(to: CGPoint(x: point.x, y: point.y + particleRadius))
            diamond.line(to: CGPoint(x: point.x + particleRadius * 0.55, y: point.y))
            diamond.line(to: CGPoint(x: point.x, y: point.y - particleRadius))
            diamond.line(to: CGPoint(x: point.x - particleRadius * 0.55, y: point.y))
            diamond.close()
            diamond.fill()
        }

        let coreRadius = 65 + eased * 185
        let corePath = NSBezierPath()
        let points = 24
        for index in 0..<points {
            let angle = CGFloat(index) / CGFloat(points) * .pi * 2
            let spike = index.isMultiple(of: 2) ? coreRadius : coreRadius * 0.63
            let point = CGPoint(
                x: center.x + cos(angle) * spike,
                y: center.y + sin(angle) * spike
            )
            index == 0 ? corePath.move(to: point) : corePath.line(to: point)
        }
        corePath.close()
        NSColor.systemOrange.withAlphaComponent(max(0, 0.94 - progress * 0.48)).setFill()
        corePath.fill()

        let innerRadius = coreRadius * 0.55
        NSColor.systemYellow.withAlphaComponent(max(0, 1 - progress * 0.42)).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )).fill()
    }

    private func drawPet(center: CGPoint, elapsed: CFTimeInterval) {
        let entry = min(1, CGFloat(elapsed / 0.5))
        let bounce = 1 + sin(min(CGFloat(elapsed), 1.5) * 12) * max(0, 1 - CGFloat(elapsed) / 1.5) * 0.09
        let size = min(bounds.width, bounds.height) * 0.29 * entry * bounce
        let rect = NSRect(
            x: center.x - size / 2,
            y: center.y - size * 0.40,
            width: size,
            height: size
        )
        petImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawText(center: CGPoint, elapsed: CFTimeInterval) {
        guard elapsed > 0.55 else { return }
        let boomScale = min(1, CGFloat((elapsed - 0.55) / 0.22))
        let boom = NSAttributedString(
            string: "BOOM!",
            attributes: [
                .font: NSFont.systemFont(ofSize: 116 * boomScale, weight: .black),
                .foregroundColor: NSColor.systemYellow,
                .strokeColor: NSColor.black,
                .strokeWidth: -10,
                .shadow: textShadow()
            ]
        )
        let boomSize = boom.size()
        boom.draw(at: CGPoint(x: center.x - boomSize.width / 2, y: center.y + 128))

        guard elapsed > 1.15 else { return }
        let labelText = NSAttributedString(
            string: headline,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: NSColor.systemYellow
            ]
        )
        let messageText = NSAttributedString(
            string: message,
            attributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .heavy),
                .foregroundColor: NSColor.white,
                .paragraphStyle: centeredParagraphStyle()
            ]
        )

        let cardWidth = min(bounds.width * 0.72, 720)
        let cardRect = NSRect(
            x: center.x - cardWidth / 2,
            y: center.y - 250,
            width: cardWidth,
            height: 106
        )
        NSColor.black.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: cardRect, xRadius: 24, yRadius: 24).fill()

        let labelSize = labelText.size()
        labelText.draw(at: CGPoint(
            x: center.x - labelSize.width / 2,
            y: cardRect.maxY - 32
        ))
        messageText.draw(
            in: NSRect(
                x: cardRect.minX + 24,
                y: cardRect.minY + 18,
                width: cardRect.width - 48,
                height: 48
            )
        )
    }

    private func drawDismissHint() {
        let hint = NSAttributedString(
            string: "点击任意位置关闭",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.white.withAlphaComponent(0.55)
            ]
        )
        let size = hint.size()
        hint.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: 28))
    }

    private func updateFrame() {
        let elapsed = CACurrentMediaTime() - startTime
        if elapsed >= duration {
            finish()
        } else {
            needsDisplay = true
        }
    }

    private func finish() {
        displayTimer?.invalidate()
        displayTimer = nil
        onFinished?()
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    private func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.systemPink.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        return shadow
    }
}
