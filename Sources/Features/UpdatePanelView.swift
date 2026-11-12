import SwiftUI

/// Lets the user check for, download and install a newer build.
struct UpdatePanelView: View {
    @ObservedObject var model: LauncherModel
    var accent: Color

    @State private var checking = false
    @State private var downloading = false
    @State private var progress: Double = 0
    @State private var available: UpdateInfo?
    @State private var status = ""

    var body: some View {
        GlassPanel(accent: accent) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(
                    title: "Atualizações",
                    subtitle: "Versão instalada: \(UpdateService.currentVersion)",
                    systemImage: "arrow.triangle.2.circlepath",
                    accent: accent
                ) {
                    if checking || downloading {
                        ProgressView().controlSize(.small)
                    }
                }

                Text("As atualizações são publicadas em github.com/\(UpdateService.repository) e installadas automaticamente a partir daí.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                if let info = available {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack(spacing: Theme.Space.s) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Theme.success)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Nova versão disponível: \(info.displayVersion)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(info.asset.name) · \(info.sizeLabel)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                        }

                        if downloading {
                            ProgressBar(value: progress, accent: accent)
                            Text("A transferir… \(Int(progress * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            NeonButton(
                                title: "Transferir e instalar",
                                systemImage: "arrow.down.circle.fill",
                                accent: accent,
                                secondary: accent.opacity(0.7),
                                prominent: false
                            ) {
                                install(info)
                            }
                        }
                    }
                    .padding(Theme.Space.m)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                            .fill(Theme.success.opacity(0.10))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                            .strokeBorder(Theme.success.opacity(0.3), lineWidth: 1)
                    }
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack {
                    Button {
                        check()
                    } label: {
                        Label(checking ? "A procurar…" : "Procurar atualizações", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(checking || downloading)

                    if available != nil {
                        GhostButton(title: "Ignorar", systemImage: "xmark", tint: Theme.textSecondary, compact: true) {
                            available = nil
                            status = ""
                        }
                    }

                    Spacer()

                    Link("Ver no GitHub", destination: URL(string: "https://github.com/\(UpdateService.repository)/releases")!)
                        .font(.system(size: 11.5))
                }
            }
        }
    }

    private func check() {
        checking = true
        status = ""
        available = nil
        Task {
            defer { checking = false }
            do {
                if let info = try await UpdateService.check() {
                    available = info
                    status = ""
                } else {
                    status = "A instalação está atualizada."
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    /// Downloads the update and replaces the running application.
    private func install(_ info: UpdateInfo) {
        downloading = true
        progress = 0
        status = "A transferir \(info.asset.name)…"

        Task {
            do {
                let file = try await UpdateService.download(info.asset)
                let installer = try MacInstaller.install(diskImage: file)
                status = "Atualização instalada. A app vai reiniciar."
                model.notify(installer, kind: .success)
                downloading = false
                // Give the banner a moment, then relaunch.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                MacInstaller.restart()
            } catch {
                downloading = false
                status = error.localizedDescription
                model.notify(error.localizedDescription, kind: .error)
            }
        }
    }
}

/// Replaces the running macOS application with a new disk image.
enum MacInstaller {
    /// Mounts the disk image and copies the application over the running one.
    static func install(diskImage: URL) throws -> String {
        let mount = Process()
        mount.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mount.arguments = ["attach", "-nobrowse", "-readonly", "-mountrandom", diskImage.path]
        let pipe = Pipe()
        mount.standardOutput = pipe
        mount.standardError = Pipe()
        try mount.run()
        mount.waitUntilExit()
        guard mount.terminationStatus == 0 else {
            throw UpdateError.installFailed("não foi possível montar o disco.")
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // `hdiutil` prints the mount point on a line of its own.
        let volume = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/Volumes/") } ?? ""
        guard !volume.isEmpty else {
            throw UpdateError.installFailed("não foi possível localizar o disco montado.")
        }

        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", volume, "-quiet"]
            try? detach.run()
            detach.waitUntilExit()
        }

        let source = URL(fileURLWithPath: volume).appendingPathComponent("Game on Launcher.app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw UpdateError.installFailed("o disco não contém a aplicação.")
        }

        let destination = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let target = destination.appendingPathComponent("Game on Launcher.app")
        let backup = destination.appendingPathComponent("Game on Launcher.app.backup")

        // Keep the old version around in case something goes wrong.
        if FileManager.default.fileExists(atPath: target.path) {
            FileHelper.remove(backup)
            try? FileManager.default.moveItem(at: target, to: backup)
        }

        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            // Restore the previous version if the copy failed.
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: target)
            }
            throw UpdateError.installFailed(error.localizedDescription)
        }

        // Refresh the Dock icon so the new bundle is picked up.
        let refresh = Process()
        refresh.executableURL = URL(fileURLWithPath: "/usr/bin/touch")
        refresh.arguments = [target.path]
        try? refresh.run()

        return "A nova versão foi instalada em \(target.path)."
    }

    /// Relaunches the application and closes this one.
    static func restart() {
        let url = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.path]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
    }
}
