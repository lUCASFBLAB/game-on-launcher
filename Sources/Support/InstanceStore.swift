import Foundation

/// A launcher-managed instance.
struct Instance: Identifiable, Hashable {
    let id: String
    var name: String
    var minecraftVersion: String
    var loader: String
    /// Exact loader version, for example `0.20.1` for Fabric.
    var loaderVersion: String
    var source: String
    var directory: URL

    /// The loader as a typed value.
    var modLoader: ModLoader {
        ModLoader(rawValue: loader.lowercased()) ?? .vanilla
    }

    var displayVersion: String { minecraftVersion.isEmpty ? "—" : minecraftVersion }

    var icon: String {
        switch loader.lowercased() {
        case "fabric": return "square.stack.3d.up.fill"
        case "forge": return "hammer.fill"
        case "neoforge": return "cube.transparent.fill"
        case "quilt": return "square.grid.3x3.fill"
        default: return "cube.fill"
        }
    }

    var loaderLabel: String { loader.isEmpty ? "Vanilla" : loader }
}

/// Metadata stored in `instance.json` inside a managed instance folder.
private struct InstanceMetadata: Codable {
    var name: String
    var minecraftVersion: String
    var loader: String
    var loaderVersion: String?
    var source: String
}

/// Reads and writes the set of launcher-managed instances.
@MainActor
final class InstanceStore: ObservableObject {
    @Published private(set) var managed: [Instance] = []

    /// Every instance visible in the launcher.
    var all: [Instance] { managed }

    func instance(named name: String) -> Instance? {
        all.first { $0.name == name }
    }

    // MARK: - Loading

    func reload() {
        managed = loadManagedInstances()
    }

