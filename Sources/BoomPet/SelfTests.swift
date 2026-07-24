import AppKit
import Foundation

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
        "PASS: 提醒调度、标题修改、自动抠图、本地行为引擎、语言检测、版本比较、Vision OCR"
    )
    return 0
}
