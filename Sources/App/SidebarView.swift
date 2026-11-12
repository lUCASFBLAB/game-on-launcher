import SwiftUI
import UniformTypeIdentifiers

/// The navigation sidebar.
@MainActor
struct SidebarView: View {
    @ObservedObject var model: LauncherModel
    var accent: Color
    var secondary: Color
    var onRight: Bool
    var collapsed: Bool
    var onSelect: (AppPage) -> Void
    var onToggleCollapse: () -> Void
    var onToggleSide: () -> Void

    @State private var draggingItem: String?

    var body: some View {
        VStack(spacing: 0) {
            brand
                .padding(.top, 18)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.navigationOrder) { page in
                        navButton(page)
                            .onDrag {
                                draggingItem = page.rawValue
                                return NSItemProvider(object: page.rawValue as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: SidebarReorderDelegate(
                                    item: page,
                                    items: $model.navigationOrder,
                                    draggingItem: $draggingItem
                                )
                            )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: collapsed ? Theme.collapsedSidebarWidth : Theme.sidebarWidth)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                // A dark base keeps the navigation legible over any accent colour.
                Rectangle().fill(Color.black.opacity(0.34))
                LinearGradient(
                    colors: [accent.opacity(0.16), .clear, secondary.opacity(0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: onRight ? .leading : .trailing) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
        }
        .transition(.move(edge: onRight ? .trailing : .leading))
        .onChange(of: model.navigationOrder) { order in
            model.persistNavigationOrder()
        }
    }

    // MARK: - Brand

    private var brand: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            .shadow(color: accent.opacity(0.42), radius: 13, y: 4)

            if !collapsed {
                VStack(spacing: 2) {
                    Text("Game On Launcher")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("JOGOS SEM LIMITES")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.6)
                        .foregroundStyle(Theme.textTertiary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Navigation

    private func navButton(_ page: AppPage) -> some View {
        Button {
            onSelect(page)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                if !collapsed {
                    Text(page.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if page == .server && model.serverController.running {
                        StatusDot(color: Theme.success, pulsing: true, size: 7)
                    }
                }
            }
            .foregroundStyle(model.page == page ? .white : Theme.textSecondary)
            .padding(.horizontal, collapsed ? 0 : 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .background {
                if model.page == page {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(
                            LinearGradient(colors: [accent.opacity(0.85), secondary.opacity(0.65)], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: accent.opacity(0.35), radius: 10, y: 3)
                }
            }
            .overlay(alignment: .leading) {
                if model.page == page && !collapsed {
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 3, height: 18)
                        .offset(x: -9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(page.title)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.page)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Divider().opacity(0.5)

            if !collapsed {
                HStack(spacing: 7) {
                    StatusDot(color: model.connectionOK ? Theme.success : Theme.warning, pulsing: true, size: 7)
                    Text(model.connectionOK ? "Ligação ativa" : "Offline")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 6) {
                IconButton(systemImage: collapsed ? "chevron.right" : "chevron.left", tint: accent, size: 26) {
                    onToggleCollapse()
                }
                .help(collapsed ? "Expandir barra" : "Recolher barra")

                IconButton(systemImage: "arrow.left.arrow.right", tint: accent, size: 26) {
                    onToggleSide()
                }
                .help("Mover barra lateral")
            }
            .padding(.bottom, 14)
        }
    }
}

/// Supports dragging navigation entries to reorder them.
@MainActor
struct SidebarReorderDelegate: DropDelegate {
    let item: AppPage
    @Binding var items: [AppPage]
    @Binding var draggingItem: String?

    func dropEntered(info: DropInfo) {
        guard let draggingItem,
              draggingItem != item.rawValue,
              let from = items.firstIndex(where: { $0.rawValue == draggingItem }),
              let to = items.firstIndex(of: item) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        return true
    }
}
