import SwiftUI
import Combine
import AppKit
import AVFoundation
import CryptoKit

/// Central observable state for the launcher.
///
/// Everything that used to live in dozens of `@State` properties now lives here, so the
/// views stay declarative and the logic stays testable.
@MainActor
final class LauncherModel: ObservableObject {

    // MARK: - Banner

    struct Banner: Identifiable, Equatable {
        enum Kind: String {
            case info, success, warning, error

            var symbol: String {
                switch self {
                case .info: return "info.circle.fill"
                case .success: return "checkmark.circle.fill"
                case .warning: return "exclamationmark.triangle.fill"
                case .error: return "xmark.octagon.fill"
                }
            }
        }

        let id = UUID()
        var kind: Kind
        var message: String
    }

    // MARK: - Navigation

    @Published var page: AppPage = .home
    @Published var navigationOrder: [AppPage] = AppPage.allCases

    // MARK: - Feedback

    @Published var banner: Banner?
    @Published private(set) var connectionOK = true

    // MARK: - Stores

    let instances = InstanceStore()
    let logs = LogStore()
    let serverController = MinecraftServerController()
    let gameEngine = MinecraftGameEngine()
    let news = NewsStore()
    let skins = SkinStore()
    let music = MusicPlayer()

    // MARK: - Selection

    @Published private(set) var selectedInstanceID: String?
    @Published var contentTab: ContentTab = .mods

    // MARK: - Account

    enum AccountState: Equatable {
        case signedOut
        case awaitingCode(code: String, url: String)
        case authenticating
        case signedIn(MinecraftAccountProfile)
        case failed(String)
    }

    @Published private(set) var accountState: AccountState = .signedOut
    @Published private(set) var isOfflineProfile = false

    // MARK: - Content browsing

    @Published var modrinthResults: [ModrinthProject] = []
    @Published var modrinthStatus = "Pesquisa direta no Modrinth, sem API key."
    @Published var modrinthBusy = false
    @Published var curseForgeResults: [CurseForgeProject] = []
    @Published var curseForgeStatus = "Introduza e guarde uma API key CurseForge para pesquisar."
    @Published var curseForgeBusy = false
    @Published var curseForgeVersions: [String] = []
    @Published var installedModFiles: [String] = []

    // MARK: - Minecraft catalogue

    @Published var minecraftVersions: [MinecraftVersionEntry] = []
    @Published var loadingMinecraftVersions = false

    // MARK: - Launching

    @Published private(set) var launching = false

    private var preferences: Preferences?
    private var cancellables = Set<AnyCancellable>()
    private var deviceCode: MicrosoftDeviceCode?
    private var bannerTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        // Forward child-store changes so views observing the model refresh correctly.
        instances.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        logs.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        serverController.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        gameEngine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        news.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        skins.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        music.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func bind(preferences: Preferences) {
        self.preferences = preferences
        navigationOrder = preferences.navigationOrder
        // Restore the page that was open when the app was last closed.
        if let restored = AppPage(rawValue: preferences.lastPage) {
            page = restored
        }
        instances.reload()
        restoreSelectedInstance()
        refreshInstanceMods()
        music.restore(path: preferences.musicPath)

        // Look for a newer build in the background.
        if preferences.checkUpdatesOnStart {
            Task { [weak self] in
                guard let info = try? await UpdateService.check() else { return }
                await MainActor.run {
                    self?.notify("Nova versão disponível: \(info.displayVersion). Vai a Configurações → Atualizações para instalar.", kind: .info)
                }
            }
        }
    }

    // MARK: - Notifications

