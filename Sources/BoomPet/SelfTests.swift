import AppKit
import Foundation

func renderAppIcon(to outputURL: URL) -> Int32 {
    guard let directory = PetRigStore.bundledDirectory,
          let rig = try? PetRigRuntime(directory: directory) else {
        fputs("Unable to load the bundled pet rig.\n", stderr)
        return 1
    }

    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

    let bounds = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    bounds.fill()

    let iconRect = bounds.insetBy(dx: 54, dy: 54)
    let iconShape = NSBezierPath(
        roundedRect: iconRect,
        xRadius: 205,
        yRadius: 205
    )
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor(calibratedRed: 0.92, green: 0.24, blue: 0.07, alpha: 1)
        .setFill()
    iconShape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    iconShape.addClip()
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.08, alpha: 1)
    ])
    background?.draw(in: iconRect, angle: -55)

    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(ovalIn: NSRect(x: 88, y: 570, width: 330, height: 330)).fill()
    NSBezierPath(ovalIn: NSRect(x: 735, y: 720, width: 105, height: 105)).fill()
    NSColor(calibratedRed: 0.65, green: 0.05, blue: 0.01, alpha: 0.10)
        .setFill()
    NSBezierPath(ovalIn: NSRect(x: 730, y: 105, width: 250, height: 250)).fill()

    rig.draw(
        animation: "idle",
        elapsed: 0.35,
        in: NSRect(x: 135, y: 105, width: 754, height: 754),
        facingRight: true
    )
    NSGraphicsContext.restoreGraphicsState()

    let innerHighlight = NSBezierPath(
        roundedRect: iconRect.insetBy(dx: 5, dy: 5),
        xRadius: 200,
        yRadius: 200
    )
    NSColor.white.withAlphaComponent(0.32).setStroke()
    innerHighlight.lineWidth = 9
    innerHighlight.stroke()
    image.unlockFocus()

    guard let cgImage = image.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
    ) else {
        return 1
    }
    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let png = representation.representation(
        using: .png,
        properties: [:]
    ) else {
        return 1
    }
    do {
        try png.write(to: outputURL, options: .atomic)
        return 0
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        return 1
    }
}

func renderRigPreview(to outputURL: URL) -> Int32 {
    guard let directory = PetRigStore.activeDirectory,
          let rig = try? PetRigRuntime(directory: directory) else {
        fputs("Unable to load the active pet rig.\n", stderr)
        return 1
    }
    let animations = ["idle", "walk", "run", "crawl"]
    let phases: [CGFloat] = [0, 0.25, 0.5, 0.75]
    let cellSize = NSSize(width: 190, height: 190)
    let image = NSImage(size: NSSize(
        width: cellSize.width * CGFloat(animations.count),
        height: cellSize.height * CGFloat(phases.count)
    ))
    image.lockFocus()
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSRect(origin: .zero, size: image.size).fill()

    for (column, name) in animations.enumerated() {
        let duration = rig.manifest.animations[name]?.duration ?? 1
        for (row, phase) in phases.enumerated() {
            let rect = NSRect(
                x: CGFloat(column) * cellSize.width + 10,
                y: CGFloat(phases.count - row - 1) * cellSize.height + 10,
                width: cellSize.width - 20,
                height: cellSize.height - 20
            )
            rig.draw(
                animation: name,
                elapsed: duration * Double(phase),
                in: rect,
                facingRight: true
            )
            if row == 0 {
                let label = NSAttributedString(
                    string: name,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: NSColor.black
                    ]
                )
                label.draw(at: NSPoint(
                    x: CGFloat(column) * cellSize.width + 8,
                    y: image.size.height - 20
                ))
            }
        }
    }
    image.unlockFocus()

    guard let cgImage = image.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
    ) else {
        return 1
    }
    let representation = NSBitmapImageRep(cgImage: cgImage)
    guard let png = representation.representation(
        using: .png,
        properties: [:]
    ) else {
        return 1
    }
    do {
        try png.write(to: outputURL, options: .atomic)
        print(outputURL.path)
        return 0
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        return 1
    }
}

