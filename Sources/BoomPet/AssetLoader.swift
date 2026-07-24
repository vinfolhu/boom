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

    static func petSpriteParts() -> [NSImage]? {
        guard !PetAssetStore.hasCustomImage else { return nil }
        let names = [
            "pet-body", "pet-head", "pet-ear-left", "pet-ear-right",
            "pet-eyes", "pet-mouth", "pet-paws", "pet-tail"
        ]
        let parts = names.compactMap(bundledImage(named:))
        return parts.count == names.count ? parts : nil
    }

    private static func bundledImage(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}