    func notify(_ message: String, kind: Banner.Kind = .info) {
        bannerTask?.cancel()
        banner = Banner(kind: kind, message: message)
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismissBanner() }
        }
    }

    func dismissBanner() {
        banner = nil
    }

    // MARK: - Navigation

    func select(_ page: AppPage) {
        self.page = page
        preferences?.lastPage = page.rawValue
        if page == .logs {
            logs.bind(to: selectedInstance?.directory)
        }
    }

    /// Persists the current navigation order.
    func persistNavigationOrder() {
        preferences?.storeNavigationOrder(navigationOrder)
    }

    // MARK: - Instances

    var selectedInstance: Instance? {
        guard let selectedInstanceID else { return instances.all.first }
        return instances.instance(named: selectedInstanceID) ?? instances.all.first
    }

    func selectInstance(_ instance: Instance) {
        selectedInstanceID = instance.name
        preferences?.selectedInstance = instance.name
        refreshInstanceMods()
        logs.bind(to: instance.directory)
    }

    private func restoreSelectedInstance() {
        guard let stored = preferences?.selectedInstance, instances.all.contains(where: { $0.name == stored }) else {
            selectedInstanceID = instances.all.first?.name
            return
        }
        selectedInstanceID = stored
    }

    /// Creates a launcher-managed instance.
    func createManagedInstance(name: String, version: String, loader: String, loaderVersion: String = "", source: String) {
        do {
            let instance = try instances.create(name: name, version: version, loader: loader, loaderVersion: loaderVersion, source: source)
            selectedInstanceID = instance.name
            refreshInstanceMods()
            notify("Instância «\(instance.name)» criada e pronta a jogar.", kind: .success)
        } catch {
            notify("Não foi possível criar a instância: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Deletes an instance after confirmation.
    func deleteInstance(_ instance: Instance) {
        do {
            try instances.delete(instance)
            if selectedInstanceID == instance.name {
                selectedInstanceID = instances.all.first?.name
            }
            refreshInstanceMods()
            notify("Instância «\(instance.name)» apagada.", kind: .success)
        } catch {
            notify(error.localizedDescription, kind: .error)
        }
    }

    /// Renames an instance.
    func renameInstance(_ instance: Instance, to name: String) {
        do {
            try instances.rename(instance, to: name)
            selectedInstanceID = name
            refreshInstanceMods()
            notify("Instância renomeada para «\(name)».", kind: .success)
        } catch {
            notify(error.localizedDescription, kind: .error)
        }
    }

    /// Opens the instance folder in Finder.
    func openInstanceFolder(_ instance: Instance? = nil) {
        guard let target = instance ?? selectedInstance else {
            notify("Nenhuma instância selecionada.", kind: .warning)
            return
        }
        FileHelper.ensureDirectory(target.directory)
        NSWorkspace.shared.open(target.directory)
    }

    // MARK: - Mods

    /// Reloads the list of mods installed in the selected instance.
    func refreshInstanceMods() {
        guard let instance = selectedInstance else {
            installedModFiles = []
            return
        }
        let folder = InstanceStore.modsFolder(for: instance)
        installedModFiles = FileHelper.files(in: folder)
            .filter { $0.pathExtension.lowercased() == "jar" || $0.lastPathComponent.hasSuffix(".jar.disabled") }
            .map(\.lastPathComponent)
            .sorted()
    }

    /// Enables or disables a mod by renaming its file.
    func toggleMod(_ file: String, enabled: Bool) {
        guard let instance = selectedInstance else { return }
        let folder = InstanceStore.modsFolder(for: instance)
        let source = folder.appendingPathComponent(file)
        let target = folder.appendingPathComponent(
            enabled
                ? file.replacingOccurrences(of: ".disabled", with: "")
                : (file.hasSuffix(".disabled") ? file : file + ".disabled")
        )
        do {
            FileHelper.remove(target)
            try FileManager.default.moveItem(at: source, to: target)
            refreshInstanceMods()
        } catch {
            notify("Não foi possível alterar o mod: \(error.localizedDescription)", kind: .error)
        }
    }

    /// Deletes a mod from the instance.
    func deleteMod(_ file: String) {
        guard let instance = selectedInstance else { return }
        let folder = InstanceStore.modsFolder(for: instance)
        FileHelper.remove(folder.appendingPathComponent(file))
        refreshInstanceMods()
        notify("Mod removido: \(file)", kind: .success)
    }

    /// Opens the mods folder in Finder.
    func openModsFolder() {
        guard let instance = selectedInstance else { return }
        let folder = InstanceStore.modsFolder(for: instance)
        FileHelper.ensureDirectory(folder)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Modrinth

    func searchModrinth(query: String, kind: ContentTab, version: String, loader: String) async {
        modrinthBusy = true
        modrinthStatus = "A pesquisar no Modrinth…"
        defer { modrinthBusy = false }
        do {
            modrinthResults = try await ModrinthClient.shared.search(query: query, kind: kind.modrinthKind, gameVersion: version, loader: loader)
            modrinthStatus = "\(modrinthResults.count) resultados · sem chave API"
        } catch {
            modrinthStatus = "Falha na pesquisa: \(error.localizedDescription)"
        }
    }

    func downloadModrinth(_ project: ModrinthProject, kind: ContentTab, version: String, loader: String) async {
        modrinthBusy = true
        modrinthStatus = "A preparar \(project.title)…"
        defer { modrinthBusy = false }
        do {
            let destination: URL
            if kind == .modpacks {
                destination = AppPaths.modrinthDownloads
            } else {
                guard let instance = selectedInstance else {
                    modrinthStatus = "Seleciona uma instância antes de transferir."
                    return
                }
                destination = InstanceStore.folder(kind.folderName, for: instance)
            }

            let file = try await ModrinthClient.shared.download(
                project: project,
                kind: kind.modrinthKind,
                gameVersion: version,
                loader: loader,
                to: destination
            )

            if kind == .modpacks {
                let instance = try await ModpackImporter.install(packURL: file.url)
                instances.reload()
                selectInstance(instance)
                modrinthStatus = "Modpack «\(instance.name)» importado e pronto para iniciar."
                notify("Modpack «\(instance.name)» importado.", kind: .success)
            } else {
                refreshInstanceMods()
                modrinthStatus = "Transferido: \(file.url.lastPathComponent) · versão \(file.version)"
                notify("«\(project.title)» transferido para \(kind.folderName)/.", kind: .success)
            }
        } catch {
            modrinthStatus = "Falha no download: \(error.localizedDescription)"
            notify("Falha no download: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - CurseForge

    func refreshCurseForgeVersions() async {
        guard let key = LocalSecretStore.read("curseforge"), !key.isEmpty else {
            curseForgeStatus = "Guarde uma API key em Configurações → CurseForge."
            return
        }
        do {
            curseForgeVersions = try await CurseForgeClient.shared.versions(apiKey: key)
            curseForgeStatus = "Ligação CurseForge OK · \(curseForgeVersions.count) versões disponíveis."
        } catch {
            curseForgeStatus = error.localizedDescription
        }
    }

    func searchCurseForge(query: String, kind: ContentTab, version: String, loader: String) async {
        guard let key = LocalSecretStore.read("curseforge"), !key.isEmpty else {
            curseForgeStatus = "Guarde uma API key em Configurações → CurseForge."
            return
        }
        curseForgeBusy = true
        curseForgeStatus = "A pesquisar na API CurseForge…"
        defer { curseForgeBusy = false }
        do {
            curseForgeResults = try await CurseForgeClient.shared.search(
                query,
                kind: kind.curseForgeKind,
                gameVersion: version,
                loader: loader,
                apiKey: key
            )
            curseForgeStatus = "\(curseForgeResults.count) resultados da API CurseForge."
        } catch {
            curseForgeStatus = error.localizedDescription
        }
    }

    func downloadCurseForge(_ project: CurseForgeProject, kind: ContentTab, version: String, loader: String) async {
        guard let key = LocalSecretStore.read("curseforge"), !key.isEmpty else {
            curseForgeStatus = "Guarde uma API key em Configurações → CurseForge."
            return
        }
        curseForgeBusy = true
        defer { curseForgeBusy = false }

        do {
            if kind == .modpacks {
                curseForgeStatus = "A instalar o modpack…"
                let pack = try await CurseForgeClient.shared.installModpack(
                    project: project,
                    to: AppPaths.instances,
                    downloadsDirectory: AppPaths.curseForgeDownloads,
                    apiKey: key
                )
                instances.reload()
                if let created = instances.instance(named: pack.name) { selectInstance(created) }
                curseForgeStatus = "Modpack «\(pack.name)» instalado."
                notify("Modpack «\(pack.name)» instalado.", kind: .success)
            } else if kind == .worlds {
                guard let instance = selectedInstance else {
                    curseForgeStatus = "Seleciona uma instância antes de instalar o mapa."
                    return
                }
                let archive = try await CurseForgeClient.shared.download(
                    project: project,
                    kind: kind.curseForgeKind,
                    gameVersion: version,
                    loader: loader,
                    to: AppPaths.curseForgeDownloads,
                    apiKey: key
                )
                try installWorldArchive(archive, named: project.name, in: instance)
                curseForgeStatus = "Mapa instalado em saves/: \(project.name)"
                notify("Mapa «\(project.name)» instalado.", kind: .success)
            } else {
                guard let instance = selectedInstance else {
                    curseForgeStatus = "Seleciona uma instância antes de transferir o mod."
                    return
                }
                let destination = InstanceStore.folder(kind.folderName, for: instance)
                let url = try await CurseForgeClient.shared.download(
                    project: project,
                    kind: kind.curseForgeKind,
                    gameVersion: version,
                    loader: loader,
                    to: destination,
                    apiKey: key
                )
                refreshInstanceMods()
                curseForgeStatus = "Transferido: \(url.lastPathComponent)"
                notify("«\(project.name)» transferido.", kind: .success)
            }
        } catch {
            curseForgeStatus = error.localizedDescription
            notify(error.localizedDescription, kind: .error)
        }
    }

    /// Extracts a world archive into the instance's `saves/` folder.
    func installWorldArchive(_ archive: URL, named worldName: String, in instance: Instance) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("GameOnWorld-\(UUID().uuidString)", isDirectory: true)
        defer { FileHelper.remove(staging) }
        try FileHelper.extractZip(archive, to: staging)

        let enumerator = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        guard let levelFile = (enumerator?.allObjects as? [URL])?.first(where: { $0.lastPathComponent == "level.dat" }) else {
            throw LauncherError.archiveFailure("O ZIP não contém level.dat de um mundo Minecraft.")
        }

        let saves = InstanceStore.folder("saves", for: instance)
        let folderName = FileHelper.safeFolderName(worldName, fallback: "Mapa importado")
        let target = FileHelper.uniqueDirectory(in: saves, named: folderName)
        try FileManager.default.copyItem(at: levelFile.deletingLastPathComponent(), to: target)
    }

    // MARK: - Minecraft catalogue

    func loadMinecraftVersionCatalog() async {
        loadingMinecraftVersions = true
        defer { loadingMinecraftVersions = false }
        do {
            let url = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
            var request = URLRequest(url: url)
            request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw LauncherError.operationFailed("Não foi possível obter as versões oficiais do Minecraft.")
            }
            struct Manifest: Decodable { let versions: [MinecraftVersionEntry] }
            let versions = try JSONDecoder().decode(Manifest.self, from: data).versions
            minecraftVersions = versions
            connectionOK = true
        } catch {
            connectionOK = false
            notify("Falha ao carregar versões: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: - Account

    /// Starts the Microsoft device-code flow.
    func beginMicrosoftLogin() async {
        accountState = .authenticating
        do {
            let code = try await MinecraftAccountService.shared.beginDeviceLogin()
            deviceCode = code
            accountState = .awaitingCode(code: code.user_code, url: code.verification_uri)
            NSWorkspace.shared.open(URL(string: code.verification_uri)!)
        } catch {
            accountState = .failed(error.localizedDescription)
            notify(error.localizedDescription, kind: .error)
        }
    }

    /// Polls Microsoft until the device code is confirmed.
    func completeMicrosoftLogin() async {
        guard let deviceCode else {
            accountState = .signedOut
            return
        }
        accountState = .authenticating
        do {
            let profile = try await MinecraftAccountService.shared.login(using: deviceCode)
            accountState = .signedIn(profile)
            isOfflineProfile = false
            notify("Sessão iniciada como \(profile.name).", kind: .success)
        } catch {
            accountState = .failed(error.localizedDescription)
            notify(error.localizedDescription, kind: .error)
        }
    }

    /// Restores a previously stored Microsoft session.
    func restoreMicrosoftSession() async {
        accountState = .authenticating
        do {
            let profile = try await MinecraftAccountService.shared.refreshSavedLogin()
            accountState = .signedIn(profile)
            isOfflineProfile = false
            notify("Sessão restaurada como \(profile.name).", kind: .success)
        } catch {
            accountState = .signedOut
            notify("Não foi possível restaurar a sessão: \(error.localizedDescription)", kind: .warning)
        }
    }

    /// Cancels a pending device-code login.
    func cancelLogin() {
        deviceCode = nil
        accountState = .signedOut
    }

    /// Signs out of Microsoft.
    func signOut() {
        Task { await MinecraftAccountService.shared.signOut() }
        accountState = .signedOut
        isOfflineProfile = false
        notify("Sessão terminada.", kind: .info)
    }

    /// Creates and selects an offline profile.
    func useOfflineProfile(name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleaned.isEmpty ? "Jogador" : cleaned
        accountState = .signedIn(MinecraftAccountProfile.offline(name: finalName))
        isOfflineProfile = true
        preferences?.nickname = finalName
        notify("Perfil offline ativo: \(finalName).", kind: .success)
    }

    /// The profile used when launching, falling back to an offline profile.
    var launchProfile: MinecraftAccountProfile {
        if case .signedIn(let profile) = accountState { return profile }
        let name = preferences?.nickname ?? "Jogador"
        return MinecraftAccountProfile.offline(name: name)
    }

    // MARK: - Launching

    /// Launches the selected instance with the configured engine.
    func launchSelectedInstance() async {
        guard !launching else { return }
        guard let instance = selectedInstance else {
            notify("Cria ou seleciona uma instância primeiro.", kind: .warning)
            return
        }
        launching = true
        defer { launching = false }

        let preferences = self.preferences

        guard !instance.minecraftVersion.isEmpty else {
            notify("«\(instance.name)» não tem versão do Minecraft definida. Abre a instância e escolhe uma versão.", kind: .warning)
            return
        }
        // A missing loader version is not a problem: the engine resolves the
        // newest compatible release and remembers it for the next launch.
        await gameEngine.launch(
            version: instance.minecraftVersion,
            gameDirectory: instance.directory,
            account: launchProfile,
            loader: instance.modLoader,
            loaderVersion: instance.loaderVersion.isEmpty ? nil : instance.loaderVersion,
            minMemoryMB: Int(preferences?.minMemory ?? 1024),
            maxMemoryMB: Int(preferences?.maxMemory ?? 4096),
            javaArguments: (preferences?.javaArgs ?? "").split(separator: " ").map(String.init)
        )

        // Surface any failure of the engine in the banner, so the user is never left guessing.
        if case .failed(let reason) = gameEngine.phase {
            notify(reason, kind: .error)
            return
        }

        // Remember the loader version that was resolved, so the next launch uses
        // exactly the same one.
        if let profile = gameEngine.lastProfile,
           profile.loader != .vanilla,
           !profile.version.isEmpty,
           profile.version != instance.loaderVersion {
            instances.updateLoaderVersion(profile.version, for: instance.id)
            notify("A usar \(profile.loader.displayName) \(profile.version).", kind: .info)
        }
    }

    /// Checks that everything needed to start the game is in place.
    func diagnoseLaunch(_ instance: Instance) -> [String] {
        var problems: [String] = []
        if instance.minecraftVersion.isEmpty {
            problems.append("A instância não tem versão do Minecraft definida.")
        }
        // The runtime must satisfy the version the game needs.
        let required = JavaLocator.requiredJavaVersion(for: instance.minecraftVersion)
        if JavaLocator.shared.locate(minimumMajor: required) == nil {
            problems.append("Não foi encontrado um Java \(required) ou superior. O Minecraft \(instance.minecraftVersion) precisa dele.")
        }
        if case .signedIn = accountState {
            // Signed in — nothing to report.
        } else if preferences?.nickname.isEmpty != false {
            problems.append("Não existe perfil configurado.")
        }
        return problems
    }
}

/// A version of Minecraft from the official manifest.
struct MinecraftVersionEntry: Decodable, Identifiable, Hashable {
    let id: String
    let type: String
    let url: String

    var versionID: String { id }
    var stable: Bool { type == "release" }

    var displayName: String {
        switch type {
        case "release": return "estável"
        case "snapshot": return "snapshot"
        case "old_beta": return "beta"
        case "old_alpha": return "alfa"
        case "old_alpha_beta": return "alfa"
        default: return type
        }
    }
}

/// The tabs of the content hub.
enum ContentTab: String, CaseIterable, Identifiable {
    case mods = "Mods"
    case curseForge = "CurseForge"
    case modrinth = "Modrinth"
    case modpacks = "Modpacks"
    case resourcepacks = "Recursos"
    case shaders = "Shaders"
    case worlds = "Mundos"
    case servers = "Servidores"
    case screenshots = "Capturas"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .mods: return "shippingbox.fill"
        case .curseForge: return "flame.fill"
        case .modrinth: return "cube.transparent.fill"
        case .modpacks: return "square.stack.3d.up.fill"
        case .resourcepacks: return "paintpalette.fill"
        case .shaders: return "sparkles"
        case .worlds: return "globe.americas.fill"
        case .servers: return "server.rack"
        case .screenshots: return "photo.fill"
        }
    }

    /// The kind string understood by the Modrinth API.
    var modrinthKind: String {
        switch self {
        case .modpacks: return "Modpacks"
        case .resourcepacks: return "Pacotes de recursos"
        case .shaders: return "Shaders"
        default: return "Mods"
        }
    }

    /// The kind string understood by the CurseForge API.
    var curseForgeKind: String {
        switch self {
        case .modpacks: return "Modpacks"
        case .worlds: return "Mapas"
        default: return "Mods"
        }
    }

    /// The instance subfolder this tab writes into.
    var folderName: String {
        switch self {
        case .resourcepacks: return "resourcepacks"
        case .shaders: return "shaderpacks"
        case .worlds: return "saves"
        case .screenshots: return "screenshots"
        default: return "mods"
        }
    }
}
