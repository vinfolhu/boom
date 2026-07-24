import AppKit

enum AssetLoader {
    static func petImage() -> NSImage {
        if let customImage = PetAssetStore.customImage {
            return customImage
        }

        if let image = NSImage(named: "pet") {
            return image
        }

        if let url = Bundle.main.url(forResource: "pet", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: "pet", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "宠物") ?? NSImage()
    }
}
