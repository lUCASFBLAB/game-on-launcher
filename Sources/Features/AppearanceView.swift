import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Themes, colours and the background media.
@MainActor
struct AppearanceView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var showImageImporter = false
    @State private var showVideoImporter = false
    @State private var showMusicImporter = false
    @State private var imageStatus = "Nenhuma imagem selecionada"
    @State private var videoStatus = "Nenhum vídeo selecionado"
    @State private var videoDuration: Double = 0
    @State private var previewAsset: NSImage?

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PageHeader(
                    eyebrow: "Personalização",
                    title: "Aparência",
                    subtitle: "Monta o launcher do teu jeito. As alterações são imediatas.",
                    accent: accent
                ) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 46, height: 46)
                        .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.14)) }
                }

                accentPanel
                seasonalPanel
                stylePanel
                backgroundPanel
                musicPanel
                navigationPanel
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 950, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $showImageImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { importBackgroundImage($0) }
        .fileImporter(isPresented: $showVideoImporter, allowedContentTypes: [.movie, .video], allowsMultipleSelection: false) { importBackgroundVideo($0) }
        .onAppear {
            restoreImageStatus()
            restoreVideoStatus()
        }
    }

    // MARK: - Accent

    private var accentPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Cor de destaque", subtitle: "Escolhe o acento ou cria o teu", systemImage: "paintpalette.fill", accent: accent)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(Theme.accents) { preset in
                        Button {
                            preferences.accentID = preset.id
                        } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [preset.primary, preset.secondary],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 38, height: 38)
                                        .shadow(color: preset.primary.opacity(preferences.accentID == preset.id ? 0.6 : 0.2), radius: 8, y: 3)
                                    if preferences.accentID == preset.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundStyle(.white)
                                    }
                                }
                                Text(preset.name)
                                    .font(.system(size: 10.5, weight: preferences.accentID == preset.id ? .bold : .regular))
                                    .foregroundStyle(preferences.accentID == preset.id ? Theme.textPrimary : Theme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                    .fill(preferences.accentID == preset.id ? preset.primary.opacity(0.10) : Color.white.opacity(0.03))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                    .strokeBorder(preferences.accentID == preset.id ? preset.primary.opacity(0.4) : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Seasonal

    private var seasonalPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Eventos e temas sazonais", subtitle: "Natal, Halloween e outras épocas", systemImage: "sparkles", accent: accent) {
                    Toggle("Automático", isOn: Binding(
                        get: { preferences.seasonalTheme == "Automático" },
                        set: { preferences.seasonalTheme = $0 ? "Automático" : preferences.resolvedSeason }
                    ))
                    .toggleStyle(.switch)
                    .tint(accent)
                    .font(.system(size: 11.5))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                    ForEach(Theme.seasonalThemes) { season in
                        Button {
                            preferences.seasonalTheme = season.id
                        } label: {
                            HStack(spacing: 7) {
                                Text(season.emoji).font(.system(size: 14))
                                Text(season.name).font(.system(size: 11.5, weight: .semibold))
                            }
                            .foregroundStyle(preferences.seasonalTheme == season.id ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                    .fill(
                                        preferences.seasonalTheme == season.id
                                            ? LinearGradient(colors: [season.primary, season.secondary], startPoint: .leading, endPoint: .trailing)
                                            : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.03)], startPoint: .leading, endPoint: .trailing)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingToggle(
                    title: "Ativar decoração sazonal",
                    subtitle: "Mostra elementos temáticos no fundo.",
                    systemImage: "wand.and.stars",
                    accent: accent,
                    isOn: $preferences.seasonalEffects
                )
            }
        }
    }

    // MARK: - Style

    private var stylePanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Estilo", systemImage: "slider.horizontal.3", accent: accent)

                HStack {
                    Text("Base").font(.system(size: 12.5))
                    Spacer()
                    SegmentBar(
                        options: [(true, "Escuro", "moon.stars.fill"), (false, "Claro", "sun.max.fill")],
                        selection: $preferences.darkMode,
                        accent: accent
                    )
                    .frame(width: 190)
                }

                Divider().opacity(0.4)

                MetricSlider(label: "Opacidade dos painéis", systemImage: "square.on.square.dashed", value: $preferences.panelOpacity, range: 0.3...1, unit: "%", accent: accent, step: 0.02)
                MetricSlider(label: "Arredondamento", systemImage: "circle.circle", value: $preferences.panelRadius, range: 6...26, unit: " pt", accent: accent)
                MetricSlider(label: "Desfoque", systemImage: "aqi.medium", value: $preferences.blurRadius, range: 0...40, unit: " pt", accent: accent)

                Divider().opacity(0.4)

                SettingToggle(title: "Grelha holográfica", subtitle: "Linhas em fuga no fundo.", systemImage: "grid", accent: accent, isOn: $preferences.gridEnabled)
                SettingToggle(title: "Partículas", subtitle: "Ponto de luz em movimento.", systemImage: "sparkles", accent: accent, isOn: $preferences.particlesEnabled)
                SettingToggle(title: "Animações", subtitle: "Transições e efeitos animados.", systemImage: "wand.and.rays", accent: accent, isOn: $preferences.animationsEnabled)
            }
        }
    }

    // MARK: - Background

    private var backgroundPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Plano de fundo", subtitle: "Imagem ou vídeo local, reproduzido em loop", systemImage: "photo.on.rectangle.angled", accent: accent)

                HStack(spacing: Theme.Space.m) {
                    mediaTile(
                        icon: "photo.fill",
                        title: "Imagem estática",
                        subtitle: "PNG, JPG, HEIC e formatos suportados pelo macOS",
                        status: imageStatus,
                        hasAsset: !preferences.backgroundImagePath.isEmpty,
                        actionTitle: "Selecionar imagem…",
                        action: { showImageImporter = true },
                        remove: clearBackgroundImage
                    )

                    mediaTile(
                        icon: "film.fill",
                        title: "Vídeo de fundo",
                        subtitle: "MP4, MOV ou M4V · até 30 segundos · loop automático",
                        status: videoStatus,
                        hasAsset: !preferences.backgroundVideoPath.isEmpty,
                        actionTitle: "Escolher vídeo…",
                        action: { showVideoImporter = true },
                        remove: clearBackgroundVideo
                    )
                }

                if !preferences.backgroundVideoPath.isEmpty {
                    SettingToggle(
                        title: "Reproduzir vídeo de fundo",
                        subtitle: "Desliga para poupar bateria.",
                        systemImage: "play.circle.fill",
                        accent: accent,
                        isOn: $preferences.backgroundVideoEnabled
                    )
                }

                if !preferences.backgroundImagePath.isEmpty {
                    MetricSlider(
                        label: "Opacidade da imagem",
                        systemImage: "circle.lefthalf.filled",
                        value: $preferences.backgroundImageOpacity,
                        range: 0...0.8,
                        unit: "%",
                        accent: accent,
                        step: 0.02
                    )
                }
            }
        }
    }

    /// Background music player.
    private var musicPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Música de fundo",
                    subtitle: "Uma faixa local em loop enquanto usas o launcher",
                    systemImage: "music.note",
                    accent: accent
                ) {
                    if model.music.isPlaying {
                        GlassChip(text: "A tocar", systemImage: "speaker.wave.2.fill", tint: Theme.success, filled: true)
                    }
                }

                HStack(spacing: Theme.Space.s) {
                    Button {
                        showMusicImporter = true
                    } label: {
                        Label("Escolher faixa…", systemImage: "folder")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.music.toggle()
                    } label: {
                        Label(model.music.isPlaying ? "Pausar" : "Tocar", systemImage: model.music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.music.trackName == "Nenhuma faixa")

                    if model.music.trackName != "Nenhuma faixa" {
                        Button {
                            model.music.clear()
                            preferences.musicPath = ""
                        } label: {
                            Label("Remover", systemImage: "trash")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.danger)
                    }

                    Spacer()

                    Text(model.music.trackName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                MetricSlider(
                    label: "Volume",
                    systemImage: "speaker.wave.2",
                    value: Binding(
                        get: { Double(preferences.musicVolume) },
                        set: { newValue in
                            preferences.musicVolume = newValue
                            model.music.setVolume(newValue)
                        }
                    ),
                    range: 0...1,
                    unit: "",
                    accent: accent,
                    step: 0.05
                )

                SettingToggle(
                    title: "Tocar música de fundo",
                    subtitle: "A faixa continua quando mudas de página.",
                    systemImage: "music.note.list",
                    accent: accent,
                    isOn: $preferences.musicEnabled
                )
            }
        }
        .fileImporter(
            isPresented: $showMusicImporter,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.music.importTrack(url)
                    preferences.musicPath = model.music.savedPath
                }
            case .failure(let error):
                model.notify("Não foi possível abrir a faixa: \(error.localizedDescription)", kind: .error)
            }
        }
        .onChange(of: preferences.musicEnabled) { enabled in
            if enabled {
                model.music.play()
            } else {
                model.music.pause()
            }
        }
    }

    private func mediaTile(
        icon: String,
        title: String,
        subtitle: String,
        status: String,
        hasAsset: Bool,
        actionTitle: String,
        action: @MainActor @escaping () -> Void,
        remove: @MainActor @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 36, height: 36)
                    .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.14)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: hasAsset ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 10))
                    .foregroundStyle(hasAsset ? Theme.success : Theme.textTertiary)
                Text(status)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            HStack {
                GhostButton(title: actionTitle, systemImage: "folder", tint: accent, compact: true, action: action)
                if hasAsset {
                    GhostButton(title: "Remover", systemImage: "trash", tint: Theme.danger, compact: true, action: remove)
                }
                Spacer()
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Color.white.opacity(0.035)) }
    }

    // MARK: - Navigation

    private var navigationPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Navegação", subtitle: "Posição e ordem dos ícones", systemImage: "sidebar.left", accent: accent)

                SettingToggle(
                    title: "Barra lateral à direita",
                    subtitle: "Move a navegação para o lado oposto.",
                    systemImage: "arrow.left.arrow.right",
                    accent: accent,
                    isOn: $preferences.navigationOnRight
                )

                SettingToggle(
                    title: "Barra recolhida",
                    subtitle: "Mostra apenas os ícones.",
                    systemImage: "rectangle.collapse",
                    accent: accent,
                    isOn: $preferences.navigationCollapsed
                )

                GhostButton(title: "Restaurar ordem original", systemImage: "arrow.uturn.backward", tint: accent) {
                    model.navigationOrder = AppPage.allCases
                    model.persistNavigationOrder()
                }
            }
        }
    }

    // MARK: - Media handling

    private func importBackgroundImage(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            imageStatus = "Não foi possível abrir a imagem: \(error.localizedDescription)"
        case .success(let urls):
            guard let source = urls.first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                guard NSImage(contentsOf: source) != nil else {
                    imageStatus = "O macOS não conseguiu ler este formato de imagem."
                    return
                }
                let folder = AppPaths.backgrounds
                let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
                let destination = folder.appendingPathComponent("background-\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: source, to: destination)
                preferences.backgroundImagePath = destination.path
                imageStatus = "Imagem aplicada · \(destination.lastPathComponent)"
            } catch {
                imageStatus = "Falha ao importar imagem: \(error.localizedDescription)"
            }
        }
    }

    private func importBackgroundVideo(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            videoStatus = "Não foi possível abrir o vídeo: \(error.localizedDescription)"
        case .success(let urls):
            guard let source = urls.first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            Task { @MainActor in
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                do {
                    let asset = AVURLAsset(url: source)
                    let duration = try await asset.load(.duration)
                    let seconds = CMTimeGetSeconds(duration)
                    guard seconds.isFinite, seconds > 0 else {
                        videoStatus = "Este vídeo não tem uma duração válida."
                        return
                    }
                    guard seconds <= 30 else {
                        videoStatus = "O vídeo tem \(Int(seconds.rounded())) s. O limite é 30 segundos."
                        return
                    }
                    let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
                    let destination = AppPaths.backgrounds.appendingPathComponent("background-\(UUID().uuidString).\(ext)")
                    try FileManager.default.copyItem(at: source, to: destination)
                    preferences.backgroundVideoPath = destination.path
                    videoDuration = seconds
                    videoStatus = "Vídeo pronto · reprodução em loop"
                } catch {
                    videoStatus = "Falha ao importar vídeo: \(error.localizedDescription)"
                }
            }
        }
    }

    private func clearBackgroundImage() {
        if !preferences.backgroundImagePath.isEmpty {
            FileHelper.remove(URL(fileURLWithPath: preferences.backgroundImagePath))
        }
        preferences.backgroundImagePath = ""
        imageStatus = "Nenhuma imagem selecionada"
    }

    private func clearBackgroundVideo() {
        if !preferences.backgroundVideoPath.isEmpty {
            FileHelper.remove(URL(fileURLWithPath: preferences.backgroundVideoPath))
        }
        preferences.backgroundVideoPath = ""
        videoDuration = 0
        videoStatus = "Nenhum vídeo selecionado"
    }

    private func restoreImageStatus() {
        let path = preferences.backgroundImagePath
        guard !path.isEmpty else {
            imageStatus = "Nenhuma imagem selecionada"
            return
        }
        imageStatus = "Imagem aplicada · \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    private func restoreVideoStatus() {
        let path = preferences.backgroundVideoPath
        guard !path.isEmpty else {
            videoStatus = "Nenhum vídeo selecionado"
            return
        }
        videoStatus = "Vídeo pronto · reprodução em loop"
    }
}
