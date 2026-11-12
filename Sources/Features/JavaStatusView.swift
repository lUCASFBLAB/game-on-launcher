import SwiftUI

/// Shows the Java runtimes detected on the machine and lets the user pick one.
///
/// The Minecraft version decides which Java is required: Java 21 from 1.20.5 and
/// Java 17 from 1.17. A runtime that is too old makes the game fail with
/// `UnsupportedClassVersionError`.
struct JavaStatusView: View {
    var accent: Color
    /// The Minecraft version whose requirement is highlighted.
    var minecraftVersion: String = ""

    @State private var detected: String?
    @State private var version: String?
    @State private var required: Int = 17
    @State private var runtimes: [JavaLocator.Runtime] = []
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: detected == nil ? "exclamationmark.triangle.fill" : statusIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusTint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(detected ?? "Nenhum Java encontrado")
                        .font(.system(size: 12.5, weight: .medium))
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                Button {
                    showPicker = true
                } label: {
                    Text("Escolher…").font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }

            if !runtimes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(runtimes, id: \.javaHome) { runtime in
                        let suitable = runtime.majorVersion >= required
                        GlassChip(
                            text: "Java \(runtime.majorVersion)",
                            systemImage: suitable ? "checkmark.circle.fill" : "xmark.circle.fill",
                            tint: suitable ? Theme.success : Theme.warning,
                            filled: suitable
                        )
                    }
                }
            }
        }
        .onAppear(perform: detect)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.unixExecutable, .executable, .item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                UserDefaults.standard.set(url.path, forKey: "gameOnLauncherJavaPath")
                JavaLocator.shared.invalidate()
                detect()
            }
        }
    }

    private var statusIcon: String {
        detected == nil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var statusTint: Color {
        detected == nil ? Theme.warning : Theme.success
    }

    private var detail: String {
        guard detected != nil else {
            return "Instala o Java \(required) ou superior para jogar."
        }
        if let version {
            return "Java \(version) · \(detected ?? "")"
        }
        return detected ?? ""
    }

    private func detect() {
        required = minecraftVersion.isEmpty
            ? 17
            : JavaLocator.requiredJavaVersion(for: minecraftVersion)
        runtimes = JavaLocator.shared.installedRuntimes()
        detected = JavaLocator.shared.locate(minimumMajor: required)?.path
        version = JavaLocator.shared.version(minimumMajor: required)
    }
}
