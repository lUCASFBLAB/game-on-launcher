import SwiftUI

/// Real log browser for the selected instance.
@MainActor
struct LogsView: View {
    @ObservedObject var model: LauncherModel
    @EnvironmentObject private var preferences: Preferences

    @State private var filePendingDelete: ManagedServerFile?

    private var accent: Color { preferences.tokens.accent }
    private var logs: LogStore { model.logs }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            PageHeader(
                eyebrow: "Diagnóstico",
                title: "Registos",
                subtitle: model.selectedInstance?.name ?? "Nenhuma instância selecionada",
                accent: accent
            ) {
                HStack(spacing: Theme.Space.s) {
                    Toggle("Ao vivo", isOn: Binding(
                        get: { logs.autoRefresh },
                        set: { _ in logs.toggleAutoRefresh() }
                    ))
                    .toggleStyle(.switch)
                    .tint(accent)
                    .font(.system(size: 11.5))

                    GhostButton(title: "Exportar", systemImage: "square.and.arrow.up", tint: accent, compact: true) {
                        if let url = logs.export() {
                            model.notify("Registo exportado para \(url.lastPathComponent).", kind: .success)
                        } else {
                            model.notify("Não foi possível exportar o registo.", kind: .error)
                        }
                    }
                    GhostButton(title: "Copiar", systemImage: "doc.on.doc", tint: accent, compact: true) {
                        logs.copyToPasteboard()
                        model.notify("Registo copiado para a área de transferência.", kind: .success)
                    }
                }
            }

            HStack(alignment: .top, spacing: Theme.Space.m) {
                categorySidebar
                logViewer
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Theme.gutter)
        .onAppear {
            logs.bind(to: model.selectedInstance?.directory)
        }
        .onChange(of: model.selectedInstance?.id) { _ in
            logs.bind(to: model.selectedInstance?.directory)
        }
    }

    // MARK: - Categories

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(LogStore.categories, id: \.self) { category in
                let count = logs.count(for: category)
                Button {
                    logs.select(category: category)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: category == logs.selectedCategory ? "book.fill" : "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 18)
                        Text(category)
                            .font(.system(size: 12, weight: category == logs.selectedCategory ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(category == logs.selectedCategory ? accent : Theme.textTertiary)
                        }
                    }
                    .foregroundStyle(category == logs.selectedCategory ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background {
                        if category == logs.selectedCategory {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .fill(accent.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 210)
        .padding(Theme.Space.s)
        .background {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
    }

    // MARK: - Viewer

    private var logViewer: some View {
        GlassPanel(padding: Theme.Space.m, accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    Text(logs.selectedCategory)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    SearchField(prompt: "Pesquisar no registo", text: searchBinding, accent: accent)
                        .frame(maxWidth: 260)
                }

                if logs.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.text.magnifyingglass",
                        title: "Sem registos",
                        message: "Inicia o jogo ou o servidor para ver os ficheiros de registo em tempo real.",
                        accent: accent
                    )
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(logs.filteredContent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textPrimary.opacity(0.88))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(Theme.Space.m)
                                .id("log-top")
                        }
                        .background {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .fill(Color.black.opacity(0.42))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .strokeBorder(accent.opacity(0.16), lineWidth: 1)
                        }
                        .onChange(of: logs.filteredContent) { _ in
                            withAnimation { proxy.scrollTo("log-top", anchor: .bottom) }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { logs.searchText },
            set: { logs.searchText = $0 }
        )
    }
}
