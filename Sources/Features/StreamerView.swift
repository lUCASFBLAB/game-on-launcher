import SwiftUI

/// Streamer mode: privacy, live overlay and shortcuts.
@MainActor
struct StreamerView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var sessionStart = Date()
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PageHeader(
                    eyebrow: "Transmissão",
                    title: "Modo streamer",
                    subtitle: "Protege dados pessoais e prepara o overlay da live.",
                    accent: accent
                ) {
                    Toggle("Ativo", isOn: $preferences.streamerMode)
                        .toggleStyle(.switch)
                        .tint(accent)
                }

                togglePanel
                overlayPanel
                overlayPreview
                shortcutsPanel
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Toggles

    private var togglePanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Privacidade",
                    subtitle: "Oculta informação sensível no ecrã do launcher",
                    systemImage: "lock.shield.fill",
                    accent: accent
                )

                SettingToggle(
                    title: "Ocultar nickname e perfil",
                    subtitle: "Substitui o nome por «Perfil oculto».",
                    systemImage: "person.crop.circle",
                    accent: accent,
                    isOn: $preferences.hideNickname
                )

                SettingToggle(
                    title: "Ocultar nome da instância",
                    subtitle: "Esconde o nome da instância selecionada.",
                    systemImage: "shippingbox",
                    accent: accent,
                    isOn: $preferences.hideInstance
                )

                SettingToggle(
                    title: "Silenciar notificações",
                    subtitle: "Não mostra banners de estado durante a live.",
                    systemImage: "bell.slash.fill",
                    accent: accent,
                    isOn: $preferences.muteNotifications
                )

                Text("Estas opções afetam apenas o que o launcher mostra. Não filtram dados do jogo, do sistema ou de outros aplicativos.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Overlay settings

    private var overlayPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Overlay da live",
                    subtitle: "Composição do painel sobreposto ao ecrã",
                    systemImage: "rectangle.on.rectangle",
                    accent: accent
                )

                SettingToggle(title: "Mostrar estado do jogo", systemImage: "circle.fill", accent: accent, isOn: $preferences.overlayStatus)
                SettingToggle(title: "Mostrar instância atual", systemImage: "shippingbox", accent: accent, isOn: $preferences.overlayInstance)
                SettingToggle(title: "Mostrar cronómetro", systemImage: "timer", accent: accent, isOn: $preferences.overlayTimer)
                SettingToggle(title: "Layout compacto", systemImage: "arrow.down.right.and.arrow.up.left", accent: accent, isOn: $preferences.compactOverlay)

                MetricSlider(
                    label: "Opacidade do overlay",
                    systemImage: "circle.lefthalf.filled",
                    value: $preferences.overlayOpacity,
                    range: 0.3...1,
                    unit: "",
                    accent: accent,
                    step: 0.05
                )

                SettingToggle(title: "Usar cor de destaque", systemImage: "paintpalette", accent: accent, isOn: $preferences.overlayAccent)
            }
        }
    }

    // MARK: - Preview

    private var overlayPreview: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Prévia", subtitle: "Como aparece o overlay no ecrã", systemImage: "eye.fill", accent: accent)

                ZStack {
                    // Simulated game background.
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.16, green: 0.13, blue: 0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    VStack {
                        HStack {
                            Spacer()
                            overlayContent
                                .padding(preferences.compactOverlay ? 8 : 13)
                                .background {
                                    RoundedRectangle(cornerRadius: preferences.compactOverlay ? 8 : 13, style: .continuous)
                                        .fill(Color.black.opacity(0.55 * preferences.overlayOpacity))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: preferences.compactOverlay ? 8 : 13, style: .continuous)
                                        .strokeBorder(overlayTint.opacity(0.35), lineWidth: 1)
                                }
                                .padding(Theme.Space.l)
                        }
                        Spacer()
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
                }
            }
        }
    }

    private var overlayContent: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Text("GAME ON LAUNCHER")
                    .font(.system(size: preferences.compactOverlay ? 8.5 : 9.5, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(overlayTint)
                if preferences.overlayStatus {
                    StatusDot(color: Theme.success, pulsing: true, size: 6)
                    Text("Pronto para jogar")
                        .font(.system(size: preferences.compactOverlay ? 9.5 : 10.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            if preferences.overlayInstance {
                Text(preferences.streamerMode && preferences.hideInstance ? "Instância oculta" : (model.selectedInstance?.name ?? "—"))
                    .font(.system(size: preferences.compactOverlay ? 9.5 : 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            if preferences.overlayTimer {
                Text(elapsed)
                    .font(.system(size: preferences.compactOverlay ? 9.5 : 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var overlayTint: Color {
        preferences.overlayAccent ? accent : Theme.textPrimary
    }

    private var elapsed: String {
        let seconds = Int(Date().timeIntervalSince(sessionStart))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    // MARK: - Shortcuts

    private var shortcutsPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "Atalhos e integrações", systemImage: "keyboard", accent: accent)

                HStack {
                    Text("Alternar modo streamer").font(.system(size: 12.5))
                    Spacer()
                    Text("⌥⌘S")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)) }
                }

                HStack {
                    Text("Abrir a pasta da instância").font(.system(size: 12.5))
                    Spacer()
                    Text("⌘L")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.07)) }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Integração com OBS").font(.system(size: 12.5, weight: .semibold))
                        Text("O overlay é desenhado pelo próprio launcher. A integração nativa com o OBS ainda não está disponível.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    GhostButton(title: "Copiar configuração", systemImage: "doc.on.doc", tint: accent, compact: true) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(overlayConfigurationJSON, forType: .string)
                        model.notify("Configuração do overlay copiada.", kind: .success)
                    }
                }
            }
        }
    }

    /// A JSON snippet that can be pasted into OBS as a browser source.
    private var overlayConfigurationJSON: String {
        let payload: [String: Any] = [
            "status": preferences.overlayStatus,
            "instance": preferences.overlayInstance,
            "timer": preferences.overlayTimer,
            "compact": preferences.compactOverlay,
            "opacity": preferences.overlayOpacity,
            "accent": preferences.overlayAccent ? preferences.accentID : "none"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
