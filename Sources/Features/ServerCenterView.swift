import SwiftUI

/// Create, run and manage a local Minecraft server.
@MainActor
struct ServerCenterView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var software = "Paper"
    @State private var version = "1.21.8"
    @State private var name = "Meu servidor"
    @State private var memory = 4
    @State private var acceptedEULA = false
    @State private var command = ""
    @State private var pluginSearch = ""
    @State private var filePendingDelete: ManagedServerFile?
    @State private var showEULAInfo = false

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }
    private var server: MinecraftServerController { model.serverController }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PageHeader(
                    eyebrow: "Servidores",
                    title: "Centro de servidor",
                    subtitle: "Cria e gere servidores Paper, Fabric, Forge e NeoForge.",
                    accent: accent
                ) {
                    HStack(spacing: Theme.Space.s) {
                        StatusDot(color: server.running ? Theme.success : Theme.textTertiary, pulsing: server.running, size: 8)
                        Text(server.status)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background { Capsule().fill(.ultraThinMaterial) }
                }

                creationPanel
                controlPanel
                consolePanel
                pluginsPanel
                filesPanel
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            "Apagar \(filePendingDelete?.name ?? "ficheiro")?",
            isPresented: Binding(
                get: { filePendingDelete != nil },
                set: { if !$0 { filePendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apagar ficheiro", role: .destructive) {
                if let file = filePendingDelete {
                    try? server.deleteFile(file)
                }
                filePendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { filePendingDelete = nil }
        }
        .onAppear {
            if name.isEmpty { name = preferences.serverName }
            if version.isEmpty { version = preferences.serverVersion }
            memory = preferences.serverMemory
            if server.paperVersions.isEmpty {
                Task { await server.loadPaperVersions() }
            }
        }
    }

    // MARK: - Creation

    private var creationPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Criar servidor", subtitle: "Instaladores oficiais", systemImage: "square.and.arrow.down.fill", accent: accent)

                HStack(spacing: Theme.Space.s) {
                    FormTextField(prompt: "Nome da pasta", text: $name, accent: accent)
                        .frame(maxWidth: 220)

                    Picker("Software", selection: $software) {
                        ForEach(["Paper", "Fabric", "Forge", "NeoForge"], id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    if software == "Paper" && !server.paperVersions.isEmpty {
                        Picker("Minecraft", selection: $version) {
                            ForEach(server.paperVersions, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    } else {
                        FormTextField(prompt: "Versão", text: $version, accent: accent)
                            .frame(width: 130)
                    }

                    if software == "Paper" {
                        IconButton(systemImage: "arrow.clockwise", tint: accent, size: 30) {
                            Task { await server.loadPaperVersions() }
                        }
                        .help("Atualizar versões Paper")
                    }
                }

                HStack(spacing: Theme.Space.m) {
                    Stepper("Memória: \(memory) GB", value: $memory, in: 2...64)
                        .frame(maxWidth: 220)

                    Spacer()

                    NeonButton(
                        title: server.busy ? "A instalar…" : "Criar e baixar \(software)",
                        systemImage: "arrow.down.circle.fill",
                        accent: accent,
                        secondary: secondary,
                        busy: server.busy
                    ) {
                        createServer()
                    }
                    .disabled(server.busy || version.isEmpty)
                }

                Text("Forge e NeoForge requerem Java 17 ou superior instalado no Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Control

    private var controlPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "EULA e execução", systemImage: "checkmark.seal.fill", accent: accent) {
                    GhostButton(title: "Selecionar pasta", systemImage: "folder", tint: accent, compact: true) {
                        server.chooseServerFolder()
                    }
                    GhostButton(title: "Abrir pasta", systemImage: "arrow.up.forward.app", tint: accent, compact: true) {
                        try? server.openServerFolder()
                    }
                }

                HStack(spacing: Theme.Space.s) {
                    Toggle("Li e aceito a EULA do Minecraft", isOn: $acceptedEULA)
                        .toggleStyle(.switch)
                        .tint(accent)
                    Link("Ver EULA", destination: URL(string: "https://aka.ms/MinecraftEULA")!)
                        .font(.system(size: 11.5))
                }

                HStack(spacing: Theme.Space.s) {
                    NeonButton(
                        title: "Iniciar servidor",
                        systemImage: "play.fill",
                        accent: accent,
                        secondary: secondary,
                        prominent: false,
                        busy: server.busy
                    ) {
                        server.start(acceptedEULA: acceptedEULA, memoryGB: memory)
                    }
                    .disabled(server.running)

                    GhostButton(title: "Parar", systemImage: "stop.fill", tint: Theme.warning) {
                        server.stop()
                    }
                    .disabled(!server.running)

                    GhostButton(title: "Terminar", systemImage: "xmark.octagon.fill", tint: Theme.danger) {
                        server.forceStop()
                    }
                    .disabled(!server.running)

                    Spacer()

                    if server.running {
                        GlassChip(text: String(format: "CPU %.1f%%", server.cpuUsage), systemImage: "cpu", tint: accent, filled: true)
                        GlassChip(text: String(format: "%.0f MB", server.memoryUsageMB), systemImage: "memorychip", tint: Theme.info, filled: true)
                    }
                }

                Text(server.directoryURL?.path ?? "Nenhuma pasta de servidor selecionada")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Console

    private var consolePanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Consola do servidor", subtitle: "Comandos e saída do processo", systemImage: "terminal.fill", accent: accent) {
                    GhostButton(title: "Copiar", systemImage: "doc.on.doc", tint: accent, compact: true) {
                        server.copyConsole()
                    }
                    GhostButton(title: "Limpar", systemImage: "trash", tint: accent, compact: true) {
                        server.clearConsole()
                    }
                }

                ConsoleSurface(text: server.console, accent: accent, minHeight: 210)

                HStack(spacing: Theme.Space.s) {
                    FormTextField(prompt: "Comando de consola", text: $command, accent: accent)
                        .onSubmit { submitCommand() }
                    NeonButton(title: "Enviar", systemImage: "paperplane.fill", accent: accent, secondary: secondary, prominent: false, compact: true) {
                        submitCommand()
                    }
                    .disabled(!server.running)
                }
            }
        }
    }

    // MARK: - Plugins

    private var pluginsPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Plugins para Paper", subtitle: "Catálogo Modrinth", systemImage: "puzzlepiece.fill", accent: accent)

                HStack(spacing: Theme.Space.s) {
                    SearchField(prompt: "Pesquisar plugins…", text: $pluginSearch, accent: accent)
                    NeonButton(title: "Pesquisar", systemImage: "magnifyingglass", accent: accent, secondary: secondary, prominent: false, compact: true) {
                        Task { await server.searchPlugins(query: pluginSearch, gameVersion: version) }
                    }
                }

                if server.plugins.isEmpty {
                    EmptyStateView(
                        systemImage: "puzzlepiece",
                        title: "Nenhum plugin encontrado",
                        message: "Pesquisa plugins compatíveis com a versão do teu servidor.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 5) {
                        ForEach(server.plugins) { plugin in
                            HStack(spacing: Theme.Space.m) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(plugin.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                    Text(plugin.description).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                                    Text("\(plugin.downloads.formatted()) downloads")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer(minLength: Theme.Space.s)
                                GhostButton(title: "Baixar", systemImage: "arrow.down.circle", tint: accent, compact: true) {
                                    Task { await server.downloadPlugin(plugin, gameVersion: version) }
                                }
                            }
                            .padding(Theme.Space.s)
                            .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.035)) }
                        }
                    }
                }

                Text("Os plugins são guardados em plugins/. Reinicia o servidor para os carregar.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Files

    private var filesPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Ficheiros do servidor", subtitle: "\(server.files.count) itens", systemImage: "folder.fill", accent: accent) {
                    GhostButton(title: "Atualizar", systemImage: "arrow.clockwise", tint: accent, compact: true) {
                        server.refreshFiles()
                    }
                }

                SearchField(prompt: "Pesquisar ficheiros…", text: fileSearchBinding, accent: accent)

                if server.filteredFiles.isEmpty {
                    EmptyStateView(
                        systemImage: "folder",
                        title: "Sem ficheiros",
                        message: "Cria ou seleciona uma pasta de servidor para ver os ficheiros.",
                        accent: accent
                    )
                } else {
                    VStack(spacing: 4) {
                        ForEach(server.filteredFiles) { file in
                            HStack(spacing: Theme.Space.s) {
                                Image(systemName: file.isDirectory ? "folder.fill" : (file.name.hasSuffix(".jar") ? "shippingbox.fill" : "doc.fill"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(accent)
                                    .frame(width: 22)
                                Text(file.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if !file.isDirectory {
                                    Text(FileHelper.formattedSize(file.size))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                IconButton(systemImage: "arrow.up.right.square", tint: accent, size: 24) {
                                    server.openFile(file)
                                }
                                IconButton(systemImage: "trash", tint: Theme.danger, size: 24) {
                                    filePendingDelete = file
                                }
                            }
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, 5)
                            .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.025)) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// Two-way binding for the server file search field.
    private var fileSearchBinding: Binding<String> {
        Binding(
            get: { model.serverController.fileSearch },
            set: { model.serverController.fileSearch = $0 }
        )
    }

    private func createServer() {
        Task {
            switch software {
            case "Fabric":
                await server.createFabricServer(name: name, version: version)
            case "Forge", "NeoForge":
                await server.createInstallerServer(name: name, gameVersion: version, software: software)
            default:
                await server.createPaperServer(name: name, version: version)
            }
            preferences.serverName = name
            preferences.serverVersion = version
            preferences.serverSoftware = software
            preferences.serverMemory = memory
        }
    }

    private func submitCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        server.sendCommand(text)
        command = ""
    }
}
