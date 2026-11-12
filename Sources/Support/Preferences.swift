import Foundation
import SwiftUI
import Combine

/// Typed, observable wrapper over `UserDefaults`.
///
/// Every switch in Settings binds to one of these properties, so preferences actually
/// persist and restore instead of being hard-coded constants.
@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `@AppStorage` does not publish changes on its own when used outside a
        // `DynamicProperty`, so forward `UserDefaults` notifications manually to keep
        // every bound view in sync.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .filter { ($0.object as? UserDefaults) == defaults }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Appearance

    @AppStorage("gameOnLauncherDarkMode") var darkMode = true
    @AppStorage("gameOnLauncherAccent") var accentID = "plasma"
    @AppStorage("gameOnLauncherPanelOpacity") var panelOpacity = 0.78
    @AppStorage("gameOnLauncherPanelRadius") var panelRadius = Theme.panelRadius
    @AppStorage("gameOnLauncherBlurRadius") var blurRadius = 18.0
    @AppStorage("gameOnLauncherNavigationOnRight") var navigationOnRight = false
    @AppStorage("gameOnLauncherNavigationCollapsed") var navigationCollapsed = false
    @AppStorage("gameOnLauncherNavigationOrder") var navigationOrderJSON = ""
    @AppStorage("gameOnLauncherSeasonTheme") var seasonalTheme = "Automático"
    @AppStorage("gameOnLauncherSeasonEffects") var seasonalEffects = true
    @AppStorage("gameOnLauncherBackgroundImagePath") var backgroundImagePath = ""
    /// Path of the background music track.
    @AppStorage("gameOnLauncherMusicPath") var musicPath = ""
    @AppStorage("gameOnLauncherMusicVolume") var musicVolume = 0.4
    @AppStorage("gameOnLauncherMusicEnabled") var musicEnabled = true
    @AppStorage("gameOnLauncherBackgroundVideoPath") var backgroundVideoPath = ""
    @AppStorage("gameOnLauncherBackgroundVideoEnabled") var backgroundVideoEnabled = true
    @AppStorage("gameOnLauncherBackgroundImageOpacity") var backgroundImageOpacity = 0.24
    @AppStorage("gameOnLauncherGridEnabled") var gridEnabled = true
    @AppStorage("gameOnLauncherParticlesEnabled") var particlesEnabled = true
    @AppStorage("gameOnLauncherAnimationsEnabled") var animationsEnabled = true

    // MARK: - Gameplay

    @AppStorage("gameOnLauncherMinMemory") var minMemory = 1024.0
    @AppStorage("gameOnLauncherMaxMemory") var maxMemory = 4096.0
    @AppStorage("gameOnLauncherJavaArgs") var javaArgs = "-Djava.net.preferIPv4Stack=true"
    @AppStorage("gameOnLauncherGameDirectory") var gameDirectory = ""
    @AppStorage("gameOnLauncherNickname") var nickname = "Jogador"
    @AppStorage("gameOnLauncherAutoCloseOnLaunch") var autoCloseOnLaunch = false
    @AppStorage("gameOnLauncherKeepLauncherOpen") var keepLauncherOpen = true
    @AppStorage("gameOnLauncherWarnLowMemory") var warnLowMemory = true
    @AppStorage("gameOnLauncherInstanceSort") var instanceSort = "Por nome"
    @AppStorage("gameOnLauncherInstanceRenamePolicy") var instanceRenamePolicy = "Perguntar o que fazer"
    @AppStorage("gameOnLauncherJavaPath") var javaPath = ""
    @AppStorage("gameOnLauncherServerMemory") var serverMemory = 4
    @AppStorage("gameOnLauncherSelectedInstance") var selectedInstance = ""
    /// The page that was open when the launcher was last closed.
    @AppStorage("gameOnLauncherLastPage") var lastPage = "Jogar"

    // MARK: - Content

    @AppStorage("gameOnLauncherModrinthLoader") var defaultLoader = "Fabric"
    @AppStorage("gameOnLauncherDefaultMCVersion") var defaultMinecraftVersion = "1.21.8"
    @AppStorage("gameOnLauncherTrackModMetadata") var trackModMetadata = true
    @AppStorage("gameOnLauncherInstallModDependencies") var installModDependencies = true
    @AppStorage("gameOnLauncherDetectModConflicts") var detectModConflicts = false
    @AppStorage("gameOnLauncherVerifyModSubpaths") var verifyModSubpaths = false
    @AppStorage("gameOnLauncherMoveBlockedMods") var moveBlockedMods = false
    @AppStorage("gameOnLauncherSuggestInstanceUpdates") var suggestInstanceUpdates = true
    @AppStorage("gameOnLauncherUpdateModsOnInstall") var updateModsOnInstall = false

    // MARK: - Server

    @AppStorage("gameOnLauncherServerEULAAccepted") var serverEULAAccepted = false
    @AppStorage("gameOnLauncherServerName") var serverName = "Meu servidor"
    @AppStorage("gameOnLauncherServerSoftware") var serverSoftware = "Paper"
    @AppStorage("gameOnLauncherServerVersion") var serverVersion = "1.21.8"
    @AppStorage("gameOnLauncherServerAutoRestart") var serverAutoRestart = false
    @AppStorage("gameOnLauncherServerConsoleFontSize") var serverConsoleFontSize = 11.0

    // MARK: - Updates

    @AppStorage("gameOnLauncherCheckUpdatesOnStart") var checkUpdatesOnStart = true
    /// The settings tab that was open last time.
    @AppStorage("gameOnLauncherSettingsTab") var settingsTab = "Geral"

    /// Every settings tab, used to validate the stored value.
    let tabs = ["Geral", "Minecraft", "Java", "Contas", "Serviços", "CurseForge", "Pastas", "Atualizações", "Proxy", "Créditos"]
    @AppStorage("gameOnLauncherUpdateFrequency") var updateFrequency = "Todo o dia"

    // MARK: - Streamer

    @AppStorage("gameOnLauncherStreamerMode") var streamerMode = false
    @AppStorage("gameOnLauncherHideNickname") var hideNickname = true
    @AppStorage("gameOnLauncherHideInstance") var hideInstance = true
    @AppStorage("gameOnLauncherMuteNotifications") var muteNotifications = true
    @AppStorage("gameOnLauncherOverlayStatus") var overlayStatus = true
    @AppStorage("gameOnLauncherOverlayInstance") var overlayInstance = false
    @AppStorage("gameOnLauncherOverlayTimer") var overlayTimer = true
    @AppStorage("gameOnLauncherCompactOverlay") var compactOverlay = false
    @AppStorage("gameOnLauncherOverlayOpacity") var overlayOpacity = 0.85
    @AppStorage("gameOnLauncherOverlayAccent") var overlayAccent = true

    // MARK: - Folders

    @AppStorage("gameOnLauncherFolderInstances") var folderInstances = "instances"
    @AppStorage("gameOnLauncherFolderMods") var folderMods = "mods"
    @AppStorage("gameOnLauncherFolderIcons") var folderIcons = "icons"
    @AppStorage("gameOnLauncherFolderJava") var folderJava = "java"
    @AppStorage("gameOnLauncherFolderSkins") var folderSkins = "skins"
    @AppStorage("gameOnLauncherFolderDownloads") var folderDownloads = "~/Downloads"

    // MARK: - Derived values

    /// Accent colour resolved from the stored preset id.
    var accentColor: Color {
        Theme.accents.first { $0.id == accentID }?.primary ?? Theme.accents[0].primary
    }

    var accentSecondaryColor: Color {
        Theme.accents.first { $0.id == accentID }?.secondary ?? Theme.accents[0].secondary
    }

    /// Currently active seasonal theme name (resolved from "Automático" if needed).
    var resolvedSeason: String {
        if seasonalTheme != "Automático" { return seasonalTheme }
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12: return "Natal"
        case 10: return "Halloween"
        case 1: return "Ano Novo"
        case 3, 4: return "Páscoa"
        case 6, 7, 8: return "Verão"
        default: return "Noite neon"
        }
    }

    /// Ordered list of navigation destinations.
    var navigationOrder: [AppPage] {
        let valid = AppPage.allCases
        guard let data = navigationOrderJSON.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String].self, from: data) else { return valid }
        let filtered = stored.compactMap { AppPage(rawValue: $0) }
        let known = Set(filtered)
        return filtered + valid.filter { !known.contains($0) }
    }

    func storeNavigationOrder(_ order: [AppPage]) {
        guard let data = try? JSONEncoder().encode(order.map(\.rawValue)) else { return }
        navigationOrderJSON = String(data: data, encoding: .utf8) ?? ""
    }

    /// Resolved design tokens for the current preferences.
    var tokens: ThemeTokens {
        ThemeTokens.resolve(
            accentID: accentID,
            isDark: darkMode,
            seasonalID: resolvedSeason,
            seasonalEnabled: seasonalEffects
        )
    }
}

/// Every destination in the launcher sidebar.
enum AppPage: String, CaseIterable, Identifiable, Hashable {
    case home = "Jogar"
    case instances = "Instâncias"
    case content = "Conteúdo"
    case server = "Servidor"
    case logs = "Logs"
    case accounts = "Contas"
    case streamer = "Streamer"
    case appearance = "Aparência"
    case settings = "Configurações"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "play.fill"
        case .instances: return "square.stack.3d.up.fill"
        case .content: return "shippingbox.fill"
        case .server: return "server.rack"
        case .logs: return "doc.text.magnifyingglass"
        case .accounts: return "person.crop.circle.fill"
        case .streamer: return "video.fill"
        case .appearance: return "paintpalette.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .home: return "Escolhe uma instância e entra no jogo."
        case .instances: return "Versões, modpacks e perfis separados."
        case .content: return "Mods, modpacks, shaders e mundos."
        case .server: return "Servidores Paper, Fabric, Forge e NeoForge."
        case .logs: return "Registos e diagnóstico da instância."
        case .accounts: return "Perfis Microsoft e offline."
        case .streamer: return "Privacidade e overlay para lives."
        case .appearance: return "Temas, cores e plano de fundo."
        case .settings: return "Preferências do launcher."
        }
    }
}
