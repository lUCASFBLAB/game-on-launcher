import SwiftUI
import AVFoundation
import AppKit

/// The application entry point.
@main
struct GameOnLauncherApp: App {
    @StateObject private var preferences = Preferences()

    var body: some Scene {
        WindowGroup {
            LauncherRootView()
                .environmentObject(preferences)
                .frame(minWidth: 1080, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Root layout: sidebar + content, with the animated futuristic backdrop.
@MainActor
struct LauncherRootView: View {
    @EnvironmentObject private var preferences: Preferences

    @StateObject private var model = LauncherModel()
    @State private var backgroundImage: NSImage?
    @State private var backgroundPlayer: AVQueuePlayer?
    @State private var backgroundLooper: AVPlayerLooper?

    private var tokens: ThemeTokens { preferences.tokens }
    private var accent: Color { tokens.accent }

    var body: some View {
        HStack(spacing: 0) {
            if preferences.navigationOnRight {
                contentArea
                sidebar
            } else {
                sidebar
                contentArea
            }
        }
        .preferredColorScheme(preferences.darkMode ? .dark : .light)
        .tint(accent)
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            model.bind(preferences: preferences)
            restoreBackgroundImage()
            restoreBackgroundVideo()
        }
        .onChange(of: preferences.backgroundVideoPath) { _ in restoreBackgroundVideo() }
        .onChange(of: preferences.backgroundImagePath) { _ in restoreBackgroundImage() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        SidebarView(
            model: model,
            accent: accent,
            secondary: tokens.accentSecondary,
            onRight: preferences.navigationOnRight,
            collapsed: preferences.navigationCollapsed,
            onSelect: { model.select($0) },
            onToggleCollapse: { preferences.navigationCollapsed.toggle() },
            onToggleSide: { preferences.navigationOnRight.toggle() }
        )
    }

    // MARK: - Content

    private var contentArea: some View {
        ZStack {
            NebulaBackground(accent: accent, secondary: tokens.accentSecondary, isDark: preferences.darkMode)

            if let backgroundImage {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(preferences.backgroundImageOpacity)
                    .ignoresSafeArea()
            }

            if let backgroundPlayer, preferences.backgroundVideoEnabled {
                LoopingVideoBackground(player: backgroundPlayer)
                    .opacity(0.32)
                    .ignoresSafeArea()
            }

            if preferences.gridEnabled && preferences.darkMode {
                GridOverlay(accent: accent, opacity: 0.14)
            }

            if preferences.particlesEnabled && preferences.darkMode {
                Starfield(accent: accent)
            }

            if preferences.animationsEnabled && preferences.darkMode {
                ScanSheen(accent: accent)
            }

            PageRouter(model: model)

            // Floating status toast.
            if let banner = model.banner {
                StatusToast(banner: banner, accent: accent) { model.dismissBanner() }
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.banner)
    }

    // MARK: - Background media

    private func restoreBackgroundImage() {
        let path = preferences.backgroundImagePath
        guard !path.isEmpty else {
            backgroundImage = nil
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url) else {
            backgroundImage = nil
            return
        }
        backgroundImage = image
    }

    private func restoreBackgroundVideo() {
        backgroundPlayer?.pause()
        backgroundLooper = nil
        backgroundPlayer = nil

        let path = preferences.backgroundVideoPath
        guard !path.isEmpty, preferences.backgroundVideoEnabled else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        backgroundLooper = AVPlayerLooper(player: player, templateItem: item)
        backgroundPlayer = player
        player.play()
    }
}

/// Routes the current page to the matching screen.
@MainActor
struct PageRouter: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Group {
            switch model.page {
            case .home: HomeView(model: model)
            case .instances: InstancesView(model: model)
            case .content: ContentHubView(model: model)
            case .server: ServerCenterView(model: model)
            case .logs: LogsView(model: model)
            case .accounts: AccountsView(model: model)
            case .streamer: StreamerView(model: model)
            case .appearance: AppearanceView(model: model)
            case .settings: SettingsView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.99)))
        .id(model.page)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: model.page)
    }
}

/// Floating notification shown at the bottom of the window.
@MainActor
struct StatusToast: View {
    var banner: LauncherModel.Banner
    var accent: Color
    var dismiss: () -> Void

    private var tint: Color {
        switch banner.kind {
        case .info: return accent
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .error: return Theme.danger
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: banner.kind.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
            Text(banner.message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.4), lineWidth: 1)
        }
        .frame(maxWidth: 460)
    }
}
