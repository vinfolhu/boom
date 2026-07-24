import AppKit
import Foundation
import UniformTypeIdentifiers

struct PetRigPoint: Codable {
    var x: CGFloat
    var y: CGFloat
}

struct PetRigRect: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    var nsRect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

struct PetRigPartDefinition: Codable {
    var id: String
    var file: String
    var parent: String?
    var zIndex: Int
    var frame: PetRigRect
    var anchor: PetRigPoint
}

struct PetRigKeyframe: Codable {
    var time: CGFloat
    var x: CGFloat?
    var y: CGFloat?
    var rotation: CGFloat?
    var scaleX: CGFloat?
    var scaleY: CGFloat?
}

struct PetRigTrack: Codable {
    var part: String
    var keyframes: [PetRigKeyframe]
}

struct PetRigAnimation: Codable {
    var duration: TimeInterval
    var tracks: [PetRigTrack]
}

struct PetRigDirection: Codable {
    var defaultFacing: String
    var mirrorWithMovement: Bool
}

struct PetRigMovement: Codable {
    var horizontalMargin: CGFloat
    var verticalMargin: CGFloat
    var maxVerticalShift: CGFloat
    var walkSpeed: CGFloat
    var runSpeed: CGFloat
    var crawlSpeed: CGFloat
    var walkWeight: Int
    var runWeight: Int
    var crawlWeight: Int
    var pauseMinimum: TimeInterval
    var pauseMaximum: TimeInterval

    static let fallback = PetRigMovement(
        horizontalMargin: 0.32,
        verticalMargin: 0.20,
        maxVerticalShift: 58,
        walkSpeed: 165,
        runSpeed: 235,
        crawlSpeed: 112,
        walkWeight: 42,
        runWeight: 38,
        crawlWeight: 20,
        pauseMinimum: 0.7,
        pauseMaximum: 2.1
    )
}

struct PetRigManifest: Codable {
    var formatVersion: Int
    var name: String
    var canvas: PetRigPoint
    var direction: PetRigDirection
    var movement: PetRigMovement
    var parts: [PetRigPartDefinition]
    var animations: [String: PetRigAnimation]
}

private struct PetRigTransform {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    func adding(_ other: PetRigTransform) -> PetRigTransform {
        PetRigTransform(
            x: x + other.x,
            y: y + other.y,
            rotation: rotation + other.rotation,
            scaleX: scaleX * other.scaleX,
            scaleY: scaleY * other.scaleY
        )
    }
}

final class PetRigRuntime {
    let manifest: PetRigManifest
    private let images: [String: NSImage]
    private let partsByID: [String: PetRigPartDefinition]

    init(directory: URL) throws {
        let manifestURL = directory.appendingPathComponent("pet-rig.json")
        let data = try Data(contentsOf: manifestURL)
        let decoded = try JSONDecoder().decode(PetRigManifest.self, from: data)
        guard decoded.formatVersion == 1,
              decoded.canvas.x > 0,
              decoded.canvas.y > 0,
              !decoded.parts.isEmpty else {
            throw PetRigError.invalidManifest
        }

        var loadedImages: [String: NSImage] = [:]
        var identifiers = Set<String>()
        for part in decoded.parts {
            guard identifiers.insert(part.id).inserted,
                  part.frame.width > 0,
                  part.frame.height > 0 else {
                throw PetRigError.invalidPart(part.id)
            }
            let safeFilename = URL(fileURLWithPath: part.file).lastPathComponent
            guard safeFilename == part.file,
                  let image = NSImage(
                    contentsOf: directory.appendingPathComponent(safeFilename)
                  ) else {
                throw PetRigError.missingImage(part.file)
            }
            loadedImages[part.id] = image
        }
        for part in decoded.parts {
            if let parent = part.parent, !identifiers.contains(parent) {
                throw PetRigError.invalidParent(part.id, parent)
            }
        }
        for (name, animation) in decoded.animations {
            guard animation.duration > 0 else {
                throw PetRigError.invalidAnimation(name)
            }
            for track in animation.tracks {
                guard identifiers.contains(track.part),
                      !track.keyframes.isEmpty else {
                    throw PetRigError.invalidAnimation(name)
                }
            }
        }

        manifest = decoded
        images = loadedImages
        partsByID = Dictionary(
            uniqueKeysWithValues: decoded.parts.map { ($0.id, $0) }
        )
    }

