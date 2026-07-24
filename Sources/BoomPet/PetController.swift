import AppKit
import QuartzCore

enum PetDockEdge: String {
    case left
    case right
    case top
    case bottom
}

final class PetController {
    private let panel: PetPanel
    private let petView: PetView
    private var trackingTimer: Timer?
    private var roamTimer: Timer?
    private var currentScreenNumber: NSNumber?
    private var isDragging = false
    private var dockEdge: PetDockEdge?

    private let positionXKey = "BoomPet.petPositionX"
    private let positionYKey = "BoomPet.petPositionY"
    private let autoRoamKey = "BoomPet.petAutoRoam"
    private let dockEdgeKey = "BoomPet.petDockEdge"

    init(
        onOpenSettings: @escaping () -> Void,
        onTestBoom: @escaping () -> Void,
        languageStore: LanguageStore
    ) {
        let size = NSSize(width: 154, height: 154)
        panel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.image = AssetLoader.petImage()
        petView.languageStore = languageStore
        petView.onOpenSettings = onOpenSettings
        petView.onTestBoom = onTestBoom
        petView.onDragStateChanged = { [weak self] dragging in
            self?.isDragging = dragging
            if dragging {
                self?.leaveDockForDragging()
            }
        }
        petView.onDragEnded = { [weak self] in
            self?.saveCurrentPosition()
        }
        panel.contentView = petView
        if let rawEdge = UserDefaults.standard.string(forKey: dockEdgeKey) {
            dockEdge = PetDockEdge(rawValue: rawEdge)
            petView.peekEdge = dockEdge
        }
    }

    func show() {
        moveToMouseScreen(force: true)
        panel.orderFrontRegardless()
        trackingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            self?.moveToMouseScreen()
        }
        RunLoop.main.add(trackingTimer!, forMode: .common)

        roamTimer = Timer.scheduledTimer(
            withTimeInterval: 4.5,
            repeats: true
        ) { [weak self] _ in
            self?.performSmallRoam()
        }
        RunLoop.main.add(roamTimer!, forMode: .common)
    }

    func stop() {
        trackingTimer?.invalidate()
        roamTimer?.invalidate()
        trackingTimer = nil
        roamTimer = nil
        panel.close()
    }

    func reloadImage() {
        petView.image = AssetLoader.petImage()
        petView.needsDisplay = true
    }

    private func moveToMouseScreen(force: Bool = false) {
        guard !isDragging else { return }
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = screen(at: mouseLocation) else {
            return
        }

        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard force || screenNumber != currentScreenNumber else { return }
        currentScreenNumber = screenNumber

        panel.setFrameOrigin(savedOrigin(in: screen))
        panel.orderFrontRegardless()
    }

    private func performSmallRoam() {
        guard !isDragging,
              dockEdge == nil,
              UserDefaults.standard.bool(forKey: autoRoamKey),
              let screen = screen(at: NSEvent.mouseLocation) else {
            return
        }

        let base = savedOrigin(in: screen)
        let target = clampedOrigin(
            NSPoint(
                x: base.x + CGFloat.random(in: -58...34),
                y: base.y + CGFloat.random(in: -18...42)
            ),
            in: screen
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(target)
        }
    }

    private func saveCurrentPosition() {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = screen(at: center) else { return }
        let frame = screen.visibleFrame
        let edgeThreshold: CGFloat = 30
        let distances: [(PetDockEdge, CGFloat)] = [
            (.left, abs(panel.frame.minX - frame.minX)),
            (.right, abs(panel.frame.maxX - frame.maxX)),
            (.bottom, abs(panel.frame.minY - frame.minY)),
            (.top, abs(panel.frame.maxY - frame.maxY))
        ]

        if let nearest = distances.min(by: { $0.1 < $1.1 }),
           nearest.1 <= edgeThreshold {
            dockEdge = nearest.0
            UserDefaults.standard.set(nearest.0.rawValue, forKey: dockEdgeKey)
            petView.peekEdge = nearest.0
            panel.setFrameOrigin(dockedOrigin(for: nearest.0, in: screen))
        } else {
            dockEdge = nil
            UserDefaults.standard.removeObject(forKey: dockEdgeKey)
            petView.peekEdge = nil
        }

        let availableWidth = max(1, frame.width - panel.frame.width)
        let availableHeight = max(1, frame.height - panel.frame.height)
        let normalizedX = (panel.frame.minX - frame.minX) / availableWidth
        let normalizedY = (panel.frame.minY - frame.minY) / availableHeight

        UserDefaults.standard.set(min(1, max(0, normalizedX)), forKey: positionXKey)
        UserDefaults.standard.set(min(1, max(0, normalizedY)), forKey: positionYKey)
        currentScreenNumber = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber
    }

    private func savedOrigin(in screen: NSScreen) -> NSPoint {
        let defaults = UserDefaults.standard
        let hasSavedPosition = defaults.object(forKey: positionXKey) != nil
        let normalizedX = hasSavedPosition ? defaults.double(forKey: positionXKey) : 1
        let normalizedY = hasSavedPosition ? defaults.double(forKey: positionYKey) : 0
        let frame = screen.visibleFrame

        if let dockEdge {
            return dockedOrigin(for: dockEdge, in: screen)
        }

        return clampedOrigin(
            NSPoint(
                x: frame.minX + (frame.width - panel.frame.width) * normalizedX,
                y: frame.minY + (frame.height - panel.frame.height) * normalizedY
            ),
            in: screen
        )
    }

    private func dockedOrigin(for edge: PetDockEdge, in screen: NSScreen) -> NSPoint {
        let base = undockedSavedOrigin(in: screen)
        let frame = screen.visibleFrame
        switch edge {
        case .left:
            return NSPoint(x: frame.minX, y: base.y)
        case .right:
            return NSPoint(x: frame.maxX - panel.frame.width, y: base.y)
        case .top:
            return NSPoint(x: base.x, y: frame.maxY - panel.frame.height)
        case .bottom:
            return NSPoint(x: base.x, y: frame.minY)
        }
    }

    private func undockedSavedOrigin(in screen: NSScreen) -> NSPoint {
        let defaults = UserDefaults.standard
        let hasSavedPosition = defaults.object(forKey: positionXKey) != nil
        let normalizedX = hasSavedPosition ? defaults.double(forKey: positionXKey) : 1
        let normalizedY = hasSavedPosition ? defaults.double(forKey: positionYKey) : 0
        let frame = screen.visibleFrame
        return clampedOrigin(
            NSPoint(
                x: frame.minX + (frame.width - panel.frame.width) * normalizedX,
                y: frame.minY + (frame.height - panel.frame.height) * normalizedY
            ),
            in: screen
        )
    }

    private func leaveDockForDragging() {
        guard dockEdge != nil else { return }
        dockEdge = nil
        petView.peekEdge = nil
        UserDefaults.standard.removeObject(forKey: dockEdgeKey)
    }

    private func clampedOrigin(_ origin: NSPoint, in screen: NSScreen) -> NSPoint {
        let frame = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        return NSPoint(
            x: min(max(origin.x, frame.minX), frame.maxX - panel.frame.width),
            y: min(max(origin.y, frame.minY), frame.maxY - panel.frame.height)
        )
    }

    private func screen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
    }
}

