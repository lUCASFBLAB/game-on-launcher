import Foundation

/// A single item in the "Novidades" feed.
struct NewsItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case release, snapshot, mod, tip

        var accent: String { "kind" }
    }

    let id: String
    let title: String
    let summary: String
    let date: Date
    let imageURL: URL?
    let kind: Kind
    let version: String
}

/// Fetches real news: official Mojang patch notes and popular Modrinth mods.
@MainActor
final class NewsStore: ObservableObject {
    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    private var loaded = false

    /// Loads the feed once per session.
    func load(force: Bool = false) async {
        guard !loading, force || !loaded else { return }
        loading = true
        error = nil
        defer { loading = false }

        async let notes = fetchPatchNotes()
        async let mods = fetchPopularMods()

        var collected: [NewsItem] = []
        collected.append(contentsOf: (try? await notes) ?? [])
        collected.append(contentsOf: (try? await mods) ?? [])
        collected.sort { $0.date > $1.date }

        items = Array(collected.prefix(12))
        loaded = true
        if items.isEmpty {
            error = "Não foi possível carregar as novidades."
        }
    }

    // MARK: - Mojang patch notes

    private func fetchPatchNotes() async throws -> [NewsItem] {
        let url = URL(string: "https://launchercontent.mojang.com/v2/javaPatchNotes.json")!
        var request = URLRequest(url: url)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LauncherError.invalidResponse
        }

        struct Response: Decodable {
            struct Entry: Decodable {
                struct Image: Decodable { let title: String; let url: String }
                let title: String
                let version: String
                let type: String
                let image: Image?
                let id: String
                let date: String
                let shortText: String?
            }
            let entries: [Entry]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // Prefer official releases, then snapshots, newest first.
        let releases = decoded.entries.filter { $0.type == "release" }.prefix(3)
        let snapshots = decoded.entries.filter { $0.type == "snapshot" }.prefix(2)
        let selected = Array(releases) + Array(snapshots)

        return selected.map { entry in
            let imageURL = entry.image.flatMap { URL(string: "https://launchercontent.mojang.com" + $0.url) }
            return NewsItem(
                id: "mojang-\(entry.id)",
                title: entry.title,
                summary: entry.shortText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Novidades oficiais do Minecraft Java Edition.",
                date: ISO8601DateFormatter().date(from: entry.date) ?? Date(),
                imageURL: imageURL,
                kind: entry.type == "release" ? .release : .snapshot,
                version: entry.version
            )
        }
    }

    // MARK: - Modrinth highlights

    private func fetchPopularMods() async throws -> [NewsItem] {
        var components = URLComponents(string: "https://api.modrinth.com/v2/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: ""),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "index", value: "downloads"),
            URLQueryItem(name: "facets", value: "[[\"project_type:mod\"],[\"categories:fabric\"]]")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LauncherError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else {
            throw LauncherError.invalidResponse
        }

        return hits.compactMap { hit in
            guard let id = hit["project_id"] as? String,
                  let title = hit["title"] as? String else { return nil }
            let description = hit["description"] as? String ?? "Mod em destaque na comunidade."
            let downloads = hit["downloads"] as? Int ?? 0
            let modified = hit["modified"] as? String
            let date = modified.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
            let icon = hit["icon_url"] as? String

            return NewsItem(
                id: "modrinth-\(id)",
                title: title,
                summary: "\(description) · \(downloads.formatted()) downloads",
                date: date,
                imageURL: icon.flatMap(URL.init(string:)),
                kind: .mod,
                version: id
            )
        }
    }
}
