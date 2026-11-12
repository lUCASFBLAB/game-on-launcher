import SwiftUI
import UniformTypeIdentifiers

/// Hub for mods, modpacks, shaders and worlds.
@MainActor
struct ContentHubView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var search = ""
    @State private var version = "1.21.8"
    @State private var loader = "Fabric"

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PageHeader(
                eyebrow: "Conteúdo",
                title: "Biblioteca da instância",
                subtitle: model.selectedInstance?.name ?? "Seleciona uma instância",
                accent: accent
            ) {
                HStack(spacing: Theme.Space.s) {
                    GhostButton(title: "Abrir pasta", systemImage: "folder", tint: accent) {
                        model.openInstanceFolder()
                    }
                    GhostButton(title: "Mods", systemImage: "shippingbox.fill", tint: accent) {
                        model.contentTab = .mods
                    }
                }
            }

            tabBar

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    switch model.contentTab {
                    case .mods: installedMods
                    case .curseForge: curseForgeBrowser
                    case .modrinth: modrinthBrowser
                    case .modpacks: modpacksBrowser
                    case .worlds: worldsBrowser
                    case .servers: serversBrowser
                    case .screenshots: screenshotsBrowser
                    default: resourceBrowser
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Theme.Space.l)
            }
        }
        .padding(Theme.gutter)
        .onAppear {
            if version.isEmpty { version = preferences.defaultMinecraftVersion }
            loader = preferences.defaultLoader
            model.refreshInstanceMods()
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ContentTab.allCases) { tab in
                    Button {
                        model.contentTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.systemImage).font(.system(size: 10.5, weight: .bold))
                            Text(tab.rawValue).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(model.contentTab == tab ? .white : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if model.contentTab == tab {
                                Capsule().fill(
                                    LinearGradient(colors: [accent, secondary], startPoint: .leading, endPoint: .trailing)
                                )
                                .shadow(color: accent.opacity(0.35), radius: 8, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Installed mods

    private var installedMods: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Mods instalados",
                    subtitle: "\(model.installedModFiles.filter { !$0.hasSuffix(".disabled") }.count) ativos · \(model.installedModFiles.count) ficheiros",
                    systemImage: "shippingbox.fill",
                    accent: accent
                ) {
                    GhostButton(title: "Atualizar", systemImage: "arrow.clockwise", tint: accent, compact: true) {
                        model.refreshInstanceMods()
                    }
                    GhostButton(title: "Pasta mods", systemImage: "folder", tint: accent, compact: true) {
                        model.openModsFolder()
                    }
                }

                SearchField(prompt: "Pesquisar mods…", text: $search, accent: accent)

                if model.installedModFiles.isEmpty {
                    EmptyStateView(
                        systemImage: "shippingbox",
                        title: "Nenhum mod instalado",
                        message: "Usa CurseForge ou Modrinth para instalar mods nesta instância.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 5) {
                        ForEach(filteredMods, id: \.self) { file in
                            modRow(file)
                        }
                    }
                }
            }
        }
    }

    private var filteredMods: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.installedModFiles }
        return model.installedModFiles.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func modRow(_ file: String) -> some View {
        let disabled = file.hasSuffix(".disabled")
        let displayName = file.replacingOccurrences(of: ".disabled", with: "")
        return HStack(spacing: Theme.Space.s) {
            Toggle("", isOn: Binding(
                get: { !disabled },
                set: { model.toggleMod(file, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(accent)

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12))
                .foregroundStyle(disabled ? Theme.textTertiary : accent)
                .frame(width: 24)

            Text(displayName)
                .font(.system(size: 12.5))
                .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            GlassChip(
                text: disabled ? "Desativado" : "Ativo",
                systemImage: disabled ? "pause.circle.fill" : "play.circle.fill",
                tint: disabled ? Theme.textTertiary : Theme.success,
                filled: !disabled
            )

            IconButton(systemImage: "trash", tint: Theme.danger, size: 26) {
                model.deleteMod(file)
            }
            .help("Apagar mod")
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
    }

    // MARK: - CurseForge

    private var curseForgeBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "CurseForge",
                    subtitle: "Mods e modpacks da catálogo CurseForge",
                    systemImage: "flame.fill",
                    accent: accent
                ) {
                    GlassChip(
                        text: model.curseForgeVersions.isEmpty ? "Sem versões" : "\(model.curseForgeVersions.count) versões",
                        systemImage: "number",
                        tint: accent
                    )
                }

                HStack(spacing: Theme.Space.s) {
                    SearchField(prompt: "Pesquisar mods ou modpacks…", text: $search, accent: accent)
                    NeonButton(title: "Pesquisar", systemImage: "magnifyingglass", accent: accent, secondary: secondary, prominent: false, compact: true) {
                        Task { await model.searchCurseForge(query: search, kind: .mods, version: version, loader: loader) }
                    }
                    .disabled(model.curseForgeBusy)
                }

                filters

                StatusBanner(kind: LocalSecretStore.read("curseforge") == nil ? .warning : .info, message: model.curseForgeStatus, accent: accent)

                if model.curseForgeBusy {
                    ProgressView("A consultar a API…").font(.system(size: 11.5))
                }

                if model.curseForgeResults.isEmpty {
                    EmptyStateView(
                        systemImage: "flame",
                        title: "Sem resultados",
                        message: "A API CurseForge exige uma chave autorizada, guardada em Configurações → CurseForge.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.curseForgeResults) { project in
                            projectRow(
                                title: project.name,
                                subtitle: project.summary ?? "Projeto CurseForge",
                                downloads: Int(project.downloadCount),
                                icon: "shippingbox.fill",
                                actionTitle: "Baixar",
                                action: {
                                    Task {
                                        await model.downloadCurseForge(project, kind: .mods, version: version, loader: loader)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Modrinth

    private var modrinthBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Modrinth",
                    subtitle: "Catálogo aberto · downloads diretos sem chave de API",
                    systemImage: "cube.transparent.fill",
                    accent: accent
                ) {
                    if model.modrinthBusy { ProgressView().controlSize(.small) }
                }

                HStack(spacing: Theme.Space.s) {
                    SearchField(prompt: "Pesquisar no Modrinth…", text: $search, accent: accent)
                    NeonButton(title: "Pesquisar", systemImage: "magnifyingglass", accent: accent, secondary: secondary, prominent: false, compact: true) {
                        Task { await model.searchModrinth(query: search, kind: .mods, version: version, loader: loader) }
                    }
                    .disabled(model.modrinthBusy)
                }

                filters

                StatusBanner(kind: .info, message: model.modrinthStatus, accent: accent)

                if model.modrinthResults.isEmpty {
                    EmptyStateView(
                        systemImage: "cube.transparent",
                        title: "Pesquisa o Modrinth",
                        message: "Encontra mods, modpacks, shaders e pacotes de recursos.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.modrinthResults) { project in
                            projectRow(
                                title: project.title,
                                subtitle: project.description,
                                downloads: project.downloads,
                                icon: "shippingbox.fill",
                                actionTitle: "Baixar",
                                action: {
                                    Task { await model.downloadModrinth(project, kind: .mods, version: version, loader: loader) }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Modpacks

    private var modpacksBrowser: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            GlassPanel(accent: accent) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(
                        title: "Modpacks",
                        subtitle: "Instala um pack completo com as suas dependências",
                        systemImage: "square.stack.3d.up.fill",
                        accent: accent
                    )

                    HStack(spacing: Theme.Space.s) {
                        SearchField(prompt: "Pesquisar modpacks…", text: $search, accent: accent)
                        NeonButton(title: "Pesquisar", systemImage: "magnifyingglass", accent: accent, secondary: secondary, prominent: false, compact: true) {
                            Task { await model.searchModrinth(query: search, kind: .modpacks, version: version, loader: loader) }
                        }
                        .disabled(model.modrinthBusy)
                    }

                    filters

                    if model.modrinthResults.isEmpty {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: "Nenhum modpack encontrado",
                            message: "Pesquisa no Modrinth para instalar packs completos.",
                            accent: accent
                        )
                    } else {
                        VStack(spacing: 6) {
                            ForEach(model.modrinthResults) { project in
                                projectRow(
                                    title: project.title,
                                    subtitle: project.description,
                                    downloads: project.downloads,
                                    icon: "square.stack.3d.up.fill",
                                    actionTitle: "Importar",
                                    action: {
                                        Task { await model.downloadModrinth(project, kind: .modpacks, version: version, loader: loader) }
                                    }
                                )
                            }
                        }
                    }
                }
            }

            GlassPanel(accent: accent) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Importar ficheiro .mrpack", systemImage: "arrow.down.doc.fill", accent: accent)
                    Text("Arrasta um ficheiro .mrpack para a janela ou usa o seletor. O pack é extraído e os mods são descarregados para a instância.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    GhostButton(title: "Selecionar .mrpack…", systemImage: "folder", tint: accent) {
                        importModpack()
                    }
                }
            }
        }
    }

    // MARK: - Worlds / servers / screenshots

    private var worldsBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Mundos", subtitle: "Mundos guardados na pasta saves/", systemImage: "globe.americas.fill", accent: accent)
                worldList(folder: "saves")
            }
        }
    }

    private var screenshotsBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Capturas de ecrã", subtitle: "Imagens guardadas pelo jogo", systemImage: "photo.fill", accent: accent)
                worldList(folder: "screenshots")
            }
        }
    }

    private var serversBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Servidores", subtitle: "Lista de servidores associada à instância", systemImage: "server.rack", accent: accent)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("A lista de servidores fica em servers.json dentro da pasta da instância.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    GhostButton(title: "Abrir pasta servers", systemImage: "folder", tint: accent) {
                        if let instance = model.selectedInstance {
                            NSWorkspace.shared.open(InstanceStore.folder("servers", for: instance))
                        }
                    }
                    GhostButton(title: "Centro de servidor", systemImage: "gearshape", tint: accent) {
                        model.select(.server)
                    }
                }
            }
        }
    }

    /// Lists the contents of a folder inside the selected instance.
    private func worldList(folder: String) -> some View {
        Group {
            if let instance = model.selectedInstance {
                let target = InstanceStore.folder(folder, for: instance)
                let items = (try? FileManager.default.contentsOfDirectory(at: target, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                if items.isEmpty {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "Pasta vazia",
                        message: "Não há ficheiros em \(folder)/.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 5) {
                        ForEach(items, id: \.path) { url in
                            HStack(spacing: Theme.Space.s) {
                                Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accent)
                                    .frame(width: 22)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                IconButton(systemImage: "arrow.up.right.square", tint: accent, size: 26) {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, 6)
                            .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.035)) }
                        }
                    }
                }
            } else {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "Sem instância", message: "Seleciona uma instância para ver o conteúdo.", accent: accent)
            }
        }
    }

    // MARK: - Resource browser (shaders / resource packs)

    private var resourceBrowser: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: model.contentTab == .shaders ? "Shaders" : "Pacotes de recursos",
                    subtitle: "Disponíveis no Modrinth",
                    systemImage: model.contentTab == .shaders ? "sparkles" : "paintpalette.fill",
                    accent: accent
                )

                HStack(spacing: Theme.Space.s) {
                    SearchField(prompt: "Pesquisar…", text: $search, accent: accent)
                    NeonButton(title: "Pesquisar", systemImage: "magnifyingglass", accent: accent, secondary: secondary, prominent: false, compact: true) {
                        Task {
                            let kind = model.contentTab == .shaders ? ContentTab.shaders : ContentTab.resourcepacks
                            await model.searchModrinth(query: search, kind: kind, version: version, loader: loader)
                        }
                    }
                }

                if model.modrinthResults.isEmpty {
                    EmptyStateView(systemImage: "sparkles", title: "Pesquisa o catálogo", message: "Encontra shaders e pacotes de recursos para a tua instância.", accent: accent)
                } else {
                    VStack(spacing: 6) {
                        ForEach(model.modrinthResults) { project in
                            projectRow(
                                title: project.title,
                                subtitle: project.description,
                                downloads: project.downloads,
                                icon: model.contentTab == .shaders ? "sparkles" : "paintpalette.fill",
                                actionTitle: "Transferir",
                                action: {
                                    Task {
                                        let kind = model.contentTab == .shaders ? ContentTab.shaders : ContentTab.resourcepacks
                                        await model.downloadModrinth(project, kind: kind, version: version, loader: loader)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared pieces

    private var filters: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "number").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                TextField("Versão", text: $version)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 90)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.05)) }

            Picker("Loader", selection: $loader) {
                ForEach(["Qualquer", "Fabric", "Forge", "NeoForge", "Quilt"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 140)

            Spacer()
        }
    }

    private func projectRow(
        title: String,
        subtitle: String,
        downloads: Int,
        icon: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay { Image(systemName: icon).foregroundStyle(accent) }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                Text("\(downloads.formatted()) downloads")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: Theme.Space.s)

            GhostButton(title: actionTitle, systemImage: "arrow.down.circle", tint: accent, compact: true, action: action)
        }
        .padding(Theme.Space.s)
        .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.035)) }
    }

    /// Opens a file picker for `.mrpack` archives.
    private func importModpack() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "mrpack") ?? .data]
        panel.prompt = "Importar modpack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let instance = try await ModpackImporter.install(packURL: url)
                model.instances.reload()
                model.selectInstance(instance)
                model.notify("Modpack «\(instance.name)» importado.", kind: .success)
            } catch {
                model.notify("Falha ao importar: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}
