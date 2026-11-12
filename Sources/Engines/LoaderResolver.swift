import Foundation

/// A mod loader that the internal engine can launch without any external launcher.
enum ModLoader: String, CaseIterable, Codable, Identifiable, Hashable {
    case vanilla
    case fabric
    case quilt
    case forge
    case neoforge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vanilla: return "Vanilla"
        case .fabric: return "Fabric"
        case .quilt: return "Quilt"
        case .forge: return "Forge"
        case .neoforge: return "NeoForge"
        }
    }

    /// Whether the loader needs an installer to be executed before launching.
    var needsInstaller: Bool {
        self == .forge || self == .neoforge
    }

    /// The loader versions published for a Minecraft version.
    static func versions(for loader: ModLoader, gameVersion: String) async throws -> [String] {
        switch loader {
        case .vanilla:
            return [gameVersion]
        case .fabric:
            return try await LoaderResolver.fabricProfiles(for: gameVersion).map(\.version)
        case .quilt:
            return try await LoaderResolver.quiltProfiles(for: gameVersion).map(\.version)
        case .forge:
            return try await LoaderResolver.forgeVersions(for: gameVersion)
        case .neoforge:
            return try await LoaderResolver.neoforgeVersions(for: gameVersion)
        }
    }
}

/// A library resolved from a Maven repository.
struct MavenLibrary: Hashable {
    /// Maven coordinates, for example `net.fabricmc:fabric-loader:0.20.1`.
    let coordinates: String
    /// Base URL of the Maven repository.
    let baseURL: URL
    /// Second repository, used when the first does not hold the artifact.
    let fallbackBaseURL: URL?
    let sha1: String?

    init(coordinates: String, baseURL: URL, fallbackBaseURL: URL? = nil, sha1: String? = nil) {
        self.coordinates = coordinates
        self.baseURL = baseURL
        self.fallbackBaseURL = fallbackBaseURL
        self.sha1 = sha1
    }

    /// The repository path of the artifact, for example
    /// `net/fabricmc/fabric-loader/0.20.1/fabric-loader-0.20.1.jar`.
    var artifactPath: String? {
        let parts = coordinates.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return nil }
        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[parts.count - 1]
        let classifier = parts.count >= 4 ? "-\(parts[2])" : ""
        let file = "\(artifact)-\(version)\(classifier).jar"
        return "\(group)/\(artifact)/\(version)/\(file)"
    }

    /// Converts the coordinates into a repository path and a direct download URL.
    var artifact: (path: String, url: URL)? {
        guard let path = artifactPath else { return nil }
        return (path, baseURL.appendingPathComponent(path))
    }

    /// Every repository that may hold the artifact, in order of preference.
    var candidateURLs: [URL] {
        guard let path = artifactPath else { return [] }
        var urls = [baseURL.appendingPathComponent(path)]
        if let fallbackBaseURL {
            let fallback = fallbackBaseURL.appendingPathComponent(path)
            if !urls.contains(fallback) { urls.append(fallback) }
        }
        return urls
    }
}

/// Everything the engine needs to start the game with a mod loader.
struct LoaderProfile: Hashable {
    let loader: ModLoader
    /// The loader version, for example `0.20.1`.
    let version: String
    /// Identifier used for `${version_name}`.
    let identifier: String
    /// Main class that replaces the vanilla one.
    let mainClass: String?
    /// Extra libraries that must be on the classpath.
    let libraries: [MavenLibrary]
    /// Minimum Java version required by the loader.
    let minimumJavaVersion: Int

    static let vanilla = LoaderProfile(
        loader: .vanilla,
        version: "",
        identifier: "",
        mainClass: nil,
        libraries: [],
        minimumJavaVersion: 8
    )
}

/// Resolves loader profiles from the official metadata services.
enum LoaderResolver {
    private static let fabricMeta = URL(string: "https://meta.fabricmc.net/v2")!
    private static let quiltMeta = URL(string: "https://meta.quiltmc.org/v3")!
    private static let forgeMaven = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge")!
    private static let neoforgeMaven = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge")!

    // MARK: - Fabric

