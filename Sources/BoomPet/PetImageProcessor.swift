import AppKit
import CoreGraphics

enum PetImageProcessor {
    static func automaticCutoutPNG(from image: NSImage) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let maxDimension: CGFloat = 1600
        let scale = min(1, maxDimension / CGFloat(max(source.width, source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        let cornerSamples = [
            color(atX: 0, y: 0, pixels: pixels, width: width),
            color(atX: width - 1, y: 0, pixels: pixels, width: width),
            color(atX: 0, y: height - 1, pixels: pixels, width: width),
            color(atX: width - 1, y: height - 1, pixels: pixels, width: width)
        ]
        let cornerColors = cornerSamples.compactMap { sample in
            sample.3 > 200 ? (sample.0, sample.1, sample.2) : nil
        }

        var visited = [Bool](repeating: false, count: width * height)
        var queue = [Int]()
        queue.reserveCapacity(min(width * height, 1_000_000))

        func isBackground(_ index: Int) -> Bool {
            let offset = index * 4
            if pixels[offset + 3] < 18 { return true }
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            return cornerColors.contains { corner in
                let dr = red - corner.0
                let dg = green - corner.1
                let db = blue - corner.2
                return dr * dr + dg * dg + db * db < 52 * 52
            }
        }

        func enqueue(_ index: Int) {
            guard !visited[index], isBackground(index) else { return }
            visited[index] = true
            queue.append(index)
        }

        for x in 0..<width {
            enqueue(x)
            enqueue((height - 1) * width + x)
        }
        for y in 0..<height {
            enqueue(y * width)
            enqueue(y * width + width - 1)
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            pixels[index * 4 + 3] = 0

            if x > 0 { enqueue(index - 1) }
            if x + 1 < width { enqueue(index + 1) }
            if y > 0 { enqueue(index - width) }
            if y + 1 < height { enqueue(index + width) }
        }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * width + x) * 4 + 3]
                guard alpha > 20 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY,
              let processedImage = context.makeImage() else {
            return nil
        }

        let padding = 8
        let cropX = max(0, minX - padding)
        let cropY = max(0, minY - padding)
        let cropMaxX = min(width - 1, maxX + padding)
        let cropMaxY = min(height - 1, maxY + padding)
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: cropMaxX - cropX + 1,
            height: cropMaxY - cropY + 1
        )

        guard let croppedImage = processedImage.cropping(to: cropRect) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: croppedImage).representation(
            using: .png,
            properties: [:]
        )
    }

    private static func color(
        atX x: Int,
        y: Int,
        pixels: [UInt8],
        width: Int
    ) -> (Int, Int, Int, Int) {
        let offset = (y * width + x) * 4
        return (
            Int(pixels[offset]),
            Int(pixels[offset + 1]),
            Int(pixels[offset + 2]),
            Int(pixels[offset + 3])
        )
    }
}
