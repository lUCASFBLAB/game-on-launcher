import SwiftUI

/// Account management: Microsoft device-code login and offline profiles.
@MainActor
struct AccountsView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var offlineName = ""

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                PageHeader(
                    eyebrow: "Identidade",
                    title: "Contas",
                    subtitle: "Inicia sessão com a tua conta Microsoft ou usa um perfil offline.",
                    accent: accent
                )

                currentSession
                microsoftPanel
                offlinePanel
                externalPanel
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            offlineName = preferences.nickname
        }
    }

    // MARK: - Current session

    private var currentSession: some View {
        GlassPanel(accent: accent, elevated: true) {
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [accent.opacity(0.85), secondary.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: accent.opacity(0.35), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profileName).font(.system(size: 16, weight: .bold))
                    HStack(spacing: 7) {
                        GlassChip(text: profileKind, systemImage: profileIcon, tint: accent, filled: true)
                        if case .signedIn(let profile) = model.accountState {
                            GlassChip(text: profile.dashedUUID, systemImage: "number")
                        }
                    }
                }

                Spacer()

                if case .signedIn = model.accountState {
                    GhostButton(title: "Terminar sessão", systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.danger) {
                        model.signOut()
                    }
                } else {
                    Button("Iniciar sessão") {
                        Task { await model.restoreMicrosoftSession() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Microsoft

    private var microsoftPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Conta Microsoft",
                    subtitle: "Autenticação oficial com dispositivo e código",
                    systemImage: "person.badge.key.fill",
                    accent: accent
                )

                switch model.accountState {
                case .awaitingCode(let code, let url):
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(spacing: Theme.Space.m) {
                            Text(code)
                                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                                .tracking(6)
                                .foregroundStyle(accent)
                                .textSelection(.enabled)
                            Spacer()
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .fill(accent.opacity(0.10))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        }

                        Text("Abre \(url) e confirma o código. Depois carrega em «Confirmar».")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)

                        HStack {
                            NeonButton(title: "Confirmar código", systemImage: "checkmark", accent: accent, secondary: secondary, prominent: false) {
                                Task { await model.completeMicrosoftLogin() }
                            }
                            GhostButton(title: "Cancelar", systemImage: "xmark", tint: Theme.textSecondary) {
                                model.cancelLogin()
                            }
                        }
                    }

                case .authenticating:
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("A autenticar com a Microsoft…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }

                case .failed(let reason):
                    StatusBanner(kind: .error, message: reason, accent: accent)

                default:
                    Text("Inicia sessão com a tua conta Microsoft para jogar com o teu perfil, skins e progressos oficiais. O token de sessão é guardado no Porta-chaves do macOS.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)

                    NeonButton(title: "Iniciar sessão com Microsoft", systemImage: "person.badge.key.fill", accent: accent, secondary: secondary, prominent: false) {
                        Task { await model.beginMicrosoftLogin() }
                    }
                }
            }
        }
    }

    // MARK: - Offline

    private var offlinePanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Perfil offline",
                    subtitle: "Joga sem conta, com um nickname local",
                    systemImage: "person.crop.circle",
                    accent: accent
                )

                HStack(spacing: Theme.Space.s) {
                    FormTextField(prompt: "Nickname", text: $offlineName, accent: accent)
                    NeonButton(title: "Usar perfil", systemImage: "checkmark", accent: accent, secondary: secondary, prominent: false) {
                        model.useOfflineProfile(name: offlineName)
                    }
                }

                Text("O modo offline não inclui skins, progressos nem autenticação Microsoft.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - External engine

    private var externalPanel: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Skin da conta",
                    subtitle: "Usa a skin oficial do teu nickname ou importa um PNG",
                    systemImage: "person.crop.rectangle.fill",
                    accent: accent
                )

                SkinPickerView(model: model, accent: accent)
            }
        }
    }

    // MARK: - Derived

    private var profileName: String {
        switch model.accountState {
        case .signedIn(let profile):
            return preferences.streamerMode && preferences.hideNickname ? "Perfil oculto" : profile.name
        case .awaitingCode(let code, _):
            return "A confirmar código \(code)"
        case .authenticating:
            return "A autenticar…"
        case .failed:
            return "Erro de autenticação"
        case .signedOut:
            return preferences.streamerMode && preferences.hideNickname ? "Perfil oculto" : preferences.nickname
        }
    }

    private var profileKind: String {
        switch model.accountState {
        case .signedIn:
            return model.isOfflineProfile ? "Perfil offline" : "Conta Microsoft"
        case .awaitingCode: return "A aguardar confirmação"
        case .authenticating: return "Microsoft"
        case .failed: return "Falhou"
        case .signedOut: return "Sem sessão"
        }
    }

    private var profileIcon: String {
        switch model.accountState {
        case .signedIn: return model.isOfflineProfile ? "person.crop.circle.fill" : "person.badge.key.fill"
        default: return "person.crop.circle"
        }
    }
}
