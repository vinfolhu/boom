import AppKit

private func migrateLegacyBundleDefaultsIfNeeded() {
    let defaults = UserDefaults.standard
    let marker = "BoomPet.didMigrateBundleIdentifierDefaults"
    guard !defaults.bool(forKey: marker) else { return }

    let legacyBundleIdentifier = "com.local.BoomPet"
    let currentBundleIdentifier = "com.vinfol.boom"
    let legacy = defaults.persistentDomain(
        forName: legacyBundleIdentifier
    ) ?? [:]
    let current = defaults.persistentDomain(
        forName: currentBundleIdentifier
    ) ?? [:]

    for (key, value) in legacy where current[key] == nil {
        defaults.set(value, forKey: key)
    }
    defaults.set(true, forKey: marker)
}

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

if let iconIndex = CommandLine.arguments.firstIndex(
    of: "--render-app-icon"
), CommandLine.arguments.indices.contains(iconIndex + 1) {
    exit(renderAppIcon(
        to: URL(fileURLWithPath: CommandLine.arguments[iconIndex + 1])
    ))
}

migrateLegacyBundleDefaultsIfNeeded()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