    /// Fetches every published Fabric profile for a Minecraft version.
    static func fabricProfiles(for gameVersion: String) async throws -> [LoaderProfile] {
        let entries = try await fetchJSON(fabricMeta.appendingPathComponent("versions/loader/\(gameVersion)"))
        guard let list = entries as? [[String: Any]] else { return [] }

        return list.compactMap { entry in
            guard let loader = entry["loader"] as? [String: Any],
                  let loaderVersion = loader["version"] as? String,
                  let loaderMaven = loader["maven"] as? String else { return nil }

            var libraries: [MavenLibrary] = []
            if let intermediary = entry["intermediary"] as? [String: Any],
               let maven = intermediary["maven"] as? String {
                libraries.append(MavenLibrary(coordinates: maven, baseURL: URL(string: "https://maven.fabricmc.net/")!, sha1: nil))
            }
            libraries.append(MavenLibrary(coordinates: loaderMaven, baseURL: URL(string: "https://maven.fabricmc.net/")!, sha1: nil))

            var mainClass: String?
            var extraLibraries: [MavenLibrary] = []
            if let meta = entry["launcherMeta"] as? [String: Any] {
                if let classes = meta["mainClass"] as? [String: Any] {
                    mainClass = classes["client"] as? String
                }
                if let libraryGroups = meta["libraries"] as? [String: Any] {
                    for group in ["common", "client"] {
                        for item in (libraryGroups[group] as? [[String: Any]]) ?? [] {
                            guard let name = item["name"] as? String,
                                  let urlText = item["url"] as? String,
                                  let url = URL(string: urlText) else { continue }
                            extraLibraries.append(MavenLibrary(coordinates: name, baseURL: url, sha1: item["sha1"] as? String))
                        }
                    }
                }
            }

            return LoaderProfile(
                loader: .fabric,
                version: loaderVersion,
                identifier: "fabric-loader-\(loaderVersion)-\(gameVersion)",
                mainClass: mainClass ?? "net.fabricmc.loader.impl.launch.knot.KnotClient",
                libraries: extraLibraries + libraries,
                minimumJavaVersion: 8
            )
        }
        .filter { !$0.version.isEmpty }
        .sorted { lhs, rhs in
            // Stable releases first, then the highest version.
            let left = Self.versionWeight(lhs.version)
            let right = Self.versionWeight(rhs.version)
            if left != right { return left > right }
            return Self.compareVersions(lhs.version, rhs.version) > 0
        }
    }

    // MARK: - Quilt

    /// Fetches every published Quilt profile for a Minecraft version.
    static func quiltProfiles(for gameVersion: String) async throws -> [LoaderProfile] {
        let entries = try await fetchJSON(quiltMeta.appendingPathComponent("versions/loader/\(gameVersion)"))
        guard let list = entries as? [[String: Any]] else { return [] }

        return list.compactMap { entry in
            guard let loader = entry["loader"] as? [String: Any],
                  let loaderVersion = loader["version"] as? String,
                  let loaderMaven = loader["maven"] as? String else { return nil }

            var libraries: [MavenLibrary] = []
            if let intermediary = entry["intermediary"] as? [String: Any],
               let maven = intermediary["maven"] as? String {
                libraries.append(MavenLibrary(coordinates: maven, baseURL: URL(string: "https://maven.fabricmc.net/")!, sha1: nil))
            }
            libraries.append(MavenLibrary(
                coordinates: loaderMaven,
                baseURL: URL(string: "https://maven.quiltmc.org/repository/release/")!,
                fallbackBaseURL: URL(string: "https://maven.quiltmc.org/repository/snapshot/")!,
                sha1: nil
            ))

            var mainClass: String?
            var extraLibraries: [MavenLibrary] = []
            if let meta = entry["launcherMeta"] as? [String: Any] {
                if let classes = meta["mainClass"] as? [String: Any] {
                    mainClass = classes["client"] as? String
                }
                if let libraryGroups = meta["libraries"] as? [String: Any] {
                    for group in ["common", "client"] {
                        for item in (libraryGroups[group] as? [[String: Any]]) ?? [] {
                            guard let name = item["name"] as? String,
                                  let urlText = item["url"] as? String,
                                  let url = URL(string: urlText) else { continue }
                            extraLibraries.append(MavenLibrary(coordinates: name, baseURL: url, sha1: item["sha1"] as? String))
                        }
                    }
                }
            }

            return LoaderProfile(
                loader: .quilt,
                version: loaderVersion,
                identifier: "quilt-loader-\(loaderVersion)-\(gameVersion)",
                mainClass: mainClass ?? "org.quiltmc.loader.impl.launch.knot.KnotClient",
                libraries: extraLibraries + libraries,
                minimumJavaVersion: 8
            )
        }
        .filter { !$0.version.isEmpty }
        .sorted { lhs, rhs in
            // Pre-releases are published later but are not always downloadable,
            // so the newest stable release is preferred.
            let left = Self.versionWeight(lhs.version)
            let right = Self.versionWeight(rhs.version)
            if left != right { return left > right }
            return Self.compareVersions(lhs.version, rhs.version) > 0
        }
    }

