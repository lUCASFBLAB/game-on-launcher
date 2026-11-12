import SwiftUI

/// Library of every instance the launcher knows about.
@MainActor
struct InstancesView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var search = ""
    @State private var showNewInstance = false
    @State private var renamingInstance: Instance?
    @State private var renameText = ""
    @State private var pendingDelete: Instance?

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    private var filtered: [Instance] {
        let all = model.instances.all
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { instance in
            instance.name.localizedCaseInsensitiveContains(query)
                || instance.minecraftVersion.localizedCaseInsensitiveContains(query)
                || instance.loader.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PageHeader(
                    eyebrow: "Biblioteca",
                    title: "Instâncias",
                    subtitle: "Cada instância tem os seus mods, mundos e configurações.",
                    accent: accent
                ) {
                    NeonButton(title: "Nova instância", systemImage: "plus", accent: accent, secondary: secondary, prominent: false) {
                        showNewInstance = true
                    }
                }

                toolbar

                if filtered.isEmpty {
                    GlassPanel(accent: accent) {
                        EmptyStateView(
                            systemImage: "square.stack.3d.up",
                            title: model.instances.all.isEmpty ? "Sem instâncias" : "Nenhum resultado",
                            message: model.instances.all.isEmpty
                                ? "Cria uma instância para começar a jogar, ou importa um modpack."
                                : "Nenhuma instância corresponde à pesquisa.",
                            accent: accent,
                            actionTitle: model.instances.all.isEmpty ? "Criar instância" : nil,
                            action: model.instances.all.isEmpty ? { showNewInstance = true } : nil
                        )
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                        ForEach(filtered) { instance in
                            instanceCard(instance)
                        }
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showNewInstance) {
            NewInstanceSheet(model: model).environmentObject(preferences)
        }
        .alert("Renomear instância", isPresented: Binding(
            get: { renamingInstance != nil },
            set: { if !$0 { renamingInstance = nil } }
        )) {
            TextField("Novo nome", text: $renameText)
            Button("Cancelar", role: .cancel) { renamingInstance = nil }
            Button("Renomear") {
                if let instance = renamingInstance {
                    model.renameInstance(instance, to: renameText)
                }
                renamingInstance = nil
            }
        }
        .confirmationDialog(
            "Apagar «\(pendingDelete?.name ?? "")»?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar instância", role: .destructive) {
                if let instance = pendingDelete { model.deleteInstance(instance) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("A pasta da instância e o seu conteúdo são apagados definitivamente.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Theme.Space.s) {
            SearchField(prompt: "Pesquisar instâncias", text: $search, accent: accent)
                .frame(maxWidth: 280)

            GlassChip(text: "\(filtered.count) de \(model.instances.all.count)", systemImage: "square.stack.3d.up", tint: accent)

            Spacer()

            GhostButton(title: "Pastas", systemImage: "folder", tint: accent) {
                NSWorkspace.shared.open(AppPaths.instances)
            }
            GhostButton(title: "Atualizar", systemImage: "arrow.clockwise", tint: accent) {
                model.instances.reload()
                model.refreshInstanceMods()
            }
        }
    }

    // MARK: - Card

    private func instanceCard(_ instance: Instance) -> some View {
        let isSelected = model.selectedInstance?.name == instance.name
        return Button {
            model.selectInstance(instance)
            preferences.selectedInstance = instance.name
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent.opacity(0.28), secondary.opacity(0.16)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: instance.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 42, height: 42)

                    Spacer()

                    if isSelected {
                        GlassChip(text: "Selecionada", systemImage: "checkmark.circle.fill", tint: Theme.success, filled: true)
                    } else if !instance.loaderVersion.isEmpty {
                        GlassChip(text: instance.loaderVersion, systemImage: "cube.transparent")
                    }
                }

                Text(instance.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    GlassChip(text: instance.displayVersion, systemImage: "number")
                    GlassChip(text: instance.loaderLabel, systemImage: instance.icon)
                }

                Spacer(minLength: 0)

                Text(instance.source)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.06), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.7) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.6 : 1
                    )
            }
            .shadow(color: isSelected ? accent.opacity(0.25) : .clear, radius: 14, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Jogar") { model.selectInstance(instance); Task { await model.launchSelectedInstance() } }
            Button("Abrir pasta") { model.openInstanceFolder(instance) }
            Button("Renomear") {
                renameText = instance.name
                renamingInstance = instance
            }
            Button("Duplicar") { duplicate(instance) }
            Divider()
            Button("Apagar", role: .destructive) { pendingDelete = instance }
        }
    }

    /// Copies an instance folder into a new instance.
    private func duplicate(_ instance: Instance) {
        do {
            let target = FileHelper.uniqueDirectory(in: AppPaths.instances, named: "\(instance.name) cópia")
            try FileHelper.mergeDirectory(source: instance.directory, destination: target)
            model.instances.reload()
            model.notify("Instância duplicada.", kind: .success)
        } catch {
            model.notify("Não foi possível duplicar: \(error.localizedDescription)", kind: .error)
        }
    }
}

