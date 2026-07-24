import AppKit
import Foundation
import UniformTypeIdentifiers

enum PetAssetStore {
    private static let pathKey = "BoomPet.customPetImagePath"

    static var customImage: NSImage? {
        guard let path = UserDefaults.standard.string(forKey: pathKey) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    static var hasCustomImage: Bool {
        customImage != nil
    }

    static func chooseImage() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择桌面宠物图片 / Choose a pet image"
        panel.prompt = "自动抠图并使用"
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return false
        }

        do {
            let supportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("BoomPet", isDirectory: true)
            try FileManager.default.createDirectory(
                at: supportURL,
                withIntermediateDirectories: true
            )

            let destinationURL = supportURL.appendingPathComponent("custom-pet.png")
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            guard let image = NSImage(contentsOf: sourceURL),
                  let processedData = PetImageProcessor.automaticCutoutPNG(from: image) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try processedData.write(to: destinationURL, options: .atomic)
            UserDefaults.standard.set(destinationURL.path, forKey: pathKey)
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "无法使用这张图片"
            alert.runModal()
            return false
        }
    }

    static func restoreDefault() {
        UserDefaults.standard.removeObject(forKey: pathKey)
    }
}
