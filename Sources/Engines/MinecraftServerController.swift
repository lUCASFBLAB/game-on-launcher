import AppKit
import Combine
import Foundation

/// A plugin published on Modrinth.
struct ModrinthPlugin: Identifiable, Decodable, Hashable {
    let project_id: String
    let title: String
    let description: String
    let downloads: Int
    var id: String { project_id }
}

/// A file inside a managed server folder.
struct ManagedServerFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool
}

/// Controls a local Minecraft server process.
@MainActor
final class MinecraftServerController: ObservableObject {
    @Published private(set) var status = "Servidor ainda não criado"
    @Published private(set) var console = "Centro de servidor pronto. Crie ou abra um servidor para começar.\n"
    @Published private(set) var directoryURL: URL?
    @Published private(set) var files: [ManagedServerFile] = []
    @Published private(set) var paperVersions: [String] = []
    @Published private(set) var plugins: [ModrinthPlugin] = []
    @Published private(set) var busy = false
    @Published private(set) var running = false
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsageMB: Double = 0
    @Published var fileSearch = ""

    private var process: Process?
    private var input: Pipe?
    private var monitorTask: Task<Void, Never>?
    private let userAgent = "GameOnLauncher/1.0 (macOS Minecraft launcher)"

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Version discovery

    /// Loads the available Paper versions from the official API.
    func loadPaperVersions() async {
        do {
            let data = try await get(URL(string: "https://fill.papermc.io/v3/projects/paper")!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let groups = json?["versions"] as? [String: [String]] ?? [:]
            paperVersions = groups.values.flatMap { $0 }.uniqued().sorted {
                $0.compare($1, options: .numeric, locale: Locale(identifier: "en_US_POSIX")) == .orderedDescending
            }
            if paperVersions.isEmpty { status = "Não foi possível carregar versões Paper." }
        } catch {
            status = "Falha ao carregar versões Paper: \(error.localizedDescription)"
        }
    }

    // MARK: - Server creation

    /// Downloads and installs a Paper server.
    func createPaperServer(name: String, version: String) async {
        guard !busy else { return }
        busy = true
        status = "A procurar uma versão Paper estável…"
        defer { busy = false }
        do {
            let folder = try serverFolder(named: name)
            let encoded = version.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? version
            let buildsURL = URL(string: "https://fill.papermc.io/v3/projects/paper/versions/\(encoded)/builds")!
            let buildsData = try await get(buildsURL)
            guard let builds = try JSONSerialization.jsonObject(with: buildsData) as? [[String: Any]] else {
                throw ServerError.invalidResponse
            }
            let stable = builds.first(where: { ($0["channel"] as? String) == "STABLE" }) ?? builds.first
            guard let downloadInfo = stable?["downloads"] as? [String: Any],
                  let serverDefault = downloadInfo["server:default"] as? [String: Any],
                  let rawURL = serverDefault["url"] as? String,
                  let fileURL = URL(string: rawURL) else { throw ServerError.noBuild }

            status = "A transferir Paper \(version)…"
            try await download(fileURL, to: folder.appendingPathComponent("paper.jar"))
            try "eula=false\n".write(to: folder.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)
            try writeDefaultServerProperties(in: folder)
            directoryURL = folder
            status = "Paper \(version) instalado · EULA por aceitar"
            append("Paper \(version) transferido para \(folder.path).\nLeia e aceite a EULA antes de iniciar o servidor.\n")
            refreshFiles()
        } catch {
            status = "Falha ao criar servidor: \(error.localizedDescription)"
            append("\(status)\n")
        }
    }

    /// Downloads and installs a Fabric server.
    func createFabricServer(name: String, version: String) async {
        guard !busy else { return }
        busy = true
        status = "A preparar o servidor Fabric oficial…"
        defer { busy = false }
        do {
            let game = version.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? version
            let loaderData = try await get(URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(game)")!)
            guard let loaders = try JSONSerialization.jsonObject(with: loaderData) as? [[String: Any]],
                  let loader = (loaders.first?["loader"] as? [String: Any])?["version"] as? String else {
                throw ServerError.noBuild
            }
            let installerData = try await get(URL(string: "https://meta.fabricmc.net/v2/versions/installer")!)
            guard let installers = try JSONSerialization.jsonObject(with: installerData) as? [[String: Any]],
                  let installer = installers.first?["version"] as? String else { throw ServerError.noBuild }

            let encodedLoader = loader.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loader
            let encodedInstaller = installer.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? installer
            let jarURL = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(game)/\(encodedLoader)/\(encodedInstaller)/server/jar")!

            let folder = try serverFolder(named: name)
            status = "A transferir Fabric server para Minecraft \(version)…"
            try await download(jarURL, to: folder.appendingPathComponent("fabric-server-launch.jar"))
            try "eula=false\n".write(to: folder.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)
            try writeDefaultServerProperties(in: folder)
            directoryURL = folder
            status = "Fabric instalado · Minecraft \(version) · loader \(loader) · EULA por aceitar"
            append("Fabric server transferido para \(folder.path).\nLeia e aceite a EULA antes de iniciar.\n")
            refreshFiles()
        } catch {
            status = "Falha ao criar servidor Fabric: \(error.localizedDescription)"
            append("\(status)\n")
        }
    }

    /// Downloads the Forge/NeoForge installer and runs it.
    func createInstallerServer(name: String, gameVersion: String, software: String) async {
        guard !busy else { return }
        busy = true
        status = "A consultar versões oficiais de \(software)…"
        defer { busy = false }
        do {
            let forge = software == "Forge"
            let metadataURL = URL(string: forge
                ? "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml"
                : "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!
            let metadata = String(data: try await get(metadataURL), encoding: .utf8) ?? ""
            let allVersions = metadata
                .components(separatedBy: "<version>")
                .dropFirst()
                .compactMap { $0.components(separatedBy: "</version>").first }

            let prefix: String
            if forge {
                prefix = "\(gameVersion)-"
            } else {
                let parts = gameVersion.split(separator: ".")
                guard parts.count >= 3 else { throw ServerError.noBuild }
                prefix = "\(parts[1]).\(parts[2])."
            }
            guard let installerVersion = allVersions.last(where: { $0.hasPrefix(prefix) }) else {
                throw ServerError.noBuild
            }

            let artifact = forge ? "forge" : "neoforge"
            let base = forge
                ? "https://maven.minecraftforge.net/net/minecraftforge/forge"
                : "https://maven.neoforged.net/releases/net/neoforged/neoforge"
            let installerURL = URL(string: "\(base)/\(installerVersion)/\(artifact)-\(installerVersion)-installer.jar")!

            let folder = try serverFolder(named: name)
            let installer = folder.appendingPathComponent("\(artifact)-installer.jar")
            status = "A transferir instalador \(software) \(installerVersion)…"
            try await download(installerURL, to: installer)

            status = "A instalar \(software) no servidor…"
            let log = try await runInstaller(installer, in: folder)
            guard log.exitCode == 0 else { throw ServerError.installer(log.output) }

            try "eula=false\n".write(to: folder.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)
            try writeDefaultServerProperties(in: folder)
            directoryURL = folder
            status = "\(software) \(installerVersion) instalado · EULA por aceitar"
            append("\(software) instalado para Minecraft \(gameVersion).\n\(log.output)\nAceite a EULA antes de iniciar.\n")
            refreshFiles()
        } catch {
            status = "Falha ao criar servidor \(software): \(error.localizedDescription)"
            append("\(status)\n")
        }
    }

    /// Runs the installer and captures its output.
    ///
    /// The pipe is drained concurrently — reading it only after the process exits
    /// would deadlock as soon as the installer produces more than 64 KB of output.
    private func runInstaller(_ installer: URL, in folder: URL) async throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["java", "-jar", installer.lastPathComponent, "--installServer"]
        process.currentDirectoryURL = folder

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        var collected = Data()
        let collector = OutputCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            collector.append(data)
        }

        defer { output.fileHandleForReading.readabilityHandler = nil }

        try process.run()
        // Drain the pipe while the process runs so it never blocks on a full buffer.
        while process.isRunning {
            try await Task.sleep(nanoseconds: 120_000_000)
        }
        process.waitUntilExit()
        collected = collector.data()

        let text = String(data: collected, encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    /// Creates the server folder and a sane `server.properties`.
    private func serverFolder(named name: String) throws -> URL {
        let folder = AppPaths.servers.appendingPathComponent(FileHelper.safeFolderName(name, fallback: "Meu servidor"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeDefaultServerProperties(in folder: URL) throws {
        let url = folder.appendingPathComponent("server.properties")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let contents = """
        #Minecraft server properties — generated by Game on Launcher
        server-port=25565
        max-players=20
        online-mode=true
        level-name=world
        level-seed=
        gamemode=survival
        difficulty=easy
        spawn-protection=16
        enable-command-block=false
        sync-chunk-writes=true
        view-distance=10
        simulation-distance=10
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Folder selection

    func openServerFolder() throws {
        let folder: URL
        if let directoryURL {
            folder = directoryURL
        } else {
            folder = AppPaths.servers
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        directoryURL = folder
        NSWorkspace.shared.open(folder)
        refreshFiles()
    }

    func chooseServerFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar servidor"
        if panel.runModal() == .OK, let url = panel.url {
            selectDirectory(url)
        }
    }

    func selectDirectory(_ url: URL) {
        directoryURL = url
        refreshFiles()
        status = "Servidor selecionado · \(url.lastPathComponent)"
    }

    // MARK: - Files

    /// Refreshes the file listing of the selected server folder.
    func refreshFiles() {
        guard let folder = directoryURL else {
            files = []
            return
        }
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            files = []
            return
        }
        var result: [ManagedServerFile] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            result.append(ManagedServerFile(url: url, size: size, isDirectory: isDirectory))
        }
        files = result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Files matching the current search term.
    var filteredFiles: [ManagedServerFile] {
        let query = fileSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func openFile(_ file: ManagedServerFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    /// Deletes a file, refusing anything outside the server folder.
    func deleteFile(_ file: ManagedServerFile) throws {
        guard let folder = directoryURL,
              file.url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else {
            throw ServerError.unsafePath
        }
        try FileManager.default.removeItem(at: file.url)
        refreshFiles()
    }

    // MARK: - Process control

    /// Starts the server with the given memory allocation.
    func start(acceptedEULA: Bool, memoryGB: Int) {
        guard acceptedEULA else {
            status = "Aceite a EULA oficial do Minecraft para iniciar."
            return
        }
        guard let folder = directoryURL else {
            status = "Crie/baixe um servidor primeiro."
            return
        }
        guard process?.isRunning != true else {
            status = "O servidor já está em execução."
            return
        }

        let memory = max(2, memoryGB)

        // A `run.sh` produced by the Forge/NeoForge installer takes priority.
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("run.sh").path) {
            do {
                let script = Process()
                script.executableURL = URL(fileURLWithPath: "/bin/sh")
                script.arguments = ["run.sh", "nogui"]
                script.currentDirectoryURL = folder
                try launch(script, in: folder)
                status = "Servidor modificado a iniciar…"
                append("A iniciar com run.sh · até \(memory) GB de RAM.\n")
                return
            } catch {
                status = "Não foi possível iniciar o servidor: \(error.localizedDescription)"
                return
            }
        }

        let jarName = ["paper.jar", "fabric-server-launch.jar"].first {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        guard let jarName else {
            status = "Crie/baixe um servidor Paper ou Fabric primeiro."
            return
        }

        do {
            try "eula=true\n".write(to: folder.appendingPathComponent("eula.txt"), atomically: true, encoding: .utf8)
            let server = Process()
            server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            server.arguments = ["java", "-Xms1G", "-Xmx\(memory)G", "-jar", jarName, "--nogui"]
            server.currentDirectoryURL = folder
            try launch(server, in: folder)
            status = "Servidor a iniciar…"
            append("A iniciar \(jarName.hasPrefix("fabric") ? "Fabric" : "Paper") com até \(memory) GB de RAM.\n")
        } catch {
            status = "Não foi possível iniciar Java: \(error.localizedDescription)"
            append("\(status)\n")
        }
    }

    /// Wires the process pipes and starts it.
    private func launch(_ process: Process, in folder: URL) throws {
        let output = Pipe()
        let standardInput = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = standardInput

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.append(text) }
        }

        process.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            let code = ended.terminationStatus
            Task { @MainActor [weak self] in
                self?.running = false
                self?.status = "Servidor parado · código \(code)"
                self?.append("\nServidor encerrado.\n")
                self?.refreshFiles()
                self?.stopMonitoring()
            }
        }

        try process.run()
        self.process = process
        self.input = standardInput
        running = true
        startMonitoring(process)
    }

    /// Sends a command to the server console.
    func sendCommand(_ text: String) {
        guard let input, process?.isRunning == true else {
            status = "O servidor não está em execução."
            return
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8))
        } catch {
            status = "Falha ao enviar comando: \(error.localizedDescription)"
        }
    }

    /// Gracefully stops the server.
    func stop() {
        guard process?.isRunning == true else {
            status = "O servidor não está em execução."
            return
        }
        sendCommand("stop")
    }

    /// Force-kills the server process.
    func forceStop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        running = false
        status = "Servidor terminado à força"
        stopMonitoring()
    }

    // MARK: - Resource monitoring

    /// Samples the server process CPU and memory usage.
    private func startMonitoring(_ process: Process) {
        stopMonitoring()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, process.isRunning else { return }
                let pid = process.processIdentifier
                await MainActor.run {
                    self.cpuUsage = Self.sampleCPU(pid: pid)
                    self.memoryUsageMB = Self.sampleMemory(pid: pid)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        cpuUsage = 0
        memoryUsageMB = 0
    }

    /// Reads CPU usage from `ps`.
    nonisolated private static func sampleCPU(pid: Int32) -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "%cpu", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return 0 }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let value = output.split(separator: "\n").last.map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 } ?? 0
        return value
    }

    /// Reads resident memory from `ps` (reported in KB).
    nonisolated private static func sampleMemory(pid: Int32) -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "rss", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return 0 }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let kilobytes = output.split(separator: "\n").last.map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 } ?? 0
        return kilobytes / 1024
    }

    // MARK: - Plugins

    /// Searches Modrinth for Paper plugins.
    func searchPlugins(query: String, gameVersion: String) async {
        do {
            var components = URLComponents(string: "https://api.modrinth.com/v2/search")!
            components.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "facets", value: "[[\"all_project_types:plugin\"],[\"versions:\(gameVersion)\"]]")
            ]
            let data = try await get(components.url!)
            let response = try JSONDecoder().decode(PluginSearchResponse.self, from: data)
            plugins = response.hits
            status = "\(plugins.count) plugins encontrados · Modrinth"
        } catch {
            status = "Falha ao procurar plugins: \(error.localizedDescription)"
        }
    }

    /// Downloads a plugin into the server's `plugins/` folder.
    func downloadPlugin(_ plugin: ModrinthPlugin, gameVersion: String) async {
        guard let folder = directoryURL else {
            status = "Crie ou selecione uma pasta de servidor primeiro."
            return
        }
        do {
            var components = URLComponents(string: "https://api.modrinth.com/v2/project/\(plugin.project_id)/version")!
            components.queryItems = [
                URLQueryItem(name: "game_versions", value: "[\"\(gameVersion)\"]"),
                URLQueryItem(name: "loaders", value: "[\"paper\"]")
            ]
            let data = try await get(components.url!)
            guard let versions = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = versions.first,
                  let files = first["files"] as? [[String: Any]],
                  let file = files.first,
                  let urlText = file["url"] as? String,
                  let remoteURL = URL(string: urlText),
                  let fileName = file["filename"] as? String else { throw ServerError.noPluginFile }

            let pluginsFolder = folder.appendingPathComponent("plugins", isDirectory: true)
            try FileManager.default.createDirectory(at: pluginsFolder, withIntermediateDirectories: true)
            try await download(remoteURL, to: pluginsFolder.appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent))
            status = "Plugin guardado em plugins/ · reinicie o servidor para carregar."
            append("Plugin transferido: \(plugin.title)\n")
            refreshFiles()
        } catch {
            status = "Falha ao transferir plugin: \(error.localizedDescription)"
        }
    }

    /// Removes a plugin from the server's `plugins/` folder.
    func removePlugin(_ plugin: ModrinthPlugin) {
        guard let folder = directoryURL else { return }
        let pluginsFolder = folder.appendingPathComponent("plugins", isDirectory: true)
        let matches = FileHelper.files(in: pluginsFolder).filter { url in
            url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains(plugin.title)
                || url.lastPathComponent.localizedCaseInsensitiveContains(plugin.project_id)
        }
        for match in matches { FileHelper.remove(match) }
        if !matches.isEmpty {
            status = "Plugin removido de plugins/"
            refreshFiles()
        }
    }

    // MARK: - Console

    private func append(_ text: String) {
        console += text
        if console.count > 150_000 { console = String(console.suffix(100_000)) }
    }

    func clearConsole() {
        console = ""
    }

    /// Copies the console output to the pasteboard.
    func copyConsole() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(console, forType: .string)
    }

    // MARK: - HTTP

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 90
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServerError.http(http.statusCode) }
        return data
    }

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServerError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ServerError.http(http.statusCode) }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}


// MARK: - Models & errors

private struct PluginSearchResponse: Decodable {
    let hits: [ModrinthPlugin]
}

private enum ServerError: LocalizedError {
    case invalidResponse
    case noBuild
    case noPluginFile
    case unsafePath
    case http(Int)
    case installer(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Resposta do servidor inválida."
        case .noBuild: return "Não foi encontrada uma versão compatível para este servidor."
        case .noPluginFile: return "Não foi encontrado um ficheiro Paper compatível."
        case .unsafePath: return "O ficheiro está fora da pasta do servidor."
        case .http(let code): return "HTTP \(code) ao contactar a fonte de downloads."
        case .installer(let detail): return "O instalador terminou com erro: \(detail.suffix(1000))"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