    func draw(
        animation name: String,
        elapsed: TimeInterval,
        in bounds: NSRect,
        facingRight: Bool
    ) {
        let animation = manifest.animations[name]
            ?? manifest.animations["idle"]
        let duration = max(0.01, animation?.duration ?? 1)
        let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: duration) / duration)
        let transforms = sampledTransforms(animation: animation, phase: phase)

        NSGraphicsContext.saveGraphicsState()
        let scale = min(
            bounds.width / manifest.canvas.x,
            bounds.height / manifest.canvas.y
        )
        let offsetX = bounds.midX - manifest.canvas.x * scale / 2
        let offsetY = bounds.midY - manifest.canvas.y * scale / 2
        let context = NSGraphicsContext.current?.cgContext
        context?.translateBy(x: offsetX, y: offsetY)
        context?.scaleBy(x: scale, y: scale)

        let shouldMirror = manifest.direction.mirrorWithMovement
            && (facingRight != (manifest.direction.defaultFacing == "right"))
        if shouldMirror {
            context?.translateBy(x: manifest.canvas.x, y: 0)
            context?.scaleBy(x: -1, y: 1)
        }

        for part in manifest.parts.sorted(by: { $0.zIndex < $1.zIndex }) {
            guard let image = images[part.id] else { continue }
            NSGraphicsContext.saveGraphicsState()
            applyAncestorTransforms(
                for: part,
                transforms: transforms,
                visited: []
            )
            apply(
                transform: transforms[part.id] ?? PetRigTransform(),
                around: anchorPoint(for: part)
            )
            image.draw(
                in: part.frame.nsRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func sampledTransforms(
        animation: PetRigAnimation?,
        phase: CGFloat
    ) -> [String: PetRigTransform] {
        guard let animation else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: animation.tracks.map {
                ($0.part, sample(keyframes: $0.keyframes, phase: phase))
            }
        )
    }

    private func sample(
        keyframes: [PetRigKeyframe],
        phase: CGFloat
    ) -> PetRigTransform {
        let frames = keyframes.sorted(by: { $0.time < $1.time })
        guard let first = frames.first else { return PetRigTransform() }
        if frames.count == 1 {
            return transform(from: first)
        }

        var previous = frames.last!
        var next = first
        var adjustedPhase = phase
        for index in frames.indices {
            let candidate = frames[index]
            if candidate.time >= phase {
                next = candidate
                previous = index == frames.startIndex ? frames.last! : frames[index - 1]
                break
            }
        }

        let start = previous.time
        var end = next.time
        if end <= start {
            end += 1
            if adjustedPhase < start {
                adjustedPhase += 1
            }
        }
        let amount = end > start ? (adjustedPhase - start) / (end - start) : 0
        let a = transform(from: previous)
        let b = transform(from: next)
        return PetRigTransform(
            x: interpolate(a.x, b.x, amount),
            y: interpolate(a.y, b.y, amount),
            rotation: interpolate(a.rotation, b.rotation, amount),
            scaleX: interpolate(a.scaleX, b.scaleX, amount),
            scaleY: interpolate(a.scaleY, b.scaleY, amount)
        )
    }

    private func transform(from frame: PetRigKeyframe) -> PetRigTransform {
        PetRigTransform(
            x: frame.x ?? 0,
            y: frame.y ?? 0,
            rotation: frame.rotation ?? 0,
            scaleX: frame.scaleX ?? 1,
            scaleY: frame.scaleY ?? 1
        )
    }

    private func interpolate(
        _ a: CGFloat,
        _ b: CGFloat,
        _ amount: CGFloat
    ) -> CGFloat {
        a + (b - a) * min(1, max(0, amount))
    }

    private func applyAncestorTransforms(
        for part: PetRigPartDefinition,
        transforms: [String: PetRigTransform],
        visited: Set<String>
    ) {
        guard let parentID = part.parent,
              !visited.contains(parentID),
              let parent = partsByID[parentID] else {
            return
        }
        var nextVisited = visited
        nextVisited.insert(parentID)
        applyAncestorTransforms(
            for: parent,
            transforms: transforms,
            visited: nextVisited
        )
        apply(
            transform: transforms[parentID] ?? PetRigTransform(),
            around: anchorPoint(for: parent)
        )
    }

    private func anchorPoint(for part: PetRigPartDefinition) -> NSPoint {
        NSPoint(
            x: part.frame.x + part.frame.width * part.anchor.x,
            y: part.frame.y + part.frame.height * part.anchor.y
        )
    }

    private func apply(transform: PetRigTransform, around pivot: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.translateBy(x: transform.x, y: transform.y)
        context.translateBy(x: pivot.x, y: pivot.y)
        context.rotate(by: transform.rotation * .pi / 180)
        context.scaleBy(x: transform.scaleX, y: transform.scaleY)
        context.translateBy(x: -pivot.x, y: -pivot.y)
    }
}

