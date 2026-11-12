import Foundation

/// Imports Modrinth `.mrpack` modpacks into a launcher instance.
///
/// The format is a zip containing `modrinth.index.json`, an `overrides/` folder and
/// optionally a `server-overrides/` folder.
@MainActor
enum ModpackImporter {

    /// Installs a `.mrpack` file into the instances folder and returns the new instance.
    static func install(
        packURL: URL,
        into instancesDirectory: URL = AppPaths.instances,
        gameVersion: String? = nil,
        loader: String? = nil,
        loaderVersion: String? = nil
    ) async throws -> Instance {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("GameOnMRPack-\(UUID().uuidString)", isDirectory: true)
        defer { FileHelper.remove(staging) }
        try FileHelper.extractZip(packURL, to: staging)

        let indexURL = staging.appendingPathComponent("modrinth.index.json")
        guard let indexData = try? Data(contentsOf: indexURL),
              let index = try? JSONSerialization.jsonObject(with: indexData) as? [String: Any] else {
            throw LauncherError.invalidResponse
        }

        let name = index["name"] as? String ?? packURL.deletingPathExtension().lastPathComponent
        let resolvedVersion = gameVersion ?? (index["gameVersion"] as? String) ?? ""
        let resolvedLoader = loader ?? Self.loaderName(from: index)
        let resolvedLoaderVersion = loaderVersion ?? Self.loaderVersion(from: index)
        let versionNumber = index["versionId"] as? Int ?? 1

        // Create the instance folder.
        try FileManager.default.createDirectory(at: instancesDirectory, withIntermediateDirectories: true)
        let folderName = FileHelper.safeFolderName(name, fallback: "Modpack")
        let target = FileHelper.uniqueDirectory(in: instancesDirectory, named: folderName)
        try InstanceStore.prepareFolder(at: target)

        // Download every referenced mod.
        let files = index["files"] as? [[String: Any]] ?? []
        for entry in files {
            guard let path = entry["path"] as? String,
                  let downloads = entry["downloads"] as? [[String: Any]],
                  let first = downloads.first,
                  let rawURL = first["url"] as? String,
                  let remote = URL(string: rawURL) else { continue }

            let destination = target.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) { continue }

            var request = URLRequest(url: remote)
            request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
            FileHelper.remove(destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
        }

        // Apply the overrides folder shipped with the pack.
        let overrides = staging.appendingPathComponent("overrides", isDirectory: true)
        if FileManager.default.fileExists(atPath: overrides.path) {
            try FileHelper.mergeDirectory(source: overrides, destination: target)
        }

        // Persist metadata so the instance appears in the library.
        let metadata: [String: String] = [
            "name": name,
            "minecraftVersion": resolvedVersion,
            "loader": resolvedLoader,
            "source": "Modrinth · modrinth.index.json v\(versionNumber)"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: target.appendingPathComponent("instance.json"), options: .atomic)

        return Instance(
            id: target.lastPathComponent,
            name: name,
            minecraftVersion: resolvedVersion,
            loader: resolvedLoader,
            loaderVersion: resolvedLoaderVersion,
            source: "Modrinth",
            directory: target
        )
    }

    /// Reads the loader version out of a `modrinth.index.json`.
    private static func loaderVersion(from index: [String: Any]) -> String {
        let dependencies = index["dependencies"] as? [String: Any] ?? [:]
        if let version = dependencies["fabric-loader"] as? String { return version }
        if let version = dependencies["quilt-loader"] as? String { return version }
        if let version = dependencies["neoforge"] as? String { return version }
        if let version = dependencies["forge"] as? String { return version }
        return ""
    }

    /// Reads the loader name out of a `modrinth.index.json`.
    private static func loaderName(from index: [String: Any]) -> String {        let dependencies = index["dependencies"] as? [String: Any] ?? [:]
        if dependencies["fabric-loader"] != nil { return "Fabric" }
        if dependencies["neoforge"] != nil { return "NeoForge" }
        if dependencies["forge"] != nil { return "Forge" }
        if dependencies["quilt-loader"] != nil { return "Quilt" }
        return ""
    }

    /// Imports a `.mrpack` or CurseForge `.zip` dropped by the user.
    static func importArchive(_ url: URL) async throws -> Instance {
        if url.pathExtension.lowercased() == "mrpack" {
            return try await install(packURL: url)
        }
        throw LauncherError.operationFailed("Formato não suportado: \(url.pathExtension). Use um ficheiro .mrpack.")
    }
}
