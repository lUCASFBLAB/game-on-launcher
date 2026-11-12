import SwiftUI
import UniformTypeIdentifiers

/// Lets the user pick a skin by nickname or import a PNG file.
struct SkinPickerView: View {
    @ObservedObject var model: LauncherModel
    var accent: Color

    @State private var nickname = ""
    @State private var showImporter = false

    private var store: SkinStore { model.skins }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                FormTextField(prompt: "Nickname do jogador", text: $nickname, accent: accent)

                Button {
                    Task { await store.fetch(byNickname: nickname) }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                                .fill(accent.opacity(0.85))
                        }
                }
                .buttonStyle(.plain)
                .disabled(store.loading)
                .help("Procurar a skin oficial")
            }

            HStack(spacing: Theme.Space.s) {
                Button {
                    showImporter = true
                } label: {
                    Label("Importar PNG", systemImage: "photo.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)

                if store.skin?.localFile != nil, case .signedIn(let profile) = model.accountState {
                    Button {
                        Task {
                            let ok = await store.uploadToAccount(accessToken: profile.accessToken)
                            model.notify(store.status, kind: ok ? .success : .error)
                        }
                    } label: {
                        Label("Enviar para a conta", systemImage: "arrow.up.circle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                if store.skin != nil {
                    Button {
                        store.clear()
                    } label: {
                        Label("Remover", systemImage: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.danger)
                }

                Spacer()
            }

            if store.loading {
                ProgressView("A carregar…").font(.system(size: 11.5))
            }

            Text(store.status).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)

            if let skin = store.skin {
                SkinPreview(skin: skin)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.png],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    store.importPNG(url)
                }
            case .failure(let error):
                model.notify("Não foi possível abrir a imagem: \(error.localizedDescription)", kind: .error)
            }
        }
    }
}

/// Draws the 64×64 skin sheet with the player head cut out.
struct SkinPreview: View {
    var skin: SkinProfile
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                if let image {
                    // The head occupies the 8×8 region at (8, 8) of the 64×64 sheet.
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .offset(x: -9, y: -9)
                        .scaleEffect(4)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(skin.name).font(.system(size: 13, weight: .semibold))
                Text(skin.slim ? "Modelo slim (Alex)" : "Modelo padrão (Steve)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Space.s)
        .background {
            RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                .fill(Color.white.opacity(0.035))
        }
        .task(id: skin.id) { await load() }
    }

    private func load() async {
        if let localFile = skin.localFile {
            image = NSImage(contentsOf: localFile)
            return
        }
        guard let url = skin.imageURL else { return }
        var request = URLRequest(url: url)
        request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            image = NSImage(data: data)
        }
    }
}