func runSelfTests() -> Int32 {
    let testKey = "BoomPet.self-test.\(UUID().uuidString)"
    defer {
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    let store = ReminderStore(defaultsKey: testKey)
    guard store.reminders.isEmpty else {
        fputs("FAIL: 新任务存储必须为空\n", stderr)
        return 1
    }

    store.add(title: "活动一下", intervalMinutes: 1)
    guard let firstFire = store.reminders.first?.nextFireDate else {
        fputs("FAIL: 新任务没有下次触发时间\n", stderr)
        return 1
    }

    let calendar = Calendar.current
    guard calendar.component(.second, from: firstFire) == 0 else {
        fputs("FAIL: 首次触发时间没有对齐到整分钟\n", stderr)
        return 1
    }

    let due = store.dueReminders(at: firstFire.addingTimeInterval(0.15))
    guard due.count == 1, let secondFire = store.reminders.first?.nextFireDate else {
        fputs("FAIL: 到期任务没有正确触发\n", stderr)
        return 1
    }

    guard abs(secondFire.timeIntervalSince(firstFire) - 60) < 0.001,
          calendar.component(.second, from: secondFire) == 0 else {
        fputs("FAIL: 重复任务发生时间漂移\n", stderr)
        return 1
    }

    store.setTitle(id: due[0].id, title: "新提醒内容")
    guard store.reminders.first?.title == "新提醒内容" else {
        fputs("FAIL: 任务标题无法修改\n", stderr)
        return 1
    }

    let sampleImage = NSImage(size: NSSize(width: 100, height: 100))
    sampleImage.lockFocus()
    NSColor.magenta.setFill()
    NSRect(x: 0, y: 0, width: 100, height: 100).fill()
    NSColor.systemBlue.setFill()
    NSRect(x: 30, y: 25, width: 40, height: 50).fill()
    sampleImage.unlockFocus()

    guard let processedData = PetImageProcessor.automaticCutoutPNG(from: sampleImage),
          let processed = NSBitmapImageRep(data: processedData) else {
        fputs("FAIL: 自动抠图没有移除纯色边缘并裁切\n", stderr)
        return 1
    }
    guard let sourceCGImage = sampleImage.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
    ),
    processed.pixelsWide < Int(Double(sourceCGImage.width) * 0.75),
    processed.pixelsHigh < Int(Double(sourceCGImage.height) * 0.85) else {
        fputs(
            "FAIL: 自动抠图尺寸异常 \(processed.pixelsWide)x\(processed.pixelsHigh)\n",
            stderr
        )
        return 1
    }

    let language = LanguageStore()
    let behavior = PetBehaviorEngine()
    guard behavior.message(
        for: .hover,
        language: language,
        bypassCooldown: true
    ) != nil,
    behavior.message(for: .tap, language: language) == nil,
    behavior.message(
        for: .drag,
        language: language,
        bypassCooldown: true
    ) != nil else {
        fputs("FAIL: 宠物行为台词或冷却时间异常\n", stderr)
        return 1
    }

    guard TranslationService.detectedSourceLanguage(for: "Hello world") == "en",
          TranslationService.detectedSourceLanguage(for: "你好，世界") == "zh",
          TranslationService.defaultTargetLanguage(for: "Hello") == "zh" else {
        fputs("FAIL: OCR 自动互译方向异常\n", stderr)
        return 1
    }

    guard UpdateService.isNewer("0.2.0", than: "0.1.9"),
          UpdateService.isNewer("1.0.0", than: "0.99.99"),
          !UpdateService.isNewer("0.1.0", than: "0.1.0"),
          !UpdateService.isNewer("0.1.9", than: "0.2.0") else {
        fputs("FAIL: GitHub Release 版本比较异常\n", stderr)
        return 1
    }
    guard let release = UpdateService.releaseInfo(
        from: URL(
            string: "https://github.com/vinfolhu/boom/releases/tag/v0.2.4"
        )!
    ), release.tag == "v0.2.4",
    release.downloadURL.lastPathComponent == "BoomPet-macOS-universal.dmg",
    UpdateService.releaseInfo(
        from: URL(string: "https://github.com/vinfolhu/boom/releases")!
    ) == nil else {
        fputs("FAIL: GitHub Release 网页跳转解析异常\n", stderr)
        return 1
    }

    guard let rigDirectory = PetRigStore.bundledDirectory,
          let rig = try? PetRigRuntime(directory: rigDirectory) else {
        fputs("FAIL: 内置宠物骨骼动作包无法加载\n", stderr)
        return 1
    }
    let requiredParts: Set<String> = [
        "body", "head", "earLeft", "earRight",
        "legFrontLeft", "legFrontRight", "legRearLeft", "legRearRight"
    ]
    let configuredParts = Set(rig.manifest.parts.map(\.id))
    guard requiredParts.isSubset(of: configuredParts),
          ["idle", "walk", "run", "crawl"].allSatisfy({
              rig.manifest.animations[$0] != nil
          }),
          rig.manifest.direction.mirrorWithMovement,
          rig.manifest.movement.runSpeed > rig.manifest.movement.crawlSpeed else {
        fputs("FAIL: 四足、动作、方向或路线配置不完整\n", stderr)
        return 1
    }

    let textImage = NSImage(size: NSSize(width: 520, height: 140))
    textImage.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 520, height: 140).fill()
    let sampleText = NSAttributedString(
        string: "HELLO 123",
        attributes: [
            .font: NSFont.systemFont(ofSize: 58, weight: .bold),
            .foregroundColor: NSColor.black
        ]
    )
    sampleText.draw(at: NSPoint(x: 60, y: 38))
    textImage.unlockFocus()
    guard let textCGImage = textImage.cgImage(
        forProposedRect: nil,
        context: nil,
        hints: nil
    ),
    let recognized = try? VisionOCRService.recognizeSynchronously(textCGImage),
    recognized.uppercased().contains("HELLO") else {
        fputs("FAIL: macOS Vision OCR 自检失败\n", stderr)
        return 1
    }

    print(
        "PASS: 提醒调度、标题修改、自动抠图、本地行为引擎、可配置四足骨骼、语言检测、版本比较、Vision OCR"
    )
    return 0
}
