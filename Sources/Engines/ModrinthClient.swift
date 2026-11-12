import Foundation

/// A project published on Modrinth.
struct ModrinthProject: Identifiable, Decodable, Hashable {
    let project_id: String
    let title: String
    let description: String
    let downloads: Int
    let icon_url: String?
    let project_type: String
    var id: String { project_id }

    /// Author display name, when available.
    let author: String?

    enum CodingKeys: String, CodingKey {
        case project_id, title, description, downloads, icon_url, project_type, author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project_id = try container.decode(String.self, forKey: .project_id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
        icon_url = try container.decodeIfPresent(String.self, forKey: .icon_url)
        project_type = try container.decodeIfPresent(String.self, forKey: .project_type) ?? "mod"
        author = try container.decodeIfPresent(String.self, forKey: .author)
    }
}

/// A downloaded file.
struct DownloadedModrinthFile {
    let url: URL
    let version: String
}

/// Errors raised by the Modrinth client.
enum ModrinthClientError: LocalizedError {
    case invalidResponse
    case noCompatibleFile
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "A resposta do Modrinth não foi válida."
        case .noCompatibleFile: return "Não há ficheiro compatível para esta versão e loader."
        case .http(let status): return "O Modrinth respondeu com HTTP \(status)."
        }
    }
}

/// Talks to the official Modrinth API (no key required).
actor ModrinthClient {
    static let shared = ModrinthClient()

    private let root = URL(string: "https://api.modrinth.com/v2")!
    private let userAgent = "GameOnLauncher/1.0 (macOS)"

    /// Searches the catalogue.
    func search(query: String, kind: String, gameVersion: String, loader: String) async throws -> [ModrinthProject] {
        var components = URLComponents(url: root.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        var facets: [[String]] = [["project_type:\(Self.projectType(for: kind))"]]
        if !gameVersion.isEmpty { facets.append(["versions:\(gameVersion)"]) }
        let loaderFacet = Self.loaderFacet(loader)
        if !loaderFacet.isEmpty && kind == "Mods" { facets.append(["categories:\(loaderFacet)"]) }

        let facetData = try JSONSerialization.data(withJSONObject: facets)
        let facetString = String(data: facetData, encoding: .utf8) ?? "[]"

        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "index", value: "relevance"),
            URLQueryItem(name: "facets", value: facetString)
        ]

        let data = try await get(components.url!)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = object["hits"] else { throw ModrinthClientError.invalidResponse }
        return try JSONDecoder().decode([ModrinthProject].self, from: JSONSerialization.data(withJSONObject: hits))
    }

    /// Downloads the newest compatible file of a project.
    func download(project: ModrinthProject, kind: String, gameVersion: String, loader: String, to destination: URL) async throws -> DownloadedModrinthFile {
        var components = URLComponents(url: root.appendingPathComponent("project/\(project.project_id)/version"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem]()

        if !Self.isBundleKind(kind), !gameVersion.isEmpty {
            query.append(URLQueryItem(name: "game_versions", value: try jsonString([gameVersion])))
            if kind == "Mods" {
                let loaderFacet = Self.loaderFacet(loader)
                if !loaderFacet.isEmpty { query.append(URLQueryItem(name: "loaders", value: try jsonString([loaderFacet]))) }
            }
        }
        components.queryItems = query.isEmpty ? nil : query

        let data = try await get(components.url!)
        guard let versions = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ModrinthClientError.invalidResponse
        }

        let ordered = versions.sorted {
            (($0["date_published"] as? String) ?? "") > (($1["date_published"] as? String) ?? "")
        }

        for version in ordered {
            guard let files = version["files"] as? [[String: Any]] else { continue }
            let chosen = files.first(where: { ($0["primary"] as? Bool) == true }) ?? files.first
            guard let chosen,
                  let fileName = chosen["filename"] as? String,
                  let rawURL = chosen["url"] as? String,
                  let remote = URL(string: rawURL) else { continue }

            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let target = destination.appendingPathComponent(URL(fileURLWithPath: fileName).lastPathComponent)

            var request = URLRequest(url: remote)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (temporary, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ModrinthClientError.invalidResponse
            }
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.moveItem(at: temporary, to: target)

            return DownloadedModrinthFile(url: target, version: version["version_number"] as? String ?? "")
        }
        throw ModrinthClientError.noCompatibleFile
    }

    /// Fetches a project's versions — used to resolve modpack dependencies.
    func projectVersions(_ projectID: String) async throws -> [[String: Any]] {
        var components = URLComponents(url: root.appendingPathComponent("project/\(projectID)/version"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "loaders", value: "[\"fabric\",\"forge\",\"neoforge\",\"quilt\"]")]
        let data = try await get(components.url!)
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    // MARK: - Private

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ModrinthClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw ModrinthClientError.http(http.statusCode) }
        return data
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func projectType(for kind: String) -> String {
        switch kind {
        case "Modpacks": return "modpack"
        case "Pacotes de recursos": return "resourcepack"
        case "Shaders": return "shader"
        default: return "mod"
        }
    }

    /// Kinds that are downloaded as a bundle rather than a single file.
    static func isBundleKind(_ kind: String) -> Bool {
        ["Modpacks", "Pacotes de recursos", "Shaders"].contains(kind)
    }

    static func loaderFacet(_ loader: String) -> String {
        switch loader.lowercased() {
        case "fabric": return "fabric"
        case "forge": return "forge"
        case "neoforge": return "neoforge"
        case "quilt": return "quilt"
        case "paper": return "paper"
        default: return ""
        }
    }
}