enum PetRigError: LocalizedError {
    case invalidManifest
    case invalidPart(String)
    case missingImage(String)
    case invalidParent(String, String)
    case invalidAnimation(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "pet-rig.json 格式无效"
        case .invalidPart(let id):
            return "部件定义无效：\(id)"
        case .missingImage(let file):
            return "缺少或无法读取素材：\(file)"
        case .invalidParent(let part, let parent):
            return "部件 \(part) 引用了不存在的父节点 \(parent)"
        case .invalidAnimation(let name):
            return "动作配置无效：\(name)"
        }
    }
}

enum PetRigStore {
    private static let customRigKey = "BoomPet.customPetRigPath"

    static var hasCustomRig: Bool {
        UserDefaults.standard.string(forKey: customRigKey) != nil
    }

    static var activeDirectory: URL? {
        if let path = UserDefaults.standard.string(forKey: customRigKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("pet-rig.json").path
            ) {
                return url
            }
        }
        return bundledDirectory
    }

    static var bundledDirectory: URL? {
        if let bundled = Bundle.main.url(
            forResource: "pet-rig",
            withExtension: "json",
            subdirectory: "DefaultPetRig"
        ) {
            return bundled.deletingLastPathComponent()
        }
        if let bundled = Bundle.module.url(
            forResource: "pet-rig",
            withExtension: "json",
            subdirectory: "DefaultPetRig"
        ) {
            return bundled.deletingLastPathComponent()
        }
        if let bundled = Bundle.main.url(
            forResource: "pet-rig",
            withExtension: "json"
        ) {
            return bundled.deletingLastPathComponent()
        }
        if let bundled = Bundle.module.url(
            forResource: "pet-rig",
            withExtension: "json"
        ) {
            return bundled.deletingLastPathComponent()
        }
        return nil
    }

    static func loadActive() -> PetRigRuntime? {
        guard let directory = activeDirectory else { return nil }
        return try? PetRigRuntime(directory: directory)
    }

    static func importRig() -> Result<Void, Error> {
        let panel = NSOpenPanel()
        panel.title = "导入 BoomPet 骨骼与动作配置"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let selected = panel.url else {
            return .success(())
        }

        let sourceDirectory = selected.hasDirectoryPath
            ? selected
            : selected.deletingLastPathComponent()
        do {
            _ = try PetRigRuntime(directory: sourceDirectory)
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("BoomPet", isDirectory: true)
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
            let destination = support.appendingPathComponent(
                "CustomPetRig",
                isDirectory: true
            )
            let staging = support.appendingPathComponent(
                "CustomPetRig.importing",
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.copyItem(at: sourceDirectory, to: staging)
            _ = try PetRigRuntime(directory: staging)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            UserDefaults.standard.set(destination.path, forKey: customRigKey)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func restoreDefault() {
        UserDefaults.standard.removeObject(forKey: customRigKey)
    }

    static func revealActiveDirectory() {
        if let activeDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([
                activeDirectory.appendingPathComponent("pet-rig.json")
            ])
        }
    }
}
