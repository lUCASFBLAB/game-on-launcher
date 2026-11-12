import Foundation

/// A downloadable file attached to a release.
struct ReleaseAsset: Identifiable, Hashable {
    let name: String
    let downloadURL: URL
    let size: Int64
    /// When the file was uploaded or replaced.
    let updatedAt: Date

    var id: String { name }
}

/// Information about an available update.
struct UpdateInfo: Hashable {
    let version: String
    let asset: ReleaseAsset
    let releaseName: String
    let publishedAt: Date

    /// The version shown to the user, falling back to the release date.
    var displayVersion: String {
        version.isEmpty ? "nova versão" : version
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)
    }
}

/// The platform the launcher runs on, used to pick the right asset.
enum UpdatePlatform {
    case macOS
    case windowsIntel
    case windowsARM
    case windowsPortable
    case android
    case quest

    /// The regular expression that matches the asset for this platform.
    ///
    /// The Windows assets carry the version in their name; the macOS disk image
    /// does not, so the upload date is used instead.
    var assetPattern: String {
        switch self {
        case .macOS: return #"^GameOnLauncher-macOS\.dmg$"#
        case .windowsIntel: return #"^GameOnLauncher-(\d+\.\d+\.\d+)-x64\.exe$"#
        case .windowsARM: return #"^GameOnLauncher-(\d+\.\d+\.\d+)-arm64\.exe$"#
        case .windowsPortable: return #"^GameOnLauncher-(\d+\.\d+\.\d+)-portable\.exe$"#
        case .android: return #"^GameOnLauncher-(\d+\.\d+\.\d+)(?:-[a-z]+)?\.apk$"#
        case .quest: return #"^GameOnLauncher-Quest-(\d+\.\d+\.\d+).*\.apk$"#
        }
    }

    /// The platform the current build runs on.
    static var current: UpdatePlatform {
        #if os(macOS)
        return .macOS
        #else
        return .windowsIntel
        #endif
    }
}

/// Checks GitHub Releases for a newer build of the launcher.
enum UpdateService {
    /// The repository that hosts the releases.
    static let repository = "lUCASFBLAB/game-on-launcher"

    /// The tag that always points at the latest build.
    static let releaseTag = "gameon-mac.zip"

    /// Direct download links, used when the API is unreachable.
    static let fallbackBase = URL(string: "https://github.com/\(repository)/releases/download/\(releaseTag)")!

    /// The version of the running application.
    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        if let short, let build, short != build { return "\(short) (\(build))" }
        return short ?? build ?? "0.0.0"
    }

    /// The date the running application was built.
    static var localBuildDate: Date {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/GameOnLauncher")
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? Date.distantPast
    }

    /// Looks for a newer build.
    ///
    /// The release is fetched from the GitHub API and the asset for the current
    /// platform is compared with the running build.
    static func check(platform: UpdatePlatform = .current) async throws -> UpdateInfo? {
        let release = try await fetchRelease()
        guard let asset = pickAsset(in: release, platform: platform) else { return nil }

        let remoteVersion = version(in: asset.name)

        // A version in the name is compared directly.
        if !remoteVersion.isEmpty {
            if isNewer(remoteVersion, than: currentVersion) {
                return UpdateInfo(
                    version: remoteVersion,
                    asset: asset,
                    releaseName: release.name,
                    publishedAt: release.publishedAt
                )
            }
            return nil
        }

        // Without a version in the name, a newer upload counts as an update.
        let stamp = asset.updatedAt == .distantPast ? release.publishedAt : asset.updatedAt
        if stamp > localBuildDate {
            return UpdateInfo(
                version: "",
                asset: asset,
                releaseName: release.name,
                publishedAt: release.publishedAt
            )
        }
        return nil
    }

    /// Downloads an update to a temporary file.
    static func download(_ asset: ReleaseAsset, progress: ((Double) -> Void)? = nil) async throws -> URL {
        var request = URLRequest(url: asset.downloadURL)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 1800

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
        progress?(1)
        return temporary
    }

    // MARK: - Release metadata

    private struct Release {
        let name: String
        let tag: String
        let publishedAt: Date
        let assets: [ReleaseAsset]
    }

    private static func fetchRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/tags/\(releaseTag)")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.releaseUnavailable
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.releaseUnavailable
        }

        let assets = (object["assets"] as? [[String: Any]] ?? []).compactMap { row -> ReleaseAsset? in
            guard let name = row["name"] as? String,
                  let urlText = row["browser_download_url"] as? String,
                  let url = URL(string: urlText) else { return nil }
            return ReleaseAsset(
                name: name,
                downloadURL: url,
                size: (row["size"] as? NSNumber)?.int64Value ?? 0,
                updatedAt: parseDate(row["updated_at"] as? String) ?? .distantPast
            )
        }

        return Release(
            name: object["name"] as? String ?? "",
            tag: object["tag_name"] as? String ?? releaseTag,
            publishedAt: parseDate(object["published_at"] as? String) ?? .distantPast,
            assets: assets
        )
    }

    /// Picks the asset that matches the platform.
    ///
    /// The version is not always known in advance, so the pattern is matched
    /// against every asset and the best candidate is chosen.
    private static func pickAsset(in release: Release, platform: UpdatePlatform) -> ReleaseAsset? {
        guard let regex = try? NSRegularExpression(pattern: platform.assetPattern) else { return nil }
        let matches = release.assets.filter { asset in
            let range = NSRange(asset.name.startIndex..<asset.name.endIndex, in: asset.name)
            return regex.firstMatch(in: asset.name, range: range) != nil
        }
        // The newest upload wins when several match.
        return matches.max { $0.updatedAt < $1.updatedAt }
    }

    /// Extracts a version number from a file name.
    static func version(in name: String) -> String {
        let pattern = #"(\d+)\.(\d+)(?:\.(\d+))?"#
        guard let range = name.range(of: pattern, options: .regularExpression) else { return "" }
        return String(name[range])
    }

    /// Converts a version into a list of numbers.
    static func numericVersion(_ version: String) -> [Int] {
        var numbers: [Int] = []
        var current = ""
        for character in version {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                numbers.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty { numbers.append(Int(current) ?? 0) }
        return numbers
    }

    /// Compares two version strings.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = numericVersion(candidate)
        let right = numericVersion(current)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Errors raised by the update service.
enum UpdateError: LocalizedError {
    case releaseUnavailable
    case downloadFailed
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .releaseUnavailable:
            return "Não foi possível consultar as atualizações. Verifica a ligação à internet."
        case .downloadFailed:
            return "A transferência da atualização falhou."
        case .installFailed(let detail):
            return "Não foi possível instalar a atualização: \(detail)"
        }
    }
}
