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
    case github(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .github(let message):
            return message
        }
    }
}

final class UpdateService {
    static let repository = "vinfolhu/boom"
    static let releasesURL = URL(string: "https://github.com/vinfolhu/boom/releases")!

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
            case assets
        }
    }

    private struct GitHubError: Decodable {
        let message: String
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        let endpoint = URL(
            string: "https://api.github.com/repos/\(Self.repository)/releases/latest"
        )!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("BoomPet/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }
        if http.statusCode == 404 {
            return .noPublishedRelease
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubError.self, from: data).message)
                ?? "GitHub update check failed (\(http.statusCode))."
            throw UpdateServiceError.github(message)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            return .noPublishedRelease
        }
        let latest = Self.normalizedVersion(release.tagName)
        guard Self.isNewer(latest, than: Self.currentVersion) else {
            return .upToDate(latestVersion: latest)
        }
        let preferredAsset = release.assets.first {
            $0.name.lowercased() == "boompet-macos-universal.dmg"
        } ?? release.assets.first {
            $0.name.lowercased() == "boompet-macos-universal.zip"
        } ?? release.assets.first {
            let name = $0.name.lowercased()
            return name.contains("boompet")
                && name.contains("mac")
                && (name.hasSuffix(".dmg") || name.hasSuffix(".zip"))
        }
        return .updateAvailable(
            AppUpdateInfo(
                version: latest,
                releasePageURL: release.htmlURL,
                downloadURL: preferredAsset?.browserDownloadURL,
                assetName: preferredAsset?.name
            )
        )
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
