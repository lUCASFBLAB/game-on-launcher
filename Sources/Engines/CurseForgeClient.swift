import Foundation
import Security

/// A CurseForge project (mod, modpack or map).
struct CurseForgeProject: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let summary: String?
    let downloadCount: Int64
    let logo: Logo?

    struct Logo: Decodable, Hashable {
        let thumbnailUrl: String?
        let url: String?
    }
}

/// A downloadable file belonging to a CurseForge project.
struct CurseForgeFile: Identifiable, Decodable, Hashable {
    let id: Int
    let displayName: String
    let fileName: String
    let downloadUrl: String?
    let gameVersions: [String]?
    let fileDate: String?
    let fileLength: Int64?
}

/// The result of installing a CurseForge modpack.
struct InstalledCurseForgePack {
    let directory: URL
    let name: String
    let minecraftVersion: String
    let loader: String
}

/// Errors raised by the CurseForge client.
enum CurseForgeError: LocalizedError {
    case missingKey
    case invalidResponse
    case http(Int, String)
    case noCompatibleFile
    case missingFiles(Int)
    case invalidPack
    case archive(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Guarde uma API key CurseForge nas definições."
        case .invalidResponse: return "A resposta da API CurseForge não foi válida."
        case .http(let code, let detail): return "CurseForge respondeu HTTP \(code): \(detail)"
        case .noCompatibleFile: return "Não foi encontrado um ficheiro compatível com esta seleção."
        case .missingFiles(let count): return "CurseForge não devolveu \(count) ficheiro(s) obrigatório(s) do modpack."
        case .invalidPack: return "O ZIP não contém um manifesto CurseForge válido."
        case .archive(let detail): return "Não foi possível extrair o modpack: \(detail)"
        }
    }
}

/// Secure storage backed by the macOS Keychain.
enum LocalSecretStore {
    private static let service = "com.gameonlauncher.secrets"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores a secret, replacing any previous value for the same account.
    static func write(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)

