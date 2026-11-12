import Foundation

/// Central location of every folder the launcher owns.
enum AppPaths {
    static let appFolderName = "GameOnLauncher"

    /// Root folder inside `Application Support`.
    static var root: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Instances managed natively by the launcher.
    static var instances: URL { ensure(root.appendingPathComponent("Instances", isDirectory: true)) }

    /// Downloaded modpacks and archives.
    static var downloads: URL { ensure(root.appendingPathComponent("Downloads", isDirectory: true)) }
    static var curseForgeDownloads: URL { ensure(downloads.appendingPathComponent("CurseForge", isDirectory: true)) }
    static var modrinthDownloads: URL { ensure(downloads.appendingPathComponent("Modrinth", isDirectory: true)) }

    /// Background images and videos.
    static var backgrounds: URL { ensure(root.appendingPathComponent("Backgrounds", isDirectory: true)) }

    /// Server installations.
    static var servers: URL { ensure(root.appendingPathComponent("Servers", isDirectory: true)) }

    /// Launcher logs.
    static var logs: URL { ensure(root.appendingPathComponent("Logs", isDirectory: true)) }

    /// Temporary staging used while importing archives.
    static var staging: URL { ensure(root.appendingPathComponent("Staging", isDirectory: true)) }

}

/// Small filesystem helpers shared across the app.
enum FileHelper {
    /// Removes a file or directory, ignoring missing paths.
    static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a directory (and intermediates) if it does not exist.
    @discardableResult
    static func ensureDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Recursively copies `source` into `destination`, merging folders and replacing files.
    static func mergeDirectory(source: URL, destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { continue }
            let target = destination.appendingPathComponent(child.lastPathComponent)
            if values.isDirectory == true {
                try mergeDirectory(source: child, destination: target)
            } else {
                remove(target)
                try manager.copyItem(at: child, to: target)
            }
        }
    }

    /// Extracts a zip archive using the system `ditto` tool.
    @discardableResult
    static func extractZip(_ archive: URL, to destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let extractor = Process()
        extractor.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        extractor.arguments = ["-x", "-k", archive.path, destination.path]
        let errors = Pipe()
        extractor.standardError = errors
        extractor.standardOutput = Pipe()
        try extractor.run()
        extractor.waitUntilExit()
        guard extractor.terminationStatus == 0 else {
            let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw LauncherError.archiveFailure(detail)
        }
        return destination
    }

    /// Strips characters that are unsafe in a folder name.
    static func safeFolderName(_ value: String, fallback: String = "Pasta") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ()"))
        let cleaned = String(value.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Unique folder path, appending " (2)", " (3)"… when the target already exists.
    static func uniqueDirectory(in parent: URL, named name: String) -> URL {
        var target = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(name) (\(suffix))", isDirectory: true)
            suffix += 1
        }
        return target
    }

    /// Human readable byte size.
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Lists every regular file in a directory (non-recursive).
    static func files(in directory: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [] }
        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
}

/// Errors raised by the launcher's own services.
enum LauncherError: LocalizedError {
    case archiveFailure(String)
    case invalidResponse
    case missingFile(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveFailure(let detail):
            return detail.isEmpty ? "Não foi possível extrair o arquivo." : "Não foi possível extrair o arquivo: \(detail)"
        case .invalidResponse:
            return "A resposta do serviço não foi válida."
        case .missingFile(let name):
            return "Ficheiro em falta: \(name)"
        case .operationFailed(let detail):
            return detail
        }
    }
}
