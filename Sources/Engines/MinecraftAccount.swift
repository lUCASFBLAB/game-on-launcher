import Foundation
import CryptoKit

/// A signed-in Minecraft profile.
struct MinecraftAccountProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let accessToken: String
    /// Xbox user id, required by some launch arguments.
    let xuid: String?
    /// `msa` for Microsoft accounts, `legacy` for offline profiles.
    let userType: String

    init(id: String, name: String, accessToken: String, xuid: String? = nil, userType: String = "msa") {
        self.id = id
        self.name = name
        self.accessToken = accessToken
        self.xuid = xuid
        self.userType = userType
    }

    /// The UUID formatted the way Minecraft expects it (8-4-4-4-12).
    var dashedUUID: String {
        let hex = id.lowercased().replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return id }
        let start = hex.startIndex
        func slice(_ offset: Int, _ length: Int) -> String {
            String(hex[hex.index(start, offsetBy: offset)..<hex.index(start, offsetBy: offset + length)])
        }
        return [
            slice(0, 8),
            slice(8, 4),
            slice(12, 4),
            slice(16, 4),
            slice(20, 12)
        ].joined(separator: "-")
    }

    /// Builds a local offline profile.
    static func offline(name: String) -> MinecraftAccountProfile {
        // Offline mode uses a UUID derived from the player name.
        let digest = SHA256Digest.hash(name.lowercased())
        let hex = String(digest.prefix(32))
        return MinecraftAccountProfile(id: hex, name: name, accessToken: "0", xuid: nil, userType: "legacy")
    }
}

/// Small SHA-256 helper used to derive stable offline UUIDs.
enum SHA256Digest {
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Device-code flow response from Microsoft.
struct MicrosoftDeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int?
    let message: String?
}

/// Microsoft OAuth errors.
struct MicrosoftOAuthError: Decodable {
    let error: String?
    let error_description: String?
}

