import AppKit

enum AssetLoader {
    static func petImage() -> NSImage {
        if let customImage = PetAssetStore.customImage {
            return customImage
        }

        if let rig = PetRigStore.loadActive() {
            let image = NSImage(size: NSSize(width: 512, height: 512))
            image.lockFocus()
            rig.draw(
                animation: "idle",
                elapsed: 0.35,
                in: NSRect(x: 0, y: 0, width: 512, height: 512),
                facingRight: true
            )
            image.unlockFocus()
            return image
        }

        return NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "宠物") ?? NSImage()
    }
}