final class PetPanel: NSPanel {
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
        level = .floating
        hidesOnDeactivate = false
        isMovable = false
        isMovableByWindowBackground = false
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

final class PetView: NSView {
    var image = NSImage()
    weak var languageStore: LanguageStore?
    var peekEdge: PetDockEdge? {
        didSet { needsDisplay = true }
    }
    var onOpenSettings: (() -> Void)?
    var onTestBoom: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragEnded: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let peekEdge {
            drawPeekingHead(at: peekEdge)
            return
        }
        image.draw(
            in: bounds.insetBy(dx: 3, dy: 3),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    override func mouseEntered(with event: NSEvent) {
        animateScale(to: 1.06)
    }

    override func mouseExited(with event: NSEvent) {
        animateScale(to: 1)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel = window,
              let startMouse = dragStartMouseLocation,
              let startOrigin = dragStartWindowOrigin else {
            return
        }

        let mouse = NSEvent.mouseLocation
        let deltaX = mouse.x - startMouse.x
        let deltaY = mouse.y - startMouse.y
        if abs(deltaX) + abs(deltaY) > 3, !didDrag {
            didDrag = true
            onDragStateChanged?(true)
        }

        guard didDrag else { return }
        let targetScreen = NSScreen.screens.first {
            NSMouseInRect(mouse, $0.frame, false)
        } ?? NSScreen.main
        guard let targetScreen else { return }
        let visible = targetScreen.visibleFrame.insetBy(dx: 8, dy: 8)
        let proposed = NSPoint(x: startOrigin.x + deltaX, y: startOrigin.y + deltaY)
        let clamped = NSPoint(
            x: min(max(proposed.x, visible.minX), visible.maxX - panel.frame.width),
            y: min(max(proposed.y, visible.minY), visible.maxY - panel.frame.height)
        )
        panel.setFrameOrigin(clamped)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
        }

        if didDrag {
            onDragStateChanged?(false)
            onDragEnded?()
            didDrag = false
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -0.10, 0.10, -0.05, 0.05, 0]
        animation.duration = 0.42
        layer?.add(animation, forKey: "petWiggle")
    }

    override func rightMouseDown(with event: NSEvent) {
        let text: (String, String) -> String = { [weak self] chinese, english in
            self?.languageStore?.text(chinese, english) ?? chinese
        }
        let menu = NSMenu()
        menu.addItem(
            withTitle: text("提醒设置…", "Reminder Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: text("立即测试 BOOM", "Preview BOOM"),
            action: #selector(testBoom),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: text("退出 BoomPet", "Quit BoomPet"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func testBoom() {
        onTestBoom?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func animateScale(to scale: CGFloat) {
        guard let layer else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1
        animation.toValue = scale
        animation.duration = 0.16
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.setValue(scale, forKeyPath: "transform.scale")
        layer.add(animation, forKey: "petScale")
    }

    private func drawPeekingHead(at edge: PetDockEdge) {
        let revealSize: CGFloat = 70
        let targetRect: NSRect
        switch edge {
        case .left:
            targetRect = NSRect(
                x: 0,
                y: (bounds.height - revealSize) / 2,
                width: revealSize,
                height: revealSize
            )
        case .right:
            targetRect = NSRect(
                x: bounds.width - revealSize,
                y: (bounds.height - revealSize) / 2,
                width: revealSize,
                height: revealSize
            )
        case .top:
            targetRect = NSRect(
                x: (bounds.width - revealSize) / 2,
                y: bounds.height - revealSize,
                width: revealSize,
                height: revealSize
            )
        case .bottom:
            targetRect = NSRect(
                x: (bounds.width - revealSize) / 2,
                y: 0,
                width: revealSize,
                height: revealSize
            )
        }

        let sourceSize = image.size
        let sourceRect = NSRect(
            x: sourceSize.width * 0.12,
            y: sourceSize.height * 0.40,
            width: sourceSize.width * 0.76,
            height: sourceSize.height * 0.58
        )
        image.draw(
            in: targetRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }
}
