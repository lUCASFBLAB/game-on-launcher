import SwiftUI

/// Application preferences.
@MainActor
struct SettingsView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var tab = "Geral"
    @State private var apiKeyDraft = ""
    @State private var curseForgeStatus = ""

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    private let tabs = ["Geral", "Minecraft", "Java", "Contas", "Serviços", "CurseForge", "Pastas", "Atualizações", "Proxy", "Créditos"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PageHeader(
                eyebrow: "Preferências",
                title: "Configurações",
                subtitle: "Todas as opções são guardadas e aplicadas de imediato.",
                accent: accent
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tabs, id: \.self) { item in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                tab = item
                                preferences.settingsTab = item
                            }
                        } label: {
                            Text(item)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(tab == item ? .white : Theme.textSecondary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 7)
                                .background {
                                    if tab == item {
                                        Capsule().fill(
                                            LinearGradient(colors: [accent, secondary], startPoint: .leading, endPoint: .trailing)
                                        )
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            GlassPanel(accent: accent) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    switch tab {
                    case "Geral": generalSection
                    case "Minecraft": minecraftSection
                    case "Java": javaSection
                    case "Contas": accountsSection
                    case "Serviços": servicesSection
                    case "CurseForge": curseForgeSection
                    case "Pastas": foldersSection
                    case "Atualizações": updatesSection
                    case "Proxy": proxySection
                    default: creditsSection
                    }
                }
            }
        }
        .padding(Theme.gutter)
        .frame(maxWidth: 1000, alignment: .leading)
        .onAppear {
            // Restore the tab that was open last time.
            if preferences.tabs.contains(preferences.settingsTab) {
                tab = preferences.settingsTab
            }
            curseForgeStatus = LocalSecretStore.read("curseforge") == nil
                ? "Nenhuma chave guardada."
                : "Chave guardada no Porta-chaves do macOS."
        }
    }

    // MARK: - Geral

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Interface de utilizador")

                Picker("Ordenação de instâncias", selection: $preferences.instanceSort) {
                    Text("Por nome").tag("Por nome")
                    Text("Por último lançado").tag("Por último lançado")
                }
                .pickerStyle(.segmented)

                Picker("Renomeação de pasta", selection: $preferences.instanceRenamePolicy) {
                    Text("Perguntar o que fazer").tag("Perguntar o que fazer")
                    Text("Sempre renomear pasta").tag("Sempre renomear pasta")
                    Text("Nunca renomear pasta").tag("Nunca renomear pasta")
                }
                .pickerStyle(.menu)
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                sectionTitle("Mods e pacotes de mods")
                SettingToggle(title: "Acompanhar metadados do mod", systemImage: "doc.text", accent: accent, isOn: $preferences.trackModMetadata)
                SettingToggle(title: "Instalar dependências automaticamente", systemImage: "arrow.triangle.2.circlepath", accent: accent, isOn: $preferences.installModDependencies)
                SettingToggle(title: "Detetar incompatibilidades de mods", subtitle: "Experimental.", systemImage: "exclamationmark.triangle", accent: accent, isOn: $preferences.detectModConflicts)
                SettingToggle(title: "Verificar subpastas de mods", systemImage: "folder.badge.questionmark", accent: accent, isOn: $preferences.verifyModSubpaths)
                SettingToggle(title: "Mover mods bloqueados em vez de os copiar", systemImage: "scissors", accent: accent, isOn: $preferences.moveBlockedMods)
                SettingToggle(title: "Sugerir atualizar instância ao instalar pacote", systemImage: "arrow.up.circle", accent: accent, isOn: $preferences.suggestInstanceUpdates)
                SettingToggle(title: "Atualizar mods ao instalar", systemImage: "arrow.triangle.2.circlepath", accent: accent, isOn: $preferences.updateModsOnInstall)
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Atalhos")
                shortcutRow("Alternar modo streamer", "⌥⌘S")
                shortcutRow("Abrir pasta da instância", "⌘L")
            }
        }
    }

    private func shortcutRow(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5))
            Spacer()
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)) }
        }
    }

    // MARK: - Minecraft

    private var minecraftSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Motor de jogo")

                Text("O motor interno descarrega os ficheiros oficiais da Mojang e inicia o Minecraft sem depender de qualquer launcher externo. Suporta vanilla e os carregadores Fabric, Quilt, Forge e NeoForge.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Java instalado").font(.system(size: 13, weight: .semibold))
                    JavaStatusView(accent: accent, minecraftVersion: preferences.defaultMinecraftVersion)
                    Text("O Minecraft 1.20.5 e posteriores exigem Java 21; as versões anteriores aceitam Java 17. O launcher escolhe automaticamente o runtime adequado.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack {
                    Text("Versão Minecraft por omissão").font(.system(size: 12.5))
                    Spacer()
                    FormTextField(prompt: "1.21.8", text: $preferences.defaultMinecraftVersion, accent: accent)
                        .frame(width: 120)
                }

                Picker("Loader por omissão", selection: $preferences.defaultLoader) {
                    ForEach(["Fabric", "Forge", "NeoForge", "Quilt", "Nenhum"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                sectionTitle("Comportamento")
                SettingToggle(title: "Fechar o launcher ao iniciar o jogo", systemImage: "power", accent: accent, isOn: $preferences.autoCloseOnLaunch)
                SettingToggle(title: "Manter o launcher aberto", systemImage: "macwindow", accent: accent, isOn: $preferences.keepLauncherOpen)
                SettingToggle(title: "Avisar quando a memória for insuficiente", systemImage: "exclamationmark.triangle", accent: accent, isOn: $preferences.warnLowMemory)
            }

            if preferences.maxMemory < preferences.minMemory {
                StatusBanner(kind: .warning, message: "A memória máxima é inferior à mínima. Corrige os valores em Java.", accent: accent)
            }
        }
    }

    // MARK: - Java

    private var javaSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Memória")
                MetricSlider(label: "Memória mínima", systemImage: "arrow.down", value: $preferences.minMemory, range: 512...8192, unit: " MiB", accent: accent, step: 256)
                MetricSlider(label: "Memória máxima", systemImage: "arrow.up", value: $preferences.maxMemory, range: 1024...16384, unit: " MiB", accent: accent, step: 256)
            }

            if preferences.maxMemory < preferences.minMemory {
                StatusBanner(kind: .error, message: "A memória máxima (\(Int(preferences.maxMemory)) MiB) é menor que a mínima (\(Int(preferences.minMemory)) MiB).", accent: accent)
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Argumentos JVM")
                TextField("Argumentos JVM", text: $preferences.javaArgs, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2...5)
                    .padding(10)
                    .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.05)) }
                    .overlay { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }

                HStack {
                    GhostButton(title: "Testar configuração", systemImage: "stethoscope", tint: accent) {
                        model.notify("Os argumentos serão aplicados na próxima vez que iniciares o jogo.", kind: .info)
                    }
                    GhostButton(title: "Restaurar omissões", systemImage: "arrow.uturn.backward", tint: accent) {
                        preferences.javaArgs = "-Djava.net.preferIPv4Stack=true"
                    }
                    Spacer()
                }
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                sectionTitle("Java instalado")
                JavaDetectionView(accent: accent)
            }
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("Contas")
            Text("Perfis Microsoft e offline são geridos na página Contas.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            HStack {
                NeonButton(title: "Abrir contas", systemImage: "person.crop.circle.fill", accent: accent, secondary: secondary, prominent: false) {
                    model.select(.accounts)
                }
                Spacer()
            }

            divider

            sectionTitle("Nome do perfil offline")
            FormTextField(prompt: "Jogador", text: $preferences.nickname, accent: accent)
        }
    }

    // MARK: - Services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("Fontes de conteúdo")
            HStack(spacing: Theme.Space.s) {
                ForEach(["Modrinth", "CurseForge", "PaperMC"], id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.success)
                        Text(name).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background { Capsule().fill(Color.white.opacity(0.05)) }
                }
            }
            Text("O Modrinth e o PaperMC não exigem chave de API. O CurseForge precisa de uma chave autorizada.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - CurseForge

    private var curseForgeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("API CurseForge")
            Text("A chave fica guardada no Porta-chaves do macOS e é enviada apenas à API oficial CurseForge.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)

            FormSecureField(prompt: "API key", text: $apiKeyDraft)

            HStack {
                NeonButton(title: "Guardar chave", systemImage: "key.fill", accent: accent, secondary: secondary, prominent: false) {
                    saveCurseForgeKey()
                }
                GhostButton(title: "Remover chave", systemImage: "trash", tint: Theme.danger) {
                    LocalSecretStore.delete("curseforge")
                    model.curseForgeVersions = []
                    curseForgeStatus = "Chave removida."
                    model.notify("Chave CurseForge removida.", kind: .info)
                }
                Spacer()
            }

            StatusBanner(kind: LocalSecretStore.read("curseforge") == nil ? .warning : .success, message: curseForgeStatus, accent: accent)

            Link("Documentação oficial e acesso à API", destination: URL(string: "https://docs.curseforge.com/rest-api/")!)
                .font(.system(size: 12))
            Text("A API oficial requer uma chave autorizada. O app não inclui uma chave própria.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("Pastas")
            Text("O launcher usa as suas próprias pastas em ~/Library/Application Support/GameOnLauncher.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            folderRow(label: "Instâncias", value: AppPaths.instances.path) {
                NSWorkspace.shared.open(AppPaths.instances)
            }
            folderRow(label: "Mods", value: AppPaths.instances.path + "/<instância>/mods") {
                if let instance = model.selectedInstance {
                    NSWorkspace.shared.open(InstanceStore.modsFolder(for: instance))
                }
            }
            folderRow(label: "Downloads", value: AppPaths.downloads.path) {
                NSWorkspace.shared.open(AppPaths.downloads)
            }
            folderRow(label: "Servidores", value: AppPaths.servers.path) {
                NSWorkspace.shared.open(AppPaths.servers)
            }
            folderRow(label: "Planos de fundo", value: AppPaths.backgrounds.path) {
                NSWorkspace.shared.open(AppPaths.backgrounds)
            }
            folderRow(label: "Registos do launcher", value: AppPaths.logs.path) {
                NSWorkspace.shared.open(AppPaths.logs)
            }

            HStack {
                GhostButton(title: "Abrir pasta de suporte", systemImage: "folder", tint: accent) {
                    NSWorkspace.shared.open(AppPaths.root)
                }
                Spacer()
            }
        }
    }

    private func folderRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 12.5)).frame(width: 170, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            IconButton(systemImage: "arrow.up.forward.app", tint: accent, size: 26, action: action)
                .help("Abrir pasta")
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            UpdatePanelView(model: model, accent: accent)

            Divider()

            sectionTitle("Verificação automática")
            SettingToggle(
                title: "Verificar atualizações ao iniciar",
                subtitle: "Procur uma build nova quando o launcher abre.",
                systemImage: "arrow.clockwise",
                accent: accent,
                isOn: $preferences.checkUpdatesOnStart
            )

            HStack {
                Text("Com que frequência").font(.system(size: 12.5))
                Spacer()
                Picker("Frequência", selection: $preferences.updateFrequency) {
                    ForEach(["A cada hora", "Todo o dia", "Semanalmente", "Nunca"], id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack {
                Text("As builds são publicadas em github.com/\(UpdateService.repository), sempre sob a etiqueta \(UpdateService.releaseTag).")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
            }
        }
    }

    // MARK: - Proxy

    private var proxySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            sectionTitle("Proxy")
            SettingToggle(title: "Usar proxy", systemImage: "network", accent: accent, isOn: .constant(false))
            FormTextField(prompt: "Endereço do proxy (ex.: 127.0.0.1:8080)", text: .constant(""), accent: accent)
            Text("O suporte de proxy requer configuração de rede avançada. As credenciais nunca são solicitadas.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Créditos

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Créditos e licenças")
                .font(.system(size: 17, weight: .bold))
            Text("Game on Launcher é um projeto independente. As marcas e serviços abaixo pertencem aos respetivos criadores.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                creditLink("Lucas Gonçalves (@lUCASFBLAB)", detail: "Criador do Game on Launcher", url: "https://github.com/lUCASFBLAB")
                creditLink("OpenAI · Codex", detail: "Assistência de IA no desenvolvimento", url: "https://openai.com/")
                creditLink("GitHub", detail: "Plataforma de código e colaboração; não é coautor", url: "https://github.com/lUCASFBLAB")
            }

            divider

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                creditLink("Mojang Studios", detail: "Ficheiros do jogo e APIs oficiais", url: "https://www.minecraft.net/")
                creditLink("Fabric / Quilt", detail: "Carregadores de mods e metadados oficiais", url: "https://fabricmc.net/")
                creditLink("CurseForge", detail: "Catálogo de mods/modpacks e API", url: "https://docs.curseforge.com/rest-api/")
                creditLink("Modrinth", detail: "Catálogo de conteúdo e plugins", url: "https://docs.modrinth.com/api/")
                creditLink("PaperMC", detail: "Servidor Paper e serviço de downloads", url: "https://docs.papermc.io/misc/downloads-service/")
                creditLink("Minecraft EULA", detail: "Termos do Minecraft", url: "https://www.minecraft.net/eula")
            }

            divider

            Text("Game on Launcher não é afiliado, patrocinado ou aprovado pela Mojang/Microsoft, CurseForge, Modrinth ou PaperMC.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func creditLink(_ title: String, detail: String, url: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: "heart.text.square.fill").foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let destination = URL(string: url) {
                Link("Abrir", destination: destination).font(.system(size: 11.5)).buttonStyle(.bordered)
            }
        }
        .padding(Theme.Space.s)
        .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.035)) }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .semibold))
    }

    private var divider: some View {
        Divider().opacity(0.4)
    }

    private func saveCurseForgeKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            curseForgeStatus = "Cole a API key antes de guardar."
            return
        }
        do {
            try LocalSecretStore.write(key, account: "curseforge")
            apiKeyDraft = ""
            curseForgeStatus = "Chave guardada. A testar ligação…"
            Task {
                await model.refreshCurseForgeVersions()
                curseForgeStatus = model.curseForgeStatus
            }
        } catch {
            curseForgeStatus = "Não foi possível guardar no Porta-chaves: \(error.localizedDescription)"
        }
    }
}

/// Detects the Java runtimes installed on the machine.
@MainActor
struct JavaDetectionView: View {
    var accent: Color
    @State private var results: [String] = []
    @State private var checked = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Runtimes detetados").font(.system(size: 12.5, weight: .medium))
                Spacer()
                GhostButton(title: "Procurar", systemImage: "magnifyingglass", tint: accent, compact: true) {
                    detect()
                }
            }

            if checked && results.isEmpty {
                Text("Nenhum Java encontrado. Instala o Java 17 ou superior para jogar e para servidores.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.warning)
            } else {
                ForEach(results, id: \.self) { result in
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.success)
                        Text(result)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .onAppear { detect() }
    }

    private func detect() {
        checked = true
        var found: [String] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        process.arguments = ["-V"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if (try? process.run()) != nil {
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            found = output.split(separator: "\n").map(String.init).filter { $0.contains(" ") }
        }
        results = found
    }
}
