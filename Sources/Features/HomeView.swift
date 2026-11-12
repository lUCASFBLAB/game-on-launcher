import SwiftUI

/// The main launcher screen, laid out like the official Minecraft launcher:
/// a large hero banner, a row of quick selectors and a news feed.
struct HomeView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var showNewInstance = false
    @State private var showAllNews = false

    private var accent: Color { preferences.tokens.accent }
    private var secondary: Color { preferences.tokens.accentSecondary }

    private var instance: Instance? { model.selectedInstance }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                hero
                selectorRow
                newsSection
            }
            .padding(Theme.gutter)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showNewInstance) {
            NewInstanceSheet(model: model).environmentObject(preferences)
        }
        .task {
            await model.news.load()
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop.
            VoxelLandscape(accent: accent, secondary: secondary)
                .overlay {
                    // Legibility scrim.
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.62),
                            Color.black.opacity(0.18),
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("EXPLORE · CONSTRUA · SOBREVIVA")
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(3.4)
                        .foregroundStyle(.white.opacity(0.72))

                    Text(heroTitle)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(heroSubtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .frame(maxWidth: 460, alignment: .leading)

                    NeonButton(
                        title: model.launching ? "A INICIAR…" : "JOGAR",
                        systemImage: model.launching ? "arrow.down.circle" : "play.fill",
                        accent: accent,
                        secondary: secondary,
                        busy: model.launching,
                        gradient: false
                    ) {
                        Task { await model.launchSelectedInstance() }
                    }
                    .frame(maxWidth: 260)
                    .padding(.top, Theme.Space.s)

                    // Anything that would stop the game from starting is listed here,
                    // so pressing Jogar never fails silently.
                    ForEach(launchProblems, id: \.self) { problem in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.warning)
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Theme.Space.xs)
                        .frame(maxWidth: 300, alignment: .leading)
                    }
                }
                .padding(Theme.Space.xl)

                Spacer(minLength: Theme.Space.l)

                if let instance {
                    loaderCard(instance)
                        .padding(.trailing, Theme.Space.xl)
                        .padding(.bottom, Theme.Space.xl)
                }
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 26, y: 12)
    }

    /// Problems that would prevent the game from starting.
    private var launchProblems: [String] {
        guard let instance else { return [] }
        return model.diagnoseLaunch(instance)
    }

    private var heroTitle: String {
        guard let instance else { return "Cria a tua primeira instância" }
        if preferences.streamerMode && preferences.hideInstance {
            return "Instância protegida"
        }
        return instance.name
    }

    private var heroSubtitle: String {
        guard let instance else {
            return "Escolhe uma versão, um loader e começa a tua aventura em segundos."
        }
        let version = instance.displayVersion
        let loader = instance.loaderLabel
        return "Minecraft \(version) · \(loader)\nUm mundo infinito de possibilidades. Jogue do seu jeito."
    }

    /// The loader card shown in the bottom-right corner of the hero.
    private func loaderCard(_ instance: Instance) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: instance.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.16)) }

            VStack(alignment: .leading, spacing: 1) {
                Text("\(instance.loaderLabel) Loader")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text(instance.displayVersion)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(Color.black.opacity(0.42))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
        }
        .onTapGesture { model.select(.instances) }
    }

    // MARK: - Selector row

    private var selectorRow: some View {
        HStack(spacing: Theme.Space.m) {
            selectorCard(
                icon: "square.stack.3d.up.fill",
                title: "Instância atual",
                value: instanceLabel,
                accent: accent
            ) {
                model.select(.instances)
            }

            selectorCard(
                icon: "gamecontroller.fill",
                title: "Perfil de jogo",
                value: profileLabel,
                accent: accent
            ) {
                model.select(.accounts)
            }

            selectorCard(
                icon: "slider.horizontal.3",
                title: "Mais opções",
                value: "Personalizar",
                accent: accent
            ) {
                model.select(.settings)
            }
        }
    }

    private var instanceLabel: String {
        guard let instance else { return "Nenhuma" }
        if preferences.streamerMode && preferences.hideInstance { return "Protegida" }
        return instance.name
    }

    private var profileLabel: String {
        if case .signedIn(let profile) = model.accountState {
            if preferences.streamerMode && preferences.hideNickname { return "Oculto" }
            return profile.name
        }
        return preferences.nickname
    }

    private func selectorCard(
        icon: String,
        title: String,
        value: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background { RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.14)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(value)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.05), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - News

    private var newsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("NOVIDADES")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.6)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showAllNews.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(showAllNews ? "Ver menos" : "Ver todas")
                            .font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            if model.news.loading && model.news.items.isEmpty {
                ProgressView("A carregar novidades…")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 30)
            } else if model.news.items.isEmpty {
                EmptyStateView(
                    systemImage: "newspaper",
                    title: "Sem novidades",
                    message: model.news.error ?? "Não foi possível carregar o feed de novidades.",
                    accent: accent
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: Theme.Space.m)],
                    spacing: Theme.Space.m
                ) {
                    ForEach(visibleNews) { item in
                        newsCard(item)
                    }
                }
            }
        }
    }

    private var visibleNews: [NewsItem] {
        showAllNews ? model.news.items : Array(model.news.items.prefix(3))
    }

    private func newsCard(_ item: NewsItem) -> some View {
        HStack(spacing: Theme.Space.m) {
            RemoteImage(url: item.imageURL)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(item.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)

                Text(item.date.formatted(.dateTime.day().month(.wide).year()))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.75))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}