    /// Reads the metadata stored next to an instance.
    private func readMetadata(at file: URL) -> InstanceMetadata? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(InstanceMetadata.self, from: data)
    }

    private func loadManagedInstances() -> [Instance] {
        let root = AppPaths.instances
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var result: [Instance] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let metadataURL = folder.appendingPathComponent("instance.json")
            let metadata = readMetadata(at: metadataURL)
            let rawName = metadata?.name ?? folder.lastPathComponent
            let name = InstanceStore.restoreName(rawName)
            result.append(
                Instance(
                    id: folder.lastPathComponent,
                    name: name,
                    minecraftVersion: metadata?.minecraftVersion ?? InstanceStore.extractVersion(from: name),
                    loader: metadata?.loader ?? InstanceStore.detectLoader(in: folder),
                    loaderVersion: metadata?.loaderVersion ?? "",
                    source: metadata?.source ?? "Personalizado",
                    directory: folder
                )
            )
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Folder layout

    /// Subfolders every instance gets on creation.
    static let standardFolders = ["mods", "resourcepacks", "shaderpacks", "saves", "screenshots", "logs", "config", "backups", "schematics"]

    /// Creates the standard folder layout for an instance and returns its root.
    @discardableResult
    nonisolated static func prepareFolder(at root: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in standardFolders {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: true)
        }
        return root
    }

    /// Restores a version number that was mangled by an older naming scheme.
    ///
    /// Earlier releases stripped every non-alphanumeric character, so `1.20.1`
    /// became `1201` and `26.3` became `263`. This puts the separators back.
    nonisolated static func restoreName(_ value: String) -> String {
        let pattern = #"\b(\d)(\d{2})(\d{1,2})\b"#
        var restored = value.replacingOccurrences(
            of: pattern,
            with: "$1.$2.$3",
            options: .regularExpression
        )
        restored = restored.replacingOccurrences(
            of: #"\b(\d{2})(\d)\b"#,
            with: "$1.$2",
            options: .regularExpression
        )
        return restored
    }

    /// Extracts a Minecraft version from an instance name.
    nonisolated static func extractVersion(from name: String) -> String {
        guard let match = name.range(of: #"\b\d+\.\d+(?:\.\d+)?\b"#, options: .regularExpression) else { return "" }
        return String(name[match])
    }

    /// Detects the mod loader used by an instance folder.
    nonisolated static func detectLoader(in folder: URL) -> String {
        let mods = FileHelper.files(in: folder.appendingPathComponent("mods", isDirectory: true)).map { $0.lastPathComponent.lowercased() }
        if mods.contains(where: { $0.contains("fabric-loader") }) { return "Fabric" }
        if mods.contains(where: { $0.contains("quilt-loader") }) { return "Quilt" }
        if mods.contains(where: { $0.contains("neoforge") }) { return "NeoForge" }
        if mods.contains(where: { $0.contains("forge") }) { return "Forge" }

        let libraries = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("libraries", isDirectory: true).path)) ?? []
        for entry in libraries {
            let lower = entry.lowercased()
            if lower.contains("neoforge") { return "NeoForge" }
            if lower.contains("minecraftforge") { return "Forge" }
            if lower.contains("quiltmc") { return "Quilt" }
            if lower.contains("fabricmc") { return "Fabric" }
        }
        return ""
    }

    /// Resolves the `mods` folder of an instance.
    nonisolated static func modsFolder(for instance: Instance) -> URL {
        let target = instance.directory.appendingPathComponent("mods", isDirectory: true)
        FileHelper.ensureDirectory(target)
        return target
    }

    /// Resolves a generic subfolder for an instance.
    nonisolated static func folder(_ name: String, for instance: Instance) -> URL {
        let target = instance.directory.appendingPathComponent(name, isDirectory: true)
        FileHelper.ensureDirectory(target)
        return target
    }

    // MARK: - Mutations

    /// Creates a new managed instance on disk.
    @discardableResult
    func create(name: String, version: String, loader: String, loaderVersion: String = "", source: String) throws -> Instance {
        let folderName = FileHelper.safeFolderName(name, fallback: "Instancia")
        let folder = FileHelper.uniqueDirectory(in: AppPaths.instances, named: folderName)
        try InstanceStore.prepareFolder(at: folder)
        let metadata = InstanceMetadata(name: name, minecraftVersion: version, loader: loader, loaderVersion: loaderVersion.isEmpty ? nil : loaderVersion, source: source)
        let data = try JSONEncoder().encode(metadata)
        try (data as NSData).write(to: folder.appendingPathComponent("instance.json"), options: .atomic)
        let instance = Instance(id: folder.lastPathComponent, name: name, minecraftVersion: version, loader: loader, loaderVersion: loaderVersion, source: source, directory: folder)
        managed.append(instance)
        managed.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return instance
    }

    /// Removes a managed instance and its folder.
    /// Stores the loader version that was resolved for an instance.
    @discardableResult
    func updateLoaderVersion(_ version: String, for id: String) -> Bool {
        guard let index = managed.firstIndex(where: { $0.id == id }) else { return false }
        let file = managed[index].directory.appendingPathComponent("instance.json")
        guard var metadata = readMetadata(at: file) else { return false }
        metadata.loaderVersion = version
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: file, options: .atomic)
        }
        managed[index].loaderVersion = version
        return true
    }

    func delete(_ instance: Instance) throws {
        FileHelper.remove(instance.directory)
        managed.removeAll { $0.id == instance.id }
    }

    /// Renames a managed instance, moving its folder and metadata.
    func rename(_ instance: Instance, to newName: String) throws {
        let clean = FileHelper.safeFolderName(newName, fallback: instance.name)
        guard clean != instance.id else { return }
        let target = FileHelper.uniqueDirectory(in: AppPaths.instances, named: clean)
        try FileManager.default.moveItem(at: instance.directory, to: target)
        let metadata = InstanceMetadata(name: newName, minecraftVersion: instance.minecraftVersion, loader: instance.loader, source: instance.source)
        let data = try JSONEncoder().encode(metadata)
        try (data as NSData).write(to: target.appendingPathComponent("instance.json"), options: .atomic)
        managed.removeAll { $0.id == instance.id }
        managed.append(Instance(id: target.lastPathComponent, name: newName, minecraftVersion: instance.minecraftVersion, loader: instance.loader, loaderVersion: instance.loaderVersion, source: instance.source, directory: target))
        managed.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
