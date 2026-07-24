import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTests())
}

if let previewIndex = CommandLine.arguments.firstIndex(
    of: "--render-rig-preview"
), CommandLine.arguments.indices.contains(previewIndex + 1) {
    exit(renderRigPreview(
        to: URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1])
    ))
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
