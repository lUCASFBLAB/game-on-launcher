import Foundation
import AppKit

/// A log file discovered inside an instance.
struct LogFile: Identifiable, Hashable {
    let url: URL
    let category: String
    let modified: Date
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// Reads real log files from an instance and follows them while the game runs.
@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var files: [LogFile] = []
    @Published private(set) var selectedCategory: String = "Registo do Minecraft"
    @Published private(set) var content: String = ""
    @Published var searchText: String = ""
    @Published private(set) var autoRefresh = true

    private var instanceDirectory: URL?
    private var followTask: Task<Void, Never>?

    /// Available categories in the sidebar.
    static let categories = [
        "Registo do Minecraft", "Versão", "Mods", "Pacotes de recursos", "Pacotes de shaders",
        "Notas", "Mundos", "Servidores", "Capturas de ecrã", "Definições", "Launcher", "Outros registos"
    ]

    /// Lines matching the current search term.
    var filteredContent: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return content }
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .joined(separator: "\n")
    }

    var isEmpty: Bool { content.isEmpty }

    // MARK: - Instance binding

    func bind(to directory: URL?) {
        guard directory != instanceDirectory else { return }
        instanceDirectory = directory
        refreshFiles()
        loadSelected()
    }

    // MARK: - Discovery

    /// Scans the instance for log-like files grouped by category.
    func refreshFiles() {
        guard let directory = instanceDirectory else { files = []; return }
        var discovered: [LogFile] = []

        func add(_ url: URL, category: String) {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
            discovered.append(LogFile(url: url, category: category, modified: values.contentModificationDate ?? .distantPast, size: Int64(values.fileSize ?? 0)))
        }

        // `logs/` folder holds the game's latest.log, debug.log and crash reports.
        let logsFolder = directory.appendingPathComponent("logs", isDirectory: true)
        for url in FileHelper.files(in: logsFolder) {
            let category = url.lastPathComponent.hasPrefix("crash")
                ? "Outros registos"
                : (url.lastPathComponent.contains("debug") ? "Launcher" : "Registo do Minecraft")
            add(url, category: category)
        }

        // Crash reports live under `crash-reports/`.
        let crashFolder = directory.appendingPathComponent("crash-reports", isDirectory: true)
        for url in FileHelper.files(in: crashFolder) { add(url, category: "Outros registos") }

        // Per-category folders across the instance.
        let categoryFolders = [
            "Mods": "mods", "Pacotes de recursos": "resourcepacks", "Pacotes de shaders": "shaderpacks",
            "Notas": "notes", "Mundos": "saves", "Servidores": "servers", "Capturas de ecrã": "screenshots",
            "Definições": "config", "Versão": "versions"
        ]
        for (category, folder) in categoryFolders {
            let target = directory.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            for url in FileHelper.files(in: target) { add(url, category: category) }
        }

        files = discovered.sorted {
            $0.category == $1.category
                ? $0.modified > $1.modified
                : $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
        }

        if !files.contains(where: { $0.category == selectedCategory }), let first = files.first {
            selectedCategory = first.category
        }
    }

    /// Number of files available for a category.
    func count(for category: String) -> Int {
        files.filter { $0.category == category }.count
    }

    /// Most recent file in a category.
    func latest(in category: String) -> LogFile? {
        files.filter { $0.category == category }.max { $0.modified < $1.modified }
    }

    // MARK: - Reading

    func select(category: String) {
        selectedCategory = category
        loadSelected()
    }

    /// Loads the newest file of the selected category into `content`.
    func loadSelected() {
        guard let file = latest(in: selectedCategory) else {
            content = ""
            stopFollowing()
            return
        }
        content = (try? String(contentsOf: file.url, encoding: .utf8))
            ?? (try? String(contentsOf: file.url, encoding: .isoLatin1))
            ?? ""
        startFollowing(file)
    }

    /// Polls the active file so the view stays live while the game writes to it.
    private func startFollowing(_ file: LogFile) {
        stopFollowing()
        guard autoRefresh else { return }
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, !Task.isCancelled else { return }
                let updated = (try? String(contentsOf: file.url, encoding: .utf8))
                    ?? (try? String(contentsOf: file.url, encoding: .isoLatin1))
                    ?? ""
                if updated != self.content {
                    await MainActor.run {
                        self.content = updated
                        self.refreshFiles()
                    }
                }
            }
        }
    }

    func stopFollowing() {
        followTask?.cancel()
        followTask = nil
    }

    func toggleAutoRefresh() {
        autoRefresh.toggle()
        if autoRefresh {
            loadSelected()
        } else {
            stopFollowing()
        }
    }

    /// Copies the current log content to the pasteboard.
    func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    /// Writes the current log content to a file in the launcher logs folder.
    @discardableResult
    func export() -> URL? {
        let destination = AppPaths.logs.appendingPathComponent("\(selectedCategory.replacingOccurrences(of: " ", with: "-"))-\(Int(Date().timeIntervalSince1970)).log")
        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        } catch {
            return nil
        }
    }

    deinit {
        followTask?.cancel()
    }
}