        // Try an in-place update first.
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        // Nothing stored yet — create the item with an explicit accessibility.
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecAttrLabel as String] = "Game on Launcher — \(account)"
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Talks to the official CurseForge REST API.
actor CurseForgeClient {
    static let shared = CurseForgeClient()

    private let root = URL(string: "https://api.curseforge.com/v1")!
    private let gameID = 432
    private let userAgent = "GameOnLauncher/1.0 (macOS)"

    /// Returns the Minecraft versions supported by CurseForge.
    func versions(apiKey: String) async throws -> [String] {
        let object = try await request(path: "minecraft/version", query: [URLQueryItem(name: "sortDescending", value: "true")], apiKey: apiKey)
        guard let values = object["data"] as? [[String: Any]] else { throw CurseForgeError.invalidResponse }
        return values.compactMap { $0["versionString"] as? String }
    }

    /// Searches mods, modpacks or maps.
    func search(_ query: String, kind: String, gameVersion: String, loader: String, apiKey: String) async throws -> [CurseForgeProject] {
        let classes = try await request(
            path: "categories",
            query: [URLQueryItem(name: "gameId", value: String(gameID)), URLQueryItem(name: "classesOnly", value: "true")],
            apiKey: apiKey
        )
        guard let rows = classes["data"] as? [[String: Any]] else { throw CurseForgeError.invalidResponse }

        let className = kind == "Modpacks" ? "modpacks" : (kind == "Mapas" ? "worlds" : "mods")
        guard let classID = rows.first(where: { (($0["name"] as? String) ?? "").localizedCaseInsensitiveContains(className) })?["id"] as? Int else {
            throw CurseForgeError.invalidResponse
        }

        var items = [
            URLQueryItem(name: "gameId", value: String(gameID)),
            URLQueryItem(name: "classId", value: String(classID)),
            URLQueryItem(name: "pageSize", value: "30"),
            URLQueryItem(name: "sortField", value: "downloads"),
            URLQueryItem(name: "sortOrder", value: "desc")
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "searchFilter", value: trimmed)) }
        if !gameVersion.isEmpty { items.append(URLQueryItem(name: "gameVersion", value: gameVersion)) }
        if kind == "Mods", let loaderID = loaderID(loader) { items.append(URLQueryItem(name: "modLoaderType", value: String(loaderID))) }

        let response = try await request(path: "mods/search", query: items, apiKey: apiKey)
        guard let data = response["data"] as? [[String: Any]] else { throw CurseForgeError.invalidResponse }
        return try JSONDecoder().decode([CurseForgeProject].self, from: JSONSerialization.data(withJSONObject: data))
    }

    /// Downloads the newest compatible file of a project.
    func download(project: CurseForgeProject, kind: String, gameVersion: String, loader: String, to destination: URL, apiKey: String) async throws -> URL {
        var items = [URLQueryItem(name: "pageSize", value: "50")]
        if kind != "Modpacks" && !gameVersion.isEmpty { items.append(URLQueryItem(name: "gameVersion", value: gameVersion)) }
        if kind == "Mods", let loaderID = loaderID(loader) { items.append(URLQueryItem(name: "modLoaderType", value: String(loaderID))) }

        let filesResponse = try await request(path: "mods/\(project.id)/files", query: items, apiKey: apiKey)
        guard let rows = filesResponse["data"] as? [[String: Any]], let first = rows.first, let fileID = first["id"] as? Int else {
            throw CurseForgeError.noCompatibleFile
        }
        let file = try JSONDecoder().decode(CurseForgeFile.self, from: JSONSerialization.data(withJSONObject: first))

        var downloadString = file.downloadUrl
        if downloadString == nil || downloadString?.isEmpty == true {
            let urlResponse = try await request(path: "mods/\(project.id)/files/\(fileID)/download-url", query: [], apiKey: apiKey)
            downloadString = urlResponse["data"] as? String
        }
        guard let rawURL = downloadString, let downloadURL = URL(string: rawURL) else {
            throw CurseForgeError.noCompatibleFile
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: file.fileName).lastPathComponent
        let target = destination.appendingPathComponent(safeName.isEmpty ? "\(project.id)-\(file.id).zip" : safeName)
        try await streamDownload(downloadURL, to: target)
        return target
    }

    /// Downloads and installs a modpack into the instances folder.
    func installModpack(project: CurseForgeProject, to instancesDirectory: URL, downloadsDirectory: URL, apiKey: String) async throws -> InstalledCurseForgePack {
        let archive = try await download(project: project, kind: "Modpacks", gameVersion: "", loader: "", to: downloadsDirectory, apiKey: apiKey)

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("GameOnPack-\(UUID().uuidString)", isDirectory: true)
        defer { FileHelper.remove(staging) }
        try FileHelper.extractZip(archive, to: staging)

        let manifestURL = staging.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let minecraft = manifest["minecraft"] as? [String: Any],
              let minecraftVersion = minecraft["version"] as? String,
              let packName = manifest["name"] as? String,
              let packFiles = manifest["files"] as? [[String: Any]] else { throw CurseForgeError.invalidPack }

        let modLoaders = minecraft["modLoaders"] as? [[String: Any]] ?? []
        let loaderID = modLoaders.first(where: { ($0["primary"] as? Bool) == true })?["id"] as? String
            ?? modLoaders.first?["id"] as? String
            ?? "Vanilla"
        let loader = loaderID.split(separator: "-").first.map(String.init) ?? "Vanilla"

        try FileManager.default.createDirectory(at: instancesDirectory, withIntermediateDirectories: true)
        let baseName = FileHelper.safeFolderName(packName, fallback: "CurseForge Modpack")
        let target = FileHelper.uniqueDirectory(in: instancesDirectory, named: baseName)
        try InstanceStore.prepareFolder(at: target)

        // Download every required file referenced by the manifest.
        let fileIDs = Array(Set(packFiles.filter { ($0["required"] as? Bool) != false }.compactMap { $0["fileID"] as? Int }))
        for offset in stride(from: 0, to: fileIDs.count, by: 50) {
            let ids = Array(fileIDs[offset..<min(offset + 50, fileIDs.count)])
            let response = try await request(path: "mods/files", query: [], apiKey: apiKey, method: "POST", body: ["fileIds": ids])
            let remoteFiles = response["data"] as? [[String: Any]] ?? []
            let returnedIDs = Set(remoteFiles.compactMap { $0["id"] as? Int })
            let missingCount = ids.filter { !returnedIDs.contains($0) }.count
            guard missingCount == 0 else { throw CurseForgeError.missingFiles(missingCount) }

            for row in remoteFiles {
                guard let modID = row["modId"] as? Int,
                      let fileID = row["id"] as? Int,
                      let fileName = row["fileName"] as? String else { continue }
                var rawURL = row["downloadUrl"] as? String
                if rawURL == nil || rawURL?.isEmpty == true {
                    let link = try await request(path: "mods/\(modID)/files/\(fileID)/download-url", query: [], apiKey: apiKey)
                    rawURL = link["data"] as? String
                }
                guard let text = rawURL, let url = URL(string: text) else { continue }
                let name = URL(fileURLWithPath: fileName).lastPathComponent
                let fileDestination = target.appendingPathComponent("mods", isDirectory: true).appendingPathComponent(name)
                try await streamDownload(url, to: fileDestination)
            }
        }

        // Merge the overrides folder shipped with the pack.
        let overridesName = manifest["overrides"] as? String ?? "overrides"
        let overrides = staging.appendingPathComponent(overridesName, isDirectory: true)
        if FileManager.default.fileExists(atPath: overrides.path) {
            try FileHelper.mergeDirectory(source: overrides, destination: target)
        }

        let metadata: [String: String] = [
            "name": packName,
            "minecraftVersion": minecraftVersion,
            "loader": loader,
            "source": "CurseForge"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: target.appendingPathComponent("instance.json"), options: .atomic)

        return InstalledCurseForgePack(directory: target, name: target.lastPathComponent, minecraftVersion: minecraftVersion, loader: loader)
    }

    // MARK: - Private

    private func loaderID(_ name: String) -> Int? {
        switch name.lowercased() {
        case "forge": return 1
        case "fabric": return 4
        case "quilt": return 5
        case "neoforge": return 6
        default: return nil
        }
    }

    private func request(path: String, query: [URLQueryItem], apiKey: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CurseForgeError.missingKey }
        var components = URLComponents(url: root.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CurseForgeError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw CurseForgeError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CurseForgeError.invalidResponse
        }
        return object
    }

    private func streamDownload(_ url: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CurseForgeError.invalidResponse
        }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