/// Sheet used to create a new instance.
@MainActor
struct NewInstanceSheet: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var version = ""
    @State private var loader = "Nenhum"
    @State private var search = ""
    @State private var stableOnly = true
    @State private var includeSnapshots = false
    @State private var includeBetas = false
    @State private var includeAlphas = false
    @State private var creating = false
    @State private var loaderVersions: [String] = []
    @State private var loaderVersion = ""
    @State private var loadingLoaderVersions = false

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    private var filteredVersions: [MinecraftVersionEntry] {
        model.minecraftVersions.filter { entry in
            let typeAllowed: Bool
            switch entry.type {
            case "release": typeAllowed = true
            case "snapshot": typeAllowed = !stableOnly || includeSnapshots
            case "old_beta": typeAllowed = !stableOnly || includeBetas
            case "old_alpha", "old_alpha_beta": typeAllowed = !stableOnly || includeAlphas
            default: typeAllowed = !stableOnly
            }
            return typeAllowed && (search.isEmpty || entry.id.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nova instância").font(.system(size: 20, weight: .bold))
                    Text("Catálogo oficial do Minecraft · releases, snapshots e versões antigas")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                IconButton(systemImage: "xmark", tint: Theme.textSecondary) { dismiss() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Nome")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                FormTextField(prompt: "Deixa vazio para usar o nome automático", text: $name, accent: accent)
            }

            HStack(spacing: Theme.Space.s) {
                SearchField(prompt: "Pesquisar versões (ex.: 1.20)", text: $search, accent: accent)
                IconButton(systemImage: "arrow.clockwise", tint: accent, size: 32) {
                    Task { await model.loadMinecraftVersionCatalog() }
                }
                .disabled(model.loadingMinecraftVersions)
                .help("Atualizar catálogo")
            }

            if model.loadingMinecraftVersions {
                ProgressView("A carregar versões oficiais…").font(.system(size: 11.5))
            }

            Picker("Versão do Minecraft · \(filteredVersions.count)", selection: $version) {
                ForEach(filteredVersions.prefix(300)) { entry in
                    Text("\(entry.id) · \(entry.displayName)").tag(entry.id)
                }
            }
            .labelsHidden()

            HStack(spacing: Theme.Space.m) {
                Toggle("Estáveis", isOn: $stableOnly).toggleStyle(.checkbox)
                Toggle("Snapshots", isOn: $includeSnapshots).toggleStyle(.checkbox)
                Toggle("Betas", isOn: $includeBetas).toggleStyle(.checkbox)
                Toggle("Alfas", isOn: $includeAlphas).toggleStyle(.checkbox)
            }
            .font(.system(size: 11.5))

            HStack {
                Text("Loader de mods").font(.system(size: 12.5, weight: .medium))
                Spacer()
                Picker("Loader", selection: $loader) {
                    ForEach(["Nenhum", "Fabric", "Quilt", "Forge", "NeoForge"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: loader) { _ in resolveLoaderVersions() }
            }

            if loader != "Nenhum" {
                HStack(spacing: Theme.Space.s) {
                    Text("Versão do loader").font(.system(size: 12, weight: .medium))
                    Spacer()
                    if loadingLoaderVersions {
                        ProgressView().controlSize(.small)
                    } else if loaderVersions.isEmpty {
                        Text("sem versões compatíveis")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.warning)
                    } else {
                        Picker("Versão", selection: $loaderVersion) {
                            ForEach(loaderVersions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                if loaderNeedsInstaller {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.warning)
                        Text("O \(loader) executa o seu instalador uma vez para preparar as bibliotecas. Precisa de Java 17 ou superior.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(Theme.Space.s)
                    .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Theme.warning.opacity(0.10)) }
                }
            }

            Divider()

            HStack {
                Text("A instância é criada em \(AppPaths.instances.path)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(.bordered)
                NeonButton(
                    title: creating ? "A criar…" : "Criar instância",
                    systemImage: "plus",
                    accent: accent,
                    secondary: secondary,
                    prominent: false,
                    busy: creating
                ) {
                    create()
                }
                .disabled(creating || version.isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 560)
        .onAppear {
            if model.minecraftVersions.isEmpty {
                Task { await model.loadMinecraftVersionCatalog() }
            }
            if version.isEmpty {
                version = preferences.defaultMinecraftVersion
            }
        }
        .onChange(of: filteredVersions) { _ in
            if !filteredVersions.contains(where: { $0.id == version }), let first = filteredVersions.first {
                version = first.id
            }
        }
    }

    /// Resolves the loader versions published for the selected Minecraft version.
    private func resolveLoaderVersions() {
        loaderVersions = []
        loaderVersion = ""
        guard loader != "Nenhum", !version.isEmpty else { return }
        loadingLoaderVersions = true
        Task {
            let modLoader = ModLoader(rawValue: loader.lowercased()) ?? .vanilla
            let resolved = (try? await ModLoader.versions(for: modLoader, gameVersion: version)) ?? []
            loaderVersions = resolved
            loaderVersion = resolved.first ?? ""
            loadingLoaderVersions = false
        }
    }

    /// Whether the selected loader has to run an installer.
    private var loaderNeedsInstaller: Bool {
        (ModLoader(rawValue: loader.lowercased()) ?? .vanilla).needsInstaller
    }

    private func create() {
        creating = true
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Minecraft \(version) · \(loader)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)
        model.createManagedInstance(
            name: finalName,
            version: version,
            loader: loader,
            loaderVersion: loaderVersion,
            source: "Personalizado"
        )
        creating = false
        dismiss()
    }
}