/// Handles the Microsoft device-code authentication flow.
actor MinecraftAccountService {
    static let shared = MinecraftAccountService()

    /// Public Minecraft Java launcher application ID used by compatible third-party launchers.
    static let clientID = "00000000-402b-4cd3-a82b-c45ab2f1d3f7"

    private let refreshTokenKey = "minecraftMicrosoftRefreshToken"

    // MARK: - Public API

    /// Starts the device-code flow and returns the code the user must confirm.
    func beginDeviceLogin() async throws -> MicrosoftDeviceCode {
        try await postForm(URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!, [
            "client_id": Self.clientID,
            "scope": "XboxLive.signin offline_access"
        ], decode: MicrosoftDeviceCode.self)
    }

    /// Polls the token endpoint until the user confirms the code.
    func login(using device: MicrosoftDeviceCode) async throws -> MinecraftAccountProfile {
        let deadline = Date().addingTimeInterval(TimeInterval(device.expires_in))
        let interval = max(5, device.interval ?? 5)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            var request = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": Self.clientID,
                "device_code": device.device_code
            ])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MinecraftAuthError.invalidResponse }

            if (200..<300).contains(http.statusCode) {
                let token = try JSONDecoder().decode(MicrosoftTokenResponse.self, from: data)
                try persistRefreshToken(token.refresh_token)
                return try await minecraftProfile(msaAccessToken: token.access_token)
            }

            let error = (try? JSONDecoder().decode(MicrosoftOAuthError.self, from: data))?.error ?? "http_\(http.statusCode)"
            switch error {
            case "authorization_pending": continue
            case "slow_down":
                try await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            case "authorization_declined": throw MinecraftAuthError.denied
            case "expired_token": throw MinecraftAuthError.expired
            default: throw MinecraftAuthError.oauth(error)
            }
        }
        throw MinecraftAuthError.expired
    }

    /// Restores a session using the stored refresh token.
    func refreshSavedLogin() async throws -> MinecraftAccountProfile {
        guard let refreshToken = LocalSecretStore.read(refreshTokenKey), !refreshToken.isEmpty else {
            throw MinecraftAuthError.noSavedLogin
        }
        let token = try await postForm(URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!, [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "XboxLive.signin offline_access"
        ], decode: MicrosoftTokenResponse.self)
        try persistRefreshToken(token.refresh_token)
        return try await minecraftProfile(msaAccessToken: token.access_token)
    }

    /// Removes the stored session.
    func signOut() {
        LocalSecretStore.delete(refreshTokenKey)
    }

    /// Whether a saved session exists.
    func hasSavedSession() -> Bool {
        guard let token = LocalSecretStore.read(refreshTokenKey) else { return false }
        return !token.isEmpty
    }

    // MARK: - Xbox / Minecraft exchange

    private func minecraftProfile(msaAccessToken: String) async throws -> MinecraftAccountProfile {
        let xbl = try await postJSON(URL(string: "https://user.auth.xboxlive.com/user/authenticate")!, headers: ["x-xbl-contract-version": "1"], body: [
            "Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(msaAccessToken)"],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ], decode: XboxTokenResponse.self)

        let xsts = try await postJSON(URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!, headers: ["x-xbl-contract-version": "1"], body: [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [xbl.Token]] as [String: Any],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT"
        ], decode: XboxTokenResponse.self)

        let claims = xsts.DisplayClaims?.xui.first
        guard let userHash = claims?.uhs, !userHash.isEmpty else { throw MinecraftAuthError.invalidXboxAccount }

        let minecraft = try await postJSON(URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!, headers: [:], body: [
            "identityToken": "XBL3.0 x=\(userHash);\(xsts.Token)"
        ], decode: MinecraftTokenResponse.self)

        try await checkOwnership(token: minecraft.access_token)

        var profileRequest = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile")!)
        profileRequest.setValue("Bearer \(minecraft.access_token)", forHTTPHeaderField: "Authorization")
        let profile: MinecraftProfileResponse = try await get(profileRequest, decode: MinecraftProfileResponse.self)

        return MinecraftAccountProfile(
            id: profile.id,
            name: profile.name,
            accessToken: minecraft.access_token,
            xuid: claims?.xid,
            userType: "msa"
        )
    }

    /// Confirms the account owns a Minecraft Java licence.
    private func checkOwnership(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/entitlements/mcstore")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let _: EntitlementsResponse = try await get(request, decode: EntitlementsResponse.self)
    }

    // MARK: - HTTP helpers

    private func postForm<T: Decodable>(_ url: URL, _ values: [String: String], decode type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(values)
        return try await get(request, decode: type)
    }

    private func postJSON<T: Decodable>(_ url: URL, headers: [String: String], body: [String: Any], decode type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await get(request, decode: type)
    }

    private func get<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MinecraftAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["errorMessage"] as? String
                ?? String(data: data, encoding: .utf8)?.prefix(180).description ?? ""
            throw MinecraftAuthError.service(http.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MinecraftAuthError.invalidResponse
        }
    }

    private func formBody(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private func persistRefreshToken(_ token: String) throws {
        guard !token.isEmpty else { throw MinecraftAuthError.invalidResponse }
        try LocalSecretStore.write(token, account: refreshTokenKey)
    }
}

// MARK: - Response models

private struct MicrosoftTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
}

private struct XboxTokenResponse: Decodable {
    let Token: String
    let DisplayClaims: Claims?

    struct Claims: Decodable {
        let xui: [UserClaim]
    }

    struct UserClaim: Decodable {
        let uhs: String?
        let xid: String?
    }
}

private struct MinecraftTokenResponse: Decodable {
    let access_token: String
}

private struct MinecraftProfileResponse: Decodable {
    let id: String
    let name: String
}

private struct EntitlementsResponse: Decodable {
    let items: [[String: String]]?
}

// MARK: - Errors

enum MinecraftAuthError: LocalizedError {
    case invalidResponse
    case noSavedLogin
    case denied
    case expired
    case invalidXboxAccount
    case oauth(String)
    case service(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "A resposta da autenticação Microsoft/Minecraft não foi válida."
        case .noSavedLogin: return "Inicia sessão com a tua conta Microsoft primeiro."
        case .denied: return "O início de sessão foi recusado."
        case .expired: return "O código de início de sessão expirou. Tenta novamente."
        case .invalidXboxAccount: return "Esta conta Microsoft não tem um perfil Xbox compatível."
        case .oauth(let code): return "A Microsoft não concluiu o início de sessão (\(code))."
        case .service(let status, let detail): return "O serviço de conta respondeu HTTP \(status): \(detail)"
        }
    }
}