    // MARK: - Forge and NeoForge

    /// Lists the Forge versions compatible with a Minecraft version.
    static func forgeVersions(for gameVersion: String) async throws -> [String] {
        let metadata = try await fetchText(forgeMaven.appendingPathComponent("maven-metadata.xml"))
        let all = metadata.components(separatedBy: "<version>").dropFirst().compactMap {
            $0.components(separatedBy: "</version>").first
        }
        return all.reversed().filter { $0.hasPrefix("\(gameVersion)-") }
    }

    /// Lists the NeoForge versions compatible with a Minecraft version.
    static func neoforgeVersions(for gameVersion: String) async throws -> [String] {
        let metadata = try await fetchText(neoforgeMaven.appendingPathComponent("maven-metadata.xml"))
        let all = metadata.components(separatedBy: "<version>").dropFirst().compactMap {
            $0.components(separatedBy: "</version>").first
        }
        let parts = gameVersion.split(separator: ".")
        guard parts.count >= 3 else { return [] }
        let prefix = "\(parts[1]).\(parts[2])."
        return all.reversed().filter { $0.hasPrefix(prefix) }
    }

    /// Builds the download URL of a Forge or NeoForge installer.
    static func installerURL(loader: ModLoader, gameVersion: String, loaderVersion: String) throws -> URL {
        switch loader {
        case .forge:
            return URL(string: "\(forgeMaven.absoluteString)/\(loaderVersion)/forge-\(loaderVersion)-installer.jar")!
        case .neoforge:
            return URL(string: "\(neoforgeMaven.absoluteString)/\(loaderVersion)/neoforge-\(loaderVersion)-installer.jar")!
        default:
            throw LoaderResolverError.unsupportedInstaller(loader)
        }
    }

    // MARK: - Helpers

    /// Ranks a loader version: stable releases come before pre-releases.
    private static func versionWeight(_ version: String) -> Int {
        let lowered = version.lowercased()
        let preRelease = ["beta", "alpha", "rc", "snapshot", "dev", "pre"].contains { lowered.contains($0) }
        return preRelease ? 0 : 1
    }

    /// Compares two dotted version strings numerically.
    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
        let right = rhs.split(whereSeparator: { $0 == "." || $0 == "-" }).compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return lhs.compare(rhs) == .orderedDescending ? 1 : (lhs == rhs ? 0 : -1)
    }

    private static func fetchJSON(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LoaderResolverError.badResponse(url.absoluteString)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LoaderResolverError.badResponse(url.absoluteString)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Errors raised while resolving loader profiles.
enum LoaderResolverError: LocalizedError {
    case badResponse(String)
    case unsupportedInstaller(ModLoader)
    case noCompatibleVersion(ModLoader, String)
    case installerFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let url):
            return "A API de loaders respondeu de forma inesperada (\(url))."
        case .unsupportedInstaller(let loader):
            return "O instalador do \(loader.displayName) não está disponível."
        case .noCompatibleVersion(let loader, let gameVersion):
            return "Não existe uma versão do \(loader.displayName) compatível com o Minecraft \(gameVersion)."
        case .installerFailed(let detail):
            return "O instalador do carregador falhou: \(detail)"
        }
    }
}
