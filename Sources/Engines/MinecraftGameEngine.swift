import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
/// Standalone Minecraft engine.
///
/// Downloads the official Mojang assets, libraries, natives and client jar, then
/// launches the game directly without depending on an external launcher.
@MainActor
final class MinecraftGameEngine: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case downloading(current: Int, total: Int)
        case starting
        case running
        case exited(code: Int32)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var console = ""
    @Published private(set) var status = "Pronto"

    private var process: Process?
    /// Version profiles produced by the Forge / NeoForge installers.
    private var installerProfiles: [String: [String: Any]] = [:]
    /// The profile used by the last launch, so the caller can remember it.
    private(set) var lastProfile: LoaderProfile?
    /// The exact command line used by the last launch, for diagnostics.
    private(set) var lastCommand: [String] = []
    private let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
    private let resourcesBase = URL(string: "https://resources.download.minecraft.net")!
    private let librariesBase = URL(string: "https://libraries.minecraft.net")!
    private let userAgent = "GameOnLauncher/1.0 (macOS)"

    var isBusy: Bool {
        switch phase {
        case .preparing, .starting: return true
        case .downloading: return true
        default: return false
        }
    }

    // MARK: - Launch

    /// Downloads everything needed and starts Minecraft.
    func launch(
        version: String,
        gameDirectory: URL,
        account: MinecraftAccountProfile,
        loader: ModLoader = .vanilla,
        loaderVersion: String? = nil,
        minMemoryMB: Int = 1024,
        maxMemoryMB: Int = 4096,
        javaArguments: [String] = []
    ) async {
        guard !isBusy else { return }
        phase = .preparing
        status = "A preparar Minecraft \(version)…"
        console = ""
        do {
            // Java is checked first: there is no point downloading hundreds of
            // megabytes when the runtime is missing. The runtime is picked to
            // match the Java version the game needs.
            let java = try javaExecutable(for: version)

            try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)

            // Forge and NeoForge must run their installer once to produce a version profile.
            let profile: LoaderProfile
            if loader.needsInstaller {
                phase = .preparing
                status = "A preparar o \(loader.displayName)…"
                profile = try await prepareInstallerProfile(
                    loader: loader,
                    gameVersion: version,
                    loaderVersion: loaderVersion ?? "",
                    gameDirectory: gameDirectory
                )
            } else if loader == .vanilla {
                profile = .vanilla
            } else {
                profile = try await resolveProfile(loader: loader, gameVersion: version, loaderVersion: loaderVersion)
            }

            lastProfile = profile

            let metadata = try await resolveMetadata(for: version, directory: gameDirectory, profile: profile)
            phase = .downloading(current: 0, total: 1)
            status = "A transferir ficheiros do Minecraft…"

            let libraries = try await installLibraries(metadata, directory: gameDirectory, profile: profile)
            let assetsIndex = try await installAssets(metadata, directory: gameDirectory)
            let clientJar = try await installClient(metadata, version: version, directory: gameDirectory)
            let natives = try await prepareNatives(metadata: metadata, clientJar: clientJar, directory: gameDirectory, version: version)

            let classpath = ([clientJar] + libraries).map(\.path).joined(separator: ":")
            let arguments = try buildArguments(
                metadata: metadata,
                version: version,
                directory: gameDirectory,
                assetsIndex: assetsIndex,
                natives: natives,
                classpath: classpath,
                account: account,
                minMemoryMB: minMemoryMB,
                maxMemoryMB: maxMemoryMB,
                javaArguments: javaArguments,
                profile: profile
            )

            phase = .starting
            status = "A iniciar Minecraft \(version)…"
            try run(java: java, arguments: arguments, directory: gameDirectory, version: version)
            phase = .running
            status = "Minecraft \(version) em execução"
            let loaderText = profile.loader == .vanilla ? "" : " · \(profile.loader.displayName) \(profile.version)"
            append("Processo iniciado: \(java.path) · \(version)\(loaderText)\n")
        } catch {
            phase = .failed(error.localizedDescription)
            status = "Não foi possível iniciar Minecraft: \(error.localizedDescription)"
            append("\n\(status)\n")
        }
    }

    /// Terminates a running game process.
    func stop() {
        guard let process, process.isRunning else { return }
        status = "A fechar Minecraft…"
        process.terminate()
    }

    /// Empties the console output.
    func clearConsole() {
        console = ""
    }

    /// Copies the console output to the pasteboard.
    func copyConsole() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(console, forType: .string)
    }

    // MARK: - Process

    private func run(java: URL, arguments: [String], directory: URL, version: String) throws {
        let game = Process()
        game.executableURL = java
        game.arguments = arguments
        lastCommand = [java.path] + arguments
        game.currentDirectoryURL = directory

        let output = Pipe()
        game.standardOutput = output
        game.standardError = output

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.append(text) }
        }

        game.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            let code = ended.terminationStatus
            Task { @MainActor [weak self] in
                self?.phase = .exited(code: code)
                self?.status = code == 0 ? "Minecraft encerrado" : "Minecraft terminou com erro (código \(code))"
                self?.append("\nJogo encerrado. Código: \(code)\n")
            }
        }

        try game.run()
        process = game
    }

    // MARK: - Metadata

    /// Resolves the version metadata, inheriting from parent versions when needed.
    /// Resolves the profile of a loader published for a Minecraft version.
    private func resolveProfile(loader: ModLoader, gameVersion: String, loaderVersion: String?) async throws -> LoaderProfile {
        let profiles: [LoaderProfile]
        switch loader {
        case .fabric:
            profiles = try await LoaderResolver.fabricProfiles(for: gameVersion)
        case .quilt:
            profiles = try await LoaderResolver.quiltProfiles(for: gameVersion)
        default:
            return .vanilla
        }

        if let loaderVersion, !loaderVersion.isEmpty {
            guard let match = profiles.first(where: { $0.version == loaderVersion }) else {
                throw LoaderResolverError.noCompatibleVersion(loader, gameVersion)
            }
            return match
        }

        // The newest release is not always published, so the first profile whose
        // loader artifact is really downloadable is used.
        for profile in profiles {
            if await Self.isPublished(profile) { return profile }
        }
        guard let best = profiles.first else {
            throw LoaderResolverError.noCompatibleVersion(loader, gameVersion)
        }
        return best
    }

    /// Checks that the loader artifact of a profile can be downloaded.
    private static func isPublished(_ profile: LoaderProfile) async -> Bool {
        guard let library = profile.libraries.first(where: {
            $0.coordinates.contains(":fabric-loader:") || $0.coordinates.contains(":quilt-loader:")
        }) else {
            return true
        }
        for url in library.candidateURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 15
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse else { continue }
            if (200..<300).contains(http.statusCode) { return true }
        }
        return false
    }

    /// Prepares the folder the Forge / NeoForge installer expects.
    ///
    /// It holds the official version JSON of the game and a minimal launcher
    /// profile, which is what the installers read to build their own profile.
    private func prepareInstallerLayout(in directory: URL, gameVersion: String) async throws {
        let versionsFolder = directory.appendingPathComponent("versions/\(gameVersion)", isDirectory: true)
        try FileManager.default.createDirectory(at: versionsFolder, withIntermediateDirectories: true)

        // The official version JSON of the game.
        let manifestData = try await get(manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let versions = manifest["versions"] as? [[String: Any]],
              let entry = versions.first(where: { ($0["id"] as? String) == gameVersion }),
              let rawURL = entry["url"] as? String,
              let versionURL = URL(string: rawURL) else {
            throw LoaderResolverError.noCompatibleVersion(.forge, gameVersion)
        }
        let versionData = try await get(versionURL)
        try versionData.write(to: versionsFolder.appendingPathComponent("\(gameVersion).json"), options: .atomic)

        // A minimal launcher profile, in both the classic and the Microsoft format.
        let profile: [String: Any] = [
            "profiles": [
                "Game On Launcher": [
                    "name": "Game On Launcher",
                    "type": "custom",
                    "created": "2024-01-01T00:00:00.000Z",
                    "lastUsed": "2024-01-01T00:00:00.000Z",
                    "lastVersion": gameVersion,
                    "gameDir": ".",
                    "javaDir": "jdk",
                    "javaArgs": "",
                    "minecraftArguments": "",
                    "icon": "grass"
                ]
            ],
            "selectedProfile": "Game On Launcher"
        ]
        let profilesData = try JSONSerialization.data(withJSONObject: profile, options: [.prettyPrinted, .sortedKeys])
        try profilesData.write(to: directory.appendingPathComponent("launcher_profiles.json"), options: .atomic)
        try profilesData.write(to: directory.appendingPathComponent("launcher_profiles_microsoft.json"), options: .atomic)
    }

    /// Runs the Forge or NeoForge installer and returns the profile it produced.
    private func prepareInstallerProfile(
        loader: ModLoader,
        gameVersion: String,
        loaderVersion: String,
        gameDirectory: URL
    ) async throws -> LoaderProfile {
        // When the instance does not pin a loader version, the newest compatible
        // release is used and remembered for the next launch.
        let resolvedVersion: String
        if loaderVersion.isEmpty {
            let available = try await ModLoader.versions(for: loader, gameVersion: gameVersion)
            guard let newest = available.first else {
                throw LoaderResolverError.noCompatibleVersion(loader, gameVersion)
            }
            resolvedVersion = newest
            append("A usar \(loader.displayName) \(newest)\n")
        } else {
            resolvedVersion = loaderVersion
        }

        let java = try javaExecutable(for: gameVersion)
        let installerURL = try LoaderResolver.installerURL(loader: loader, gameVersion: gameVersion, loaderVersion: resolvedVersion)
        let staging = gameDirectory.appendingPathComponent(".installer", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let installer = staging.appendingPathComponent("installer.jar")
        if !FileManager.default.fileExists(atPath: installer.path) {
            let (temporary, response) = try await URLSession.shared.download(from: installerURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LoaderResolverError.badResponse(installerURL.absoluteString)
            }
            try FileManager.default.moveItem(at: temporary, to: installer)
        }

        let installDirectory = staging.appendingPathComponent("client", isDirectory: true)
        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        // The Forge and NeoForge installers expect the same layout the official
        // launcher produces: the Minecraft version JSON plus a launcher profile.
        // Without them the installer stops with "there is no Minecraft launcher
        // profile in <target>, you need to run the launcher first".
        try await prepareInstallerLayout(in: installDirectory, gameVersion: gameVersion)

        let process = Process()
        process.executableURL = java
        process.arguments = ["-jar", installer.path, "--installClient", installDirectory.path]
        process.currentDirectoryURL = installDirectory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()

        // Drain the pipe while the installer runs so it never blocks on a full buffer.
        let collector = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.append(data)
        }
        while process.isRunning {
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        process.waitUntilExit()
        output.fileHandleForReading.readabilityHandler = nil
        let collected = collector.data()

        guard process.terminationStatus == 0 else {
            let detail = String(data: collected, encoding: .utf8) ?? ""
            throw LoaderResolverError.installerFailed(String(detail.suffix(500)))
        }

        // Copy the libraries the installer produced into the instance folder.
        let producedLibraries = installDirectory.appendingPathComponent("libraries", isDirectory: true)
        if FileManager.default.fileExists(atPath: producedLibraries.path) {
            try? FileHelper.mergeDirectory(
                source: producedLibraries,
                destination: gameDirectory.appendingPathComponent("libraries", isDirectory: true)
            )
        }

        // Locate the profile the installer generated. The plain game version is
        // skipped: the loader profile is the one with a different identifier.
        let versionsFolder = installDirectory.appendingPathComponent("versions", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: versionsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = folders.filter { folder in
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return entries.contains { $0.lastPathComponent == "\(folder.lastPathComponent).json" }
        }
        let generated = candidates
            .filter { $0.lastPathComponent != gameVersion }
            .sorted(by: { left, right in
                let l = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            })
        guard let profileFolder = generated.first ?? candidates.first else {
            throw LoaderResolverError.installerFailed("o instalador não gerou o perfil da versão.")
        }

        let profileJSON = profileFolder.appendingPathComponent("\(profileFolder.lastPathComponent).json")
        let profileData = try Data(contentsOf: profileJSON)
        let json = try JSONSerialization.jsonObject(with: profileData) as? [String: Any] ?? [:]

        let identifier = json["id"] as? String ?? profileFolder.lastPathComponent
        let mainClass = json["mainClass"] as? String
        append("Instalador do \(loader.displayName) concluído: \(identifier)\n")

        // The generated profile inherits from the Minecraft version, so its libraries
        // and arguments are merged into the metadata by `resolveMetadata`.
        installerProfiles[identifier] = json

        return LoaderProfile(
            loader: loader,
            version: resolvedVersion,
            identifier: identifier,
            mainClass: mainClass,
            libraries: [],
            minimumJavaVersion: 8
        )
    }

    private func resolveMetadata(for version: String, directory: URL, profile: LoaderProfile = .vanilla) async throws -> [String: Any] {
        let manifestData = try await get(manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let entries = manifest["versions"] as? [[String: Any]],
              let selected = entries.first(where: { ($0["id"] as? String) == version }),
              let rawURL = selected["url"] as? String,
              let metadataURL = URL(string: rawURL) else { throw GameEngineError.unknownVersion(version) }
        let base = try await metadata(at: metadataURL, directory: directory, depth: 0)

        // An installer-generated profile (Forge / NeoForge) inherits from the base version.
        if let child = installerProfiles[profile.identifier] {
            return mergedMetadata(parent: base, child: child)
        }
        return base
    }

    /// Merges a child version profile into its parent, combining libraries and arguments.
    private func mergedMetadata(parent: [String: Any], child: [String: Any]) -> [String: Any] {
        var combined = parent
        for (key, value) in child { combined[key] = value }

        let parentLibraries = parent["libraries"] as? [[String: Any]] ?? []
        let childLibraries = child["libraries"] as? [[String: Any]] ?? []
        combined["libraries"] = parentLibraries + childLibraries

        if let parentArguments = parent["arguments"] as? [String: Any], let childArguments = child["arguments"] as? [String: Any] {
            var merged = parentArguments
            for (key, value) in childArguments { merged[key] = value }
            combined["arguments"] = merged
        }
        return combined
    }

    private func metadata(at url: URL, directory: URL, depth: Int) async throws -> [String: Any] {
        guard depth < 5 else { throw GameEngineError.invalidMetadata }
        let data = try await get(url)
        guard let child = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GameEngineError.invalidMetadata }

        let versionID = child["id"] as? String ?? UUID().uuidString
        try data.write(to: directory.appendingPathComponent("version-\(versionID).json"), options: .atomic)

        guard let parentID = child["inheritsFrom"] as? String, !parentID.isEmpty else { return child }

        let manifest = try JSONSerialization.jsonObject(with: await get(manifestURL)) as? [String: Any]
        let versions = manifest?["versions"] as? [[String: Any]] ?? []
        guard let parent = versions.first(where: { ($0["id"] as? String) == parentID }),
              let rawURL = parent["url"] as? String,
              let parentURL = URL(string: rawURL) else { throw GameEngineError.invalidMetadata }

        let parentMetadata = try await metadata(at: parentURL, directory: directory, depth: depth + 1)
        return mergedMetadata(parent: parentMetadata, child: child)
    }

    // MARK: - Libraries

    /// Downloads every allowed library and returns the classpath entries.
    private func installLibraries(_ metadata: [String: Any], directory: URL, profile: LoaderProfile = .vanilla) async throws -> [URL] {
        let libraries = metadata["libraries"] as? [[String: Any]] ?? []
        let root = directory.appendingPathComponent("libraries", isDirectory: true)

        var classpath: [URL] = []
        var downloads: [(remote: URL, target: URL, sha1: String?)] = []

        for library in libraries {
            guard allows(library["rules"] as? [[String: Any]]) else { continue }
            guard let downloadInfo = library["downloads"] as? [String: Any] else { continue }

            if let artifact = downloadInfo["artifact"] as? [String: Any],
               let path = artifact["path"] as? String,
               let remoteText = artifact["url"] as? String,
               let remote = URL(string: remoteText) {
                let target = safePath(path, under: root)
                let sha1 = artifact["sha1"] as? String
                // A library that is already on disk and has no checksum is kept as is;
                // this avoids downloading the Forge libraries twice.
                let exists = FileManager.default.fileExists(atPath: target.path)
                if !(exists && sha1 == nil) {
                    downloads.append((remote, target, sha1))
                }
                classpath.append(target)
            }
        }

        // The loader contributes extra libraries that live in a Maven repository.
        // Some artifacts are only published in a secondary repository, so each one
        // is fetched separately and the repositories are tried in order.
        for library in profile.libraries {
            guard let path = library.artifactPath else { continue }
            let target = root.appendingPathComponent(path)
            try await downloadMavenLibrary(library, to: target)
            classpath.append(target)
        }

        try await downloadBatch(downloads)
        return classpath
    }

    // MARK: - Assets

    /// Downloads the asset index and every non-virtual asset object.
    private func installAssets(_ metadata: [String: Any], directory: URL) async throws -> String {
        guard let assetIndex = metadata["assetIndex"] as? [String: Any],
              let id = assetIndex["id"] as? String,
              let rawURL = assetIndex["url"] as? String,
              let url = URL(string: rawURL) else { return "" }

        let indexURL = directory.appendingPathComponent("assets/indexes/\(id).json")
        try await download(url, to: indexURL, sha1: assetIndex["sha1"] as? String)

        let indexData = try Data(contentsOf: indexURL)
        guard let index = try JSONSerialization.jsonObject(with: indexData) as? [String: Any],
              let objects = index["objects"] as? [String: [String: Any]] else { throw GameEngineError.invalidMetadata }

        var files: [(remote: URL, target: URL, sha1: String?)] = []
        for (_, object) in objects {
            // Virtual assets are generated by the game itself — downloading them is wrong.
            if (object["virtual"] as? Bool) == true { continue }
            guard let hash = object["hash"] as? String, hash.count >= 2 else { continue }
            let remote = resourcesBase.appendingPathComponent("\(hash.prefix(2))/\(hash)")
            let destination = directory.appendingPathComponent("assets/objects/\(hash.prefix(2))/\(hash)")
            files.append((remote, destination, hash))
        }

        try await downloadBatch(files)
        return id
    }

    // MARK: - Client

    private func installClient(_ metadata: [String: Any], version: String, directory: URL) async throws -> URL {
        guard let downloads = metadata["downloads"] as? [String: Any],
              let client = downloads["client"] as? [String: Any],
              let rawURL = client["url"] as? String,
              let url = URL(string: rawURL) else { throw GameEngineError.invalidMetadata }
        let target = directory.appendingPathComponent("versions/\(version)/\(version).jar")
        try await download(url, to: target, sha1: client["sha1"] as? String)
        return target
    }

    // MARK: - Natives

    /// Prepares the native libraries directory.
    ///
    /// Since 1.20.5 the natives ship inside the client jar; older versions download
    /// them as separate classified artifacts. Both paths are supported.
    private func prepareNatives(metadata: [String: Any], clientJar: URL, directory: URL, version: String) async throws -> URL {
        let destination = directory.appendingPathComponent("natives/\(version)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        if extractNativesFromClient(clientJar, to: destination) {
            return destination
        }

        let libraries = metadata["libraries"] as? [[String: Any]] ?? []
        let root = directory.appendingPathComponent("libraries", isDirectory: true)
        var downloads: [(remote: URL, target: URL, sha1: String?)] = []

        for library in libraries {
            guard allows(library["rules"] as? [[String: Any]]), let downloadInfo = library["downloads"] as? [String: Any],
                  let classifiers = downloadInfo["classifiers"] as? [String: Any] else { continue }

            for (classifier, info) in classifiers {
                guard isNativeClassifier(classifier), let entry = info as? [String: Any],
                      let path = entry["path"] as? String, let remoteText = entry["url"] as? String,
                      let remote = URL(string: remoteText) else { continue }
                downloads.append((remote, safePath(path, under: root), entry["sha1"] as? String))
            }
        }

        try await downloadBatch(downloads)

        for library in libraries {
            guard allows(library["rules"] as? [[String: Any]]), let downloadInfo = library["downloads"] as? [String: Any],
                  let classifiers = downloadInfo["classifiers"] as? [String: Any] else { continue }
            for (classifier, info) in classifiers where isNativeClassifier(classifier) {
                guard let entry = info as? [String: Any], let path = entry["path"] as? String else { continue }
                let jar = safePath(path, under: root)
                guard FileManager.default.fileExists(atPath: jar.path) else { continue }
                try unpack(jar: jar, to: destination)
            }
        }
        return destination
    }

    /// Extracts `natives/` from the client jar. Returns `true` when natives were found.
    private func extractNativesFromClient(_ clientJar: URL, to destination: URL) -> Bool {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", clientJar.path, "natives/*", "-d", destination.path]
        unzip.standardOutput = Pipe()
        unzip.standardError = Pipe()
        do {
            try unzip.run()
            unzip.waitUntilExit()
        } catch {
            return false
        }
        // `unzip` exits 11 when nothing matched — treat that as "no bundled natives".
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        return !contents.isEmpty
    }

    /// Unpacks a native jar (which is a zip archive) into the natives folder.
    private func unpack(jar: URL, to destination: URL) throws {
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", jar.path, "-d", destination.path]
        unzip.standardOutput = Pipe()
        let errors = Pipe()
        unzip.standardError = errors
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw GameEngineError.nativeExtraction }
    }

    /// Recognises the classifier names Mojang uses for native artifacts.
    private func isNativeClassifier(_ classifier: String) -> Bool {
        let lowered = classifier.lowercased()
        guard lowered.contains("natives") else { return false }
        // Only keep the natives that match the running operating system / architecture.
        if lowered.contains("windows") { return false }
        if lowered.contains("linux") { return false }
        if lowered.contains("macos") || lowered.contains("osx") {
            if lowered.contains("arm64") { return ProcessInfo.processInfo.effectiveArchitecture == "arm64" }
            if lowered.contains("x86_64") { return ProcessInfo.processInfo.effectiveArchitecture == "x86_64" }
            return true
        }
        return false
    }

    // MARK: - Arguments

    /// Builds the JVM and game command line.
    private func buildArguments(
        metadata: [String: Any],
        version: String,
        directory: URL,
        assetsIndex: String,
        natives: URL,
        classpath: String,
        account: MinecraftAccountProfile,
        minMemoryMB: Int,
        maxMemoryMB: Int,
        javaArguments: [String],
        profile: LoaderProfile = .vanilla
    ) throws -> [String] {
        let versionType = (metadata["type"] as? String) ?? "release"
        // A mod loader replaces the vanilla main class and the version identifier.
        let launchIdentifier = profile.identifier.isEmpty ? version : profile.identifier
        let values: [String: String] = [
            "${auth_player_name}": account.name,
            "${version_name}": launchIdentifier,
            "${game_directory}": directory.path,
            "${assets_root}": directory.appendingPathComponent("assets").path,
            "${assets_index_name}": assetsIndex,
            "${auth_uuid}": account.dashedUUID,
            "${auth_access_token}": account.accessToken,
            "${auth_session}": "token:\(account.accessToken):\(account.dashedUUID):\(account.name)",
            "${clientid}": MinecraftAccountService.clientID,
            "${auth_xuid}": account.xuid ?? "",
            "${user_type}": account.userType,
            "${version_type}": versionType,
            "${natives_directory}": natives.path,
            "${launcher_name}": "GameOnLauncher",
            "${launcher_version}": "1.0",
            "${classpath}": classpath,
            "${library_directory}": directory.appendingPathComponent("libraries").path,
            "${quickPlayPath}": directory.path,
            "${quickPlaySingleplayer}": "",
            "${quickPlayMultiplayer}": "",
            "${quickPlayRealms}": ""
        ]

        var jvm = ["-Xms\(max(256, minMemoryMB))M", "-Xmx\(max(512, maxMemoryMB))M"]

        // On macOS the JVM runs the main thread as a secondary thread, which breaks
        // the OpenGL context the game creates. This flag puts it back in first place.
        #if os(macOS)
        jvm.append("-XstartOnFirstThread")
        #endif

        if profile.loader != .vanilla {
            jvm.append("-Dfml.ignoreDisabledMinecraftCode=true")
            jvm.append("-Dfml.ignoreInvalidMinecraftCode=true")
        }
        jvm.append(contentsOf: javaArguments)
        jvm.append(contentsOf: jvmArguments(metadata, values: values))

        let game = gameArguments(metadata, version: version, directory: directory, assetsIndex: assetsIndex, versionType: versionType, account: account, values: values)

        // The main class goes between the JVM options and the game arguments.
        // Without it the JVM treats `--username` as an unknown option and refuses
        // to start, which is why the game never launched.
        let mainClass = profile.mainClass
            ?? (metadata["mainClass"] as? String)
            ?? "net.minecraft.client.main.Main"

        // The metadata sometimes repeats the flag; keep a single copy.
        var unique = [String]()
        for argument in jvm where !unique.contains(argument) { unique.append(argument) }

        return unique + [mainClass] + game
    }

    /// Resolves the `arguments.jvm` section declared by Mojang.
    private func jvmArguments(_ metadata: [String: Any], values: [String: String]) -> [String] {
        guard let arguments = metadata["arguments"] as? [String: Any], let jvm = arguments["jvm"] as? [Any] else { return [] }
        var output: [String] = []
        for item in jvm {
            if let text = item as? String {
                output.append(substitute(text, values))
            } else if let rule = item as? [String: Any], allows(rule["rules"] as? [[String: Any]]) {
                if let value = rule["value"] as? String {
                    output.append(substitute(value, values))
                } else if let list = rule["value"] as? [String] {
                    output.append(contentsOf: list.map { substitute($0, values) })
                }
            }
        }
        return output
    }

    /// Resolves the `arguments.game` section (or the legacy `minecraftArguments`).
    private func gameArguments(
        _ metadata: [String: Any],
        version: String,
        directory: URL,
        assetsIndex: String,
        versionType: String,
        account: MinecraftAccountProfile,
        values: [String: String]
    ) -> [String] {
        if let arguments = metadata["arguments"] as? [String: Any], let game = arguments["game"] as? [Any] {
            var output: [String] = []
            for item in game {
                if let text = item as? String {
                    output.append(substitute(text, values))
                } else if let rule = item as? [String: Any], allows(rule["rules"] as? [[String: Any]]) {
                    if let value = rule["value"] as? String {
                        output.append(substitute(value, values))
                    } else if let list = rule["value"] as? [String] {
                        output.append(contentsOf: list.map { substitute($0, values) })
                    }
                }
            }
            return output
        }

        if let legacy = metadata["minecraftArguments"] as? String {
            return tokenize(legacy).map { substitute($0, values) }
        }

        return [
            "--username", account.name,
            "--version", version,
            "--gameDir", directory.path,
            "--assetsDir", directory.appendingPathComponent("assets").path,
            "--assetIndex", assetsIndex,
            "--uuid", account.dashedUUID,
            "--accessToken", account.accessToken,
            "--userType", account.userType,
            "--versionType", versionType
        ]
    }

    private func substitute(_ input: String, _ values: [String: String]) -> String {
        values.reduce(input) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    /// Splits a legacy argument string honouring quotes.
    private func tokenize(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in input {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let active = quote {
                if character == active { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - Rules

    /// Evaluates Mojang library rules.
    ///
    /// Rules are evaluated in order and the **first** matching rule decides the outcome.
    /// When no rule matches, the library is not allowed.
    private func allows(_ rules: [[String: Any]]?) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        for rule in rules {
            guard ruleMatches(rule) else { continue }
            return (rule["action"] as? String) != "disallow"
        }
        return false
    }

    /// Checks whether a single rule applies to the current platform.
    private func ruleMatches(_ rule: [String: Any]) -> Bool {
        if let os = rule["os"] as? [String: Any] {
            if let name = os["name"] as? String, name != "osx" { return false }
            if let arch = os["arch"] as? String, !ProcessInfo.processInfo.machineArchitectureMatches(arch) { return false }
            if let version = os["version"] as? String, !ProcessInfo.processInfo.osVersionMatches(version) { return false }
        }
        if let features = rule["features"] as? [String: Any] {
            // Optional features (demo user, custom resolution…) are never enabled here,
            // so any rule gated behind a feature must not apply.
            for (_, value) in features where (value as? Bool) == true { return false }
        }
        return true
    }

    // MARK: - Downloads

    private func downloadBatch(_ items: [(remote: URL, target: URL, sha1: String?)]) async throws {
        guard !items.isEmpty else { return }
        let total = items.count
        var completed = 0
        for start in stride(from: 0, to: items.count, by: 12) {
            let batch = Array(items[start..<min(start + 12, items.count)])
            try await withThrowingTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask { try await Self.downloadStatic(item.remote, to: item.target, sha1: item.sha1) }
                }
                try await group.waitForAll()
            }
            completed += batch.count
            phase = .downloading(current: completed, total: total)
            status = "Ficheiros do Minecraft: \(completed)/\(total)"
            // A short pause between batches keeps the request rate polite.
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    /// Downloads a Maven artifact, trying each repository in turn.
    private func downloadMavenLibrary(_ library: MavenLibrary, to target: URL) async throws {
        var lastError: Error = GameEngineError.download(library.coordinates, 0)
        for url in library.candidateURLs {
            do {
                try await download(url, to: target, sha1: library.sha1)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func download(_ remote: URL, to target: URL, sha1: String?) async throws {
        try await Self.downloadStatic(remote, to: target, sha1: sha1)
    }

    /// Downloads a file, verifying its SHA-1 when the manifest provides one.
    nonisolated private static func downloadStatic(_ remote: URL, to target: URL, sha1: String?) async throws {
        if FileManager.default.fileExists(atPath: target.path), let sha1, Self.hashSHA1(target) == sha1 { return }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lastError: Error = GameEngineError.download(remote.absoluteString, 0)
        for attempt in 0..<3 {
            do {
                let (temporary, response) = try await URLSession.shared.download(from: remote)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw GameEngineError.download(remote.absoluteString, 0)
                }
                if let sha1, Self.hashSHA1(temporary) != sha1 { throw GameEngineError.checksum(target.lastPathComponent) }
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.moveItem(at: temporary, to: target)
                return
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 800_000_000)
                }
            }
        }
        throw lastError
    }

    /// Computes the SHA-1 digest of a file.
    nonisolated private static func hashSHA1(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1_048_576)
            } catch {
                chunk = nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches a document, retrying when the server is busy.
    ///
    /// Mojang limits the request rate, and the launcher asks for hundreds of
    /// files in a row, so `429` and `5xx` answers are retried with a pause.
    private func get(_ url: URL) async throws -> Data {
        var lastStatus = 0
        for attempt in 0..<4 {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 60

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw GameEngineError.download(url.absoluteString, 0)
                }
                if (200..<300).contains(http.statusCode) { return data }
                lastStatus = http.statusCode

                // Too many requests, or a hiccup on the server side: wait and retry.
                if http.statusCode == 429 || (500..<600).contains(http.statusCode) {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 1.5 * 1_000_000_000)
                    append("HTTP \(http.statusCode) · a tentar de novo…\n")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
            } catch let error as GameEngineError {
                throw error
            } catch {
                lastStatus = 0
            }
        }
        throw GameEngineError.download(url.absoluteString, lastStatus)
    }

    // MARK: - Java

    /// Finds a Java runtime that satisfies the game version.
    ///
    /// Minecraft 1.20.5 and newer need Java 21, older versions accept Java 17.
    /// Using an older runtime fails with `UnsupportedClassVersionError`.
    private func javaExecutable(for minecraftVersion: String) throws -> URL {
        let required = JavaLocator.requiredJavaVersion(for: minecraftVersion)
        guard let java = JavaLocator.shared.locate(minimumMajor: required) else {
            throw GameEngineError.javaMissing(required)
        }
        let found = JavaLocator.shared.readVersion(at: java) ?? "?"
        append("Java \(found) · esta versão exige Java \(required)\n")
        return java
    }

    /// Fallback lookup used when the shared locator finds nothing.
    private func legacyJavaExecutable() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: "/usr/libexec/java_home"),
            URL(fileURLWithPath: "/usr/bin/java"),
            URL(fileURLWithPath: "/usr/local/bin/java"),
            URL(fileURLWithPath: "/opt/homebrew/bin/java")
        ]

        if FileManager.default.isExecutableFile(atPath: candidates[0].path) {
            let home = Process()
            home.executableURL = candidates[0]
            let pipe = Pipe()
            home.standardOutput = pipe
            home.standardError = Pipe()
            if (try? home.run()) != nil {
                home.waitUntilExit()
                if home.terminationStatus == 0,
                   let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    let candidate = URL(fileURLWithPath: trimmed).appendingPathComponent("bin/java")
                    if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                }
            }
        }

        for candidate in candidates.dropFirst() where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw GameEngineError.javaMissing(17)
    }

    // MARK: - Utilities

    /// Confines a path inside a root folder, preventing path traversal.
    private func safePath(_ path: String, under root: URL) -> URL {
        let base = root.standardizedFileURL
        let target = base.appendingPathComponent(path).standardizedFileURL
        return target.path.hasPrefix(base.path + "/") ? target : base.appendingPathComponent(UUID().uuidString)
    }

    private func append(_ text: String) {
        console += text
        if console.count > 120_000 { console = String(console.suffix(80_000)) }
    }
}

// MARK: - Errors

enum GameEngineError: LocalizedError {
    case unknownVersion(String)
    case invalidMetadata
    case download(String, Int)
    case checksum(String)
    case nativeExtraction
    case javaMissing(Int)

    var errorDescription: String? {
        switch self {
        case .unknownVersion(let version): return "A versão \(version) não foi encontrada no manifesto oficial."
        case .invalidMetadata: return "Os metadados oficiais desta versão estão incompletos."
        case .download(let url, let status):
            if status == 429 {
                return "O servidor do Minecraft limitou o número de pedidos (HTTP 429). Espera um momento e tenta de novo."
            }
            if status >= 500 {
                return "O servidor do Minecraft respondeu com HTTP \(status). Tenta de novo dentro de um instante."
            }
            if status > 0 {
                return "Falha ao transferir ficheiros do Minecraft (HTTP \(status)): \(url)"
            }
            return "Falha ao transferir ficheiros do Minecraft: \(url)"
        case .checksum(let file): return "A verificação SHA-1 falhou para \(file). Tenta novamente."
        case .nativeExtraction: return "Não foi possível preparar as bibliotecas nativas do Minecraft."
        case .javaMissing(let required):
            return "Java \(required) não encontrado. Instala o Java \(required) ou superior — o Minecraft a partir da 1.20.5 precisa de Java 21."
        }
    }
}

// MARK: - Platform helpers

extension ProcessInfo {
    /// The architecture the JVM will report, accounting for Rosetta translation.
    var effectiveArchitecture: String {
        if sysctlString("hw.optional.arm64") == "1" {
            // Under Rosetta the process itself is x86_64 even on Apple silicon.
            return isTranslated ? "x86_64" : "arm64"
        }
        return "x86_64"
    }

    /// Whether the current process runs through Rosetta translation.
    var isTranslated: Bool {
        if let value = sysctlString("sysctl.proc_translated") { return value == "1" }
        return false
    }

    func machineArchitectureMatches(_ expected: String) -> Bool {
        switch expected {
        case "x86": return effectiveArchitecture == "x86"
        case "x86_64": return effectiveArchitecture == "x86_64"
        case "arm64": return effectiveArchitecture == "arm64"
        default: return true
        }
    }

    /// Matches the macOS version against a regular expression rule.
    func osVersionMatches(_ pattern: String) -> Bool {
        let version = operatingSystemVersion
        let text = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
