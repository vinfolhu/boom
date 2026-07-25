import Foundation

struct AppUpdateInfo {
    let version: String
    let releasePageURL: URL
    let downloadURL: URL?
    let assetName: String?
}

enum UpdateCheckResult {
    case updateAvailable(AppUpdateInfo)
    case upToDate(latestVersion: String)
    case noPublishedRelease
}

enum UpdateServiceError: LocalizedError {
    case invalidResponse
    case githubWeb(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .githubWeb(let message):
            return message
        }
    }
}

final class UpdateService {
    static let repository = "vinfolhu/boom"
    static let releasesURL = URL(string: "https://github.com/vinfolhu/boom/releases")!
    private static let preferredAssetName = "BoomPet-macOS-universal.dmg"

    func checkForUpdates() async throws -> UpdateCheckResult {
        let endpoint = URL(
            string: "https://github.com/\(Self.repository)/releases/latest"
        )!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("BoomPet/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }
        if http.statusCode == 404 {
            return .noPublishedRelease
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateServiceError.githubWeb(
                "GitHub update check failed (\(http.statusCode))."
            )
        }

        guard let resolvedURL = http.url,
              let release = Self.releaseInfo(from: resolvedURL) else {
            throw UpdateServiceError.invalidResponse
        }
        let latest = Self.normalizedVersion(release.tag)
        guard Self.isNewer(latest, than: Self.currentVersion) else {
            return .upToDate(latestVersion: latest)
        }
        return .updateAvailable(
            AppUpdateInfo(
                version: latest,
                releasePageURL: release.pageURL,
                downloadURL: release.downloadURL,
                assetName: Self.preferredAssetName
            )
        )
    }

    static func releaseInfo(
        from resolvedURL: URL
    ) -> (tag: String, pageURL: URL, downloadURL: URL)? {
        let components = resolvedURL.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            return nil
        }
        let tag = components[tagIndex + 1]
        let version = normalizedVersion(tag)
        guard !version.isEmpty,
              numericComponents(version).contains(where: { $0 > 0 }) else {
            return nil
        }
        guard let pageURL = URL(
            string: "https://github.com/\(repository)/releases/tag/\(tag)"
        ), let downloadURL = URL(
            string: "https://github.com/\(repository)/releases/download/"
                + "\(tag)/\(preferredAssetName)"
        ) else {
            return nil
        }
        return (tag, pageURL, downloadURL)
    }

    static var currentVersion: String {
        let bundled = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return normalizedVersion(bundled ?? "0.1.0")
    }

    private static func normalizedVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = numericComponents(candidate)
        let right = numericComponents(current)
        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }
        return false
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { component in
            let digits = component.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
    }
}
