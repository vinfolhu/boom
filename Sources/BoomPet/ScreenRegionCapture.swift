import AppKit
import CoreGraphics
import Foundation

enum ScreenCapturePurpose: Equatable {
    case ocr
    case sticky
}

struct CapturedScreenRegion {
    let image: CGImage
    let purpose: ScreenCapturePurpose
}

final class ScreenRegionCapture {
    private var activeProcess: Process?
    private var activeTemporaryURL: URL?

    func capture(
        for purpose: ScreenCapturePurpose,
        completion: @escaping (Result<CapturedScreenRegion, Error>) -> Void
    ) {
        guard activeProcess == nil else {
            completion(.failure(CaptureError.captureInProgress))
            return
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("boompet-capture-\(UUID().uuidString)")
            .appendingPathExtension("png")
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-x",       // no shutter sound
            "-i",       // native interactive selection
            "-s",       // rectangular selection mode
            "-t", "png",
            temporaryURL.path
        ]
        process.standardError = errorPipe
        activeProcess = process
        activeTemporaryURL = temporaryURL

        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self else { return }
                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    self.activeProcess = nil
                    self.activeTemporaryURL = nil
                }

                guard finishedProcess.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: temporaryURL.path)
                else {
                    let errorData = errorPipe.fileHandleForReading
                        .readDataToEndOfFile()
                    let systemError = String(
                        data: errorData,
                        encoding: .utf8
                    ) ?? ""
                    completion(.failure(
                        self.captureFailure(
                            status: finishedProcess.terminationStatus,
                            systemError: systemError
                        )
                    ))
                    return
                }

                guard let data = try? Data(contentsOf: temporaryURL),
                      let representation = NSBitmapImageRep(data: data),
                      let image = representation.cgImage else {
                    completion(.failure(CaptureError.captureFailed))
                    return
                }
                completion(.success(CapturedScreenRegion(
                    image: image,
                    purpose: purpose
                )))
            }
        }

        do {
            try process.run()
        } catch {
            activeProcess = nil
            activeTemporaryURL = nil
            try? FileManager.default.removeItem(at: temporaryURL)
            completion(.failure(CaptureError.captureFailed))
        }
    }

    private func captureFailure(
        status: Int32,
        systemError: String
    ) -> CaptureError {
        let message = systemError.lowercased()
        if message.contains("permission")
            || message.contains("not authorized")
            || message.contains("denied") {
            return .permissionDenied
        }
        return status == 0 ? .captureFailed : .cancelled
    }
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case captureFailed
    case captureInProgress
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "无法读取当前桌面。请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 BoomPet，然后完全退出并重新打开应用。"
        case .captureFailed:
            return "系统选区截图失败，请重新尝试。"
        case .captureInProgress:
            return "已有一个截图任务正在进行。"
        case .cancelled:
            return "已取消"
        }
    }
}
