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
    private let behaviorEngine = PetBehaviorEngine()
    private let bubbleController = PetBubbleController()
    private weak var languageStore: LanguageStore?
    private var trackingTimer: Timer?
    private var roamTimer: Timer?
    private var idleTimer: Timer?
    private var currentScreenNumber: NSNumber?
    private var isDragging = false
    private var isTemporarilyHidden = false
    private var dockEdge: PetDockEdge?

    private let positionXKey = "BoomPet.petPositionX"
    private let positionYKey = "BoomPet.petPositionY"
    private let autoRoamKey = "BoomPet.petAutoRoam"
    private let dialogueEnabledKey = "BoomPet.petDialogueEnabled"
    private let dockEdgeKey = "BoomPet.petDockEdge"
    private let petSizeKey = "BoomPet.petSize"

    init(
        onOpenSettings: @escaping () -> Void,
        onTestBoom: @escaping () -> Void,
        onStartOCR: @escaping () -> Void,
        onShowOCRHistory: @escaping () -> Void,
        onStartSticky: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        languageStore: LanguageStore
    ) {
        self.languageStore = languageStore
        let savedSize = UserDefaults.standard.double(forKey: petSizeKey)
        let side = CGFloat(min(260, max(80, savedSize > 0 ? savedSize : 154)))
        let size = NSSize(width: side, height: side)
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
        petView.onStartOCR = onStartOCR
        petView.onShowOCRHistory = onShowOCRHistory
        petView.onStartSticky = onStartSticky
        petView.onCheckUpdates = onCheckUpdates
        petView.onDragStateChanged = { [weak self] dragging in
            self?.isDragging = dragging
            if dragging {
                self?.showInteraction(.drag, bypassCooldown: true)
                self?.leaveDockForDragging()
            }
        }
        petView.onDragEnded = { [weak self] in
            self?.saveCurrentPosition()
        }
        petView.onDragMoved = { [weak self] in
            self?.repositionBubble()
        }
        petView.onHover = { [weak self] in
            self?.showInteraction(.hover)
        }
        petView.onTapped = { [weak self] in
            guard let self else { return }
            if dockEdge != nil {
                restoreFromDock()
            } else {
                showInteraction(.tap)
            }
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
            withTimeInterval: 3.2,
            repeats: true
        ) { [weak self] _ in
            self?.performSmallRoam()
        }
        RunLoop.main.add(roamTimer!, forMode: .common)

        idleTimer = Timer.scheduledTimer(
            withTimeInterval: 11,
            repeats: true
        ) { [weak self] _ in
            self?.performIdleInteraction()
        }
        RunLoop.main.add(idleTimer!, forMode: .common)
    }

    func stop() {
        trackingTimer?.invalidate()
        roamTimer?.invalidate()
        idleTimer?.invalidate()
        trackingTimer = nil
        roamTimer = nil
        idleTimer = nil
        bubbleController.hide()
        panel.close()
    }

    func reloadImage() {
        petView.reloadArtwork()
    }

    func updateSize(_ requestedSize: CGFloat) {
        let side = min(260, max(80, requestedSize))
        let oldCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        panel.setContentSize(NSSize(width: side, height: side))
        let candidate = NSPoint(
            x: oldCenter.x - side / 2,
            y: oldCenter.y - side / 2
        )
        if let screen = screen(at: oldCenter) {
            panel.setFrameOrigin(clampedOrigin(candidate, in: screen))
        }
        UserDefaults.standard.set(Double(side), forKey: petSizeKey)
        saveCurrentPosition()
        repositionBubble()
    }

    func showSystemMessage(_ message: String) {
        guard let screen = screen(
            at: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        ) else {
            return
        }
        bubbleController.show(message: message, near: panel.frame, on: screen)
    }

    func setTemporarilyHidden(_ hidden: Bool) {
        isTemporarilyHidden = hidden
        if hidden {
            bubbleController.hide()
            panel.orderOut(nil)
        } else {
            moveToMouseScreen(force: true)
            panel.orderFrontRegardless()
        }
    }

    private func moveToMouseScreen(force: Bool = false) {
        guard !isDragging, !isTemporarilyHidden else { return }
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

        let current = panel.frame.origin
        let available = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        let target: NSPoint
        if behaviorEngine.shouldStartLongRoam || Int.random(in: 0..<100) < 72 {
            target = clampedOrigin(
                NSPoint(
                    x: CGFloat.random(
                        in: available.minX...(available.maxX - panel.frame.width)
                    ),
                    y: CGFloat.random(
                        in: available.minY...(available.maxY - panel.frame.height)
                    )
                ),
                in: screen
            )
        } else {
            target = clampedOrigin(
                NSPoint(
                    x: current.x + CGFloat.random(in: -180...180),
                    y: current.y + CGFloat.random(in: -85...85)
                ),
                in: screen
            )
        }

        let distance = hypot(target.x - current.x, target.y - current.y)
        petView.setMoving(true, facingRight: target.x >= current.x)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = min(2.75, max(0.8, Double(distance / 230)))
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(target)
        } completionHandler: { [weak self] in
            guard let self else { return }
            petView.setMoving(false, facingRight: target.x >= current.x)
            repositionBubble()
            if behaviorEngine.shouldSpeakWhileRoaming {
                showInteraction(.roam)
            }
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
            bubbleController.hide()
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

    private func restoreFromDock() {
        guard dockEdge != nil,
              let screen = screen(at: NSPoint(x: panel.frame.midX, y: panel.frame.midY)) else {
            return
        }
        dockEdge = nil
        petView.peekEdge = nil
        UserDefaults.standard.removeObject(forKey: dockEdgeKey)
        panel.setFrameOrigin(undockedSavedOrigin(in: screen))
        showInteraction(.returnFromDock, bypassCooldown: true)
    }

    private func performIdleInteraction() {
        guard !isDragging,
              dockEdge == nil,
              Int.random(in: 0..<100) < 38 else {
            return
        }
        showInteraction(.idle)
    }

    private func showInteraction(
        _ event: PetInteractionEvent,
        bypassCooldown: Bool = false
    ) {
        guard UserDefaults.standard.bool(forKey: dialogueEnabledKey),
              let languageStore,
              let message = behaviorEngine.message(
                for: event,
                language: languageStore,
                bypassCooldown: bypassCooldown
              ),
              let screen = screen(
                at: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
              ) else {
            return
        }
        bubbleController.show(message: message, near: panel.frame, on: screen)
    }

    private func repositionBubble() {
        guard let screen = screen(
            at: NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        ) else {
            return
        }
        bubbleController.reposition(near: panel.frame, on: screen)
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
    private var spriteParts: [NSImage]? = AssetLoader.petSpriteParts()
    weak var languageStore: LanguageStore?
    var peekEdge: PetDockEdge? {
        didSet { needsDisplay = true }
    }
    var onOpenSettings: (() -> Void)?
    var onTestBoom: (() -> Void)?
    var onStartOCR: (() -> Void)?
    var onShowOCRHistory: (() -> Void)?
    var onStartSticky: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDragMoved: (() -> Void)?
    var onHover: (() -> Void)?
    var onTapped: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var didDrag = false
    private var animationTimer: Timer?
    private var lastAnimationFrame = Date.distantPast
    private var isMoving = false
    private var facingRight = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) {
            [weak self] _ in self?.animationTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        animationTimer?.invalidate()
    }

    func reloadArtwork() {
        image = AssetLoader.petImage()
        spriteParts = AssetLoader.petSpriteParts()
        needsDisplay = true
    }

    func setMoving(_ moving: Bool, facingRight: Bool) {
        isMoving = moving
        self.facingRight = facingRight
        needsDisplay = true
    }

    private func animationTick() {
        guard window?.isVisible == true else { return }
        let now = Date()
        let interval: TimeInterval = (isMoving || didDrag) ? (1.0 / 12.0) : 0.5
        guard now.timeIntervalSince(lastAnimationFrame) >= interval else { return }
        lastAnimationFrame = now
        needsDisplay = true
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
            drawDockIcon(at: peekEdge)
            return
        }
        if let spriteParts, spriteParts.count == 8 {
            drawAnimatedPet(parts: spriteParts)
        } else {
            let time = CACurrentMediaTime()
            let bounce = sin(time * (isMoving ? 8 : 2.2)) * (isMoving ? 4 : 1.4)
            drawTransformed(
                image,
                in: bounds.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: bounce),
                rotation: sin(time * 2.1) * (isMoving ? 0.045 : 0.012)
            )
        }
    }

    override func mouseEntered(with event: NSEvent) {
        animateScale(to: 1.06)
        onHover?()
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
        setMoving(true, facingRight: deltaX >= 0)
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
        onDragMoved?()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
        }

        if didDrag {
            setMoving(false, facingRight: facingRight)
            onDragStateChanged?(false)
            onDragEnded?()
            didDrag = false
            return
        }

        onTapped?()
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
            withTitle: text("屏幕 OCR  ⌥S", "Screen OCR  ⌥S"),
            action: #selector(startOCR),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: text("历史记录  ⌘⇧V", "History  ⌘⇧V"),
            action: #selector(showOCRHistory),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: text("选区贴图  ⌥T", "Sticky Capture  ⌥T"),
            action: #selector(startSticky),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: text("设置…", "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(
            withTitle: text("立即测试 BOOM", "Preview BOOM"),
            action: #selector(testBoom),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: text("检查更新…", "Check for Updates…"),
            action: #selector(checkUpdates),
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

    @objc private func startOCR() {
        onStartOCR?()
    }

    @objc private func showOCRHistory() {
        onShowOCRHistory?()
    }

    @objc private func startSticky() {
        onStartSticky?()
    }

    @objc private func checkUpdates() {
        onCheckUpdates?()
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

    private func drawAnimatedPet(parts: [NSImage]) {
        let time = CACurrentMediaTime()
        let cadence = isMoving ? 9.5 : 2.2
        let step = sin(time * cadence)
        let bounce = abs(sin(time * cadence)) * (isMoving ? 5.0 : 1.5)
        let blink = fmod(time, 4.1) < 0.14 ? 0.12 : 1.0

        NSGraphicsContext.saveGraphicsState()
        let scale = bounds.width / 154
        let sizeTransform = NSAffineTransform()
        sizeTransform.scale(by: scale)
        sizeTransform.concat()
        if !facingRight, let context = NSGraphicsContext.current?.cgContext {
            context.translateBy(x: 154, y: 0)
            context.scaleBy(x: -1, y: 1)
        }

        drawTransformed(
            parts[7],
            in: NSRect(x: 99, y: 16 + bounce * 0.3, width: 49, height: 84),
            rotation: step * (isMoving ? 0.30 : 0.16),
            anchor: NSPoint(x: 0.2, y: 0.2)
        )
        drawTransformed(
            parts[0],
            in: NSRect(x: 17, y: 4 + bounce, width: 91, height: 81),
            rotation: step * (isMoving ? 0.025 : 0.008)
        )
        drawTransformed(
            parts[2],
            in: NSRect(x: 24, y: 105 + bounce, width: 34, height: 43),
            rotation: -0.08 + step * 0.08,
            anchor: NSPoint(x: 0.7, y: 0.1)
        )
        drawTransformed(
            parts[3],
            in: NSRect(x: 101, y: 105 + bounce, width: 35, height: 43),
            rotation: 0.08 - step * 0.08,
            anchor: NSPoint(x: 0.3, y: 0.1)
        )
        let headBob = bounce + sin(time * 2.6) * 1.2
        drawTransformed(
            parts[1],
            in: NSRect(x: 27, y: 51 + headBob, width: 105, height: 91),
            rotation: step * (isMoving ? 0.035 : 0.012)
        )
        drawTransformed(
            parts[4],
            in: NSRect(x: 45, y: 83 + headBob, width: 67, height: 29),
            scaleY: blink
        )
        drawTransformed(
            parts[5],
            in: NSRect(x: 65, y: 68 + headBob, width: 28, height: 20),
            scaleY: 0.88 + abs(step) * (isMoving ? 0.25 : 0.08)
        )
        drawTransformed(
            parts[6],
            in: NSRect(
                x: 43 + step * (isMoving ? 2 : 0.4),
                y: 25 + bounce,
                width: 64,
                height: 51
            ),
            rotation: step * (isMoving ? 0.07 : 0.015)
        )

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTransformed(
        _ image: NSImage,
        in rect: NSRect,
        rotation: CGFloat = 0,
        scaleY: CGFloat = 1,
        anchor: NSPoint = NSPoint(x: 0.5, y: 0.5)
    ) {
        NSGraphicsContext.saveGraphicsState()
        let pivot = NSPoint(
            x: rect.minX + rect.width * anchor.x,
            y: rect.minY + rect.height * anchor.y
        )
        let transform = NSAffineTransform()
        transform.translateX(by: pivot.x, yBy: pivot.y)
        transform.rotate(byRadians: rotation)
        transform.scaleX(by: 1, yBy: scaleY)
        transform.translateX(by: -pivot.x, yBy: -pivot.y)
        transform.concat()
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let peekEdge, !dockIconRect(for: peekEdge).contains(point) {
            return nil
        }
        return super.hitTest(point)
    }

    private func drawDockIcon(at edge: PetDockEdge) {
        let targetRect = dockIconRect(for: edge)
        let background = NSBezierPath(
            roundedRect: targetRect,
            xRadius: targetRect.width / 2,
            yRadius: targetRect.height / 2
        )
        NSGradient(
            starting: .systemOrange,
            ending: .systemPink
        )?.draw(in: background, angle: -55)

        NSColor.white.withAlphaComponent(0.82).setStroke()
        background.lineWidth = 2
        background.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let icon = NSAttributedString(
            string: "🐾",
            attributes: [
                .font: NSFont.systemFont(ofSize: 29),
                .paragraphStyle: paragraph
            ]
        )
        icon.draw(
            in: NSRect(
                x: targetRect.minX,
                y: targetRect.minY + 9,
                width: targetRect.width,
                height: 38
            )
        )
    }

    private func dockIconRect(for edge: PetDockEdge) -> NSRect {
        let revealSize: CGFloat = 58
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

        return targetRect
    }
}
