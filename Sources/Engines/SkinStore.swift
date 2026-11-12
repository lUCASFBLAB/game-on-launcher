import Foundation
import AppKit

/// A Minecraft skin.
struct SkinProfile: Identifiable, Hashable {
    let id: String
    let name: String
    /// URL of the 64×64 skin image.
    let imageURL: URL?
    /// Local file, when the skin was imported from a PNG.
    let localFile: URL?
    /// The slim ("Alex") model variant.
    let slim: Bool

    var displayName: String { name }
}

/// Fetches and stores Minecraft skins.
@MainActor
final class SkinStore: ObservableObject {
    @Published private(set) var skin: SkinProfile?
    @Published private(set) var loading = false
    @Published private(set) var status = "Nenhuma skin carregada."

    /// Folder where imported skins are kept.
    private var folder: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let result = base.appendingPathComponent("GameOnLauncher/Skins", isDirectory: true)
        FileHelper.ensureDirectory(result)
        return result
    }

    /// Looks up the skin of a player by nickname.
    ///
    /// Uses the official Mojang profile and session services.
    func fetch(byNickname nickname: String) async {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            status = "Escreve um nickname."
            return
        }
        loading = true
        status = "A procurar \(name)…"
        defer { loading = false }

        do {
            let encoded = name.replacingOccurrences(of: " ", with: "%20")
            let profile = try await fetchJSON("https://api.mojang.com/users/profiles/minecraft/\(encoded)")
            guard let id = profile["id"] as? String else {
                status = "Esse nickname não tem perfil Minecraft."
                return
            }

            // The session service exposes the current skin and model variant.
            let session = try await fetchJSON("https://sessionserver.mojang.com/session/minecraft/profile/\(id)")
            let skins = session["skins"] as? [[String: Any]] ?? []
            let slim = skins.contains { ($0["variant"] as? String) == "slim" }
            let imageURL = (skins.first?["url"] as? String).flatMap(URL.init(string:))

            skin = SkinProfile(id: id, name: name, imageURL: imageURL, localFile: nil, slim: slim)
            status = "Skin de \(name) carregada."
        } catch {
            status = "Não foi possível obter a skin de \(name): \(error.localizedDescription)"
        }
    }

    /// Imports a local PNG skin.
    func importPNG(_ url: URL) {
        loading = true
        defer { loading = false }

        guard let image = NSImage(contentsOf: url) else {
            status = "O macOS não conseguiu ler esta imagem."
            return
        }
        let size = image.size
        guard size.width >= 16, size.height >= 16 else {
            status = "Uma skin tem de ser um PNG de pelo menos 64×64."
            return
        }

        let destination = folder.appendingPathComponent("skin-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            skin = SkinProfile(id: destination.lastPathComponent, name: "Skin importada", imageURL: nil, localFile: destination, slim: false)
            status = "Skin importada."
        } catch {
            status = "Não foi possível importar a skin: \(error.localizedDescription)"
        }
    }

    /// Uploads the current skin to the signed-in Microsoft account.
    ///
    /// The Minecraft profile service accepts a raw PNG as a multipart request.
    func uploadToAccount(accessToken: String) async -> Bool {
        guard let localFile = skin?.localFile else {
            status = "Importa uma skin em PNG para a poder enviar para a conta."
            return false
        }
        do {
            let data = try Data(contentsOf: localFile)
            let boundary = "GameOnLauncher-\(UUID().uuidString)"

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile/skins")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "O serviço de skins respondeu de forma inesperada."
                return false
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["errorMessage"] as? String
                status = "Não foi possível enviar a skin: \(message ?? "HTTP \(http.statusCode)")"
                return false
            }
            status = "Skin enviada para a tua conta."
            return true
        } catch {
            status = "Não foi possível enviar a skin: \(error.localizedDescription)"
            return false
        }
    }

    /// Removes the stored skin.
    func clear() {
        if let localFile = skin?.localFile {
            FileHelper.remove(localFile)
        }
        skin = nil
        status = "Skin removida."
    }

    // MARK: - Helpers

    private func fetchJSON(_ urlString: String) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw LauncherError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LauncherError.operationFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
