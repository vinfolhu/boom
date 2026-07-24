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

    print("PASS: 无默认任务、整分钟触发、周期无漂移、标题可修改、自动抠图")
    return 0
}
