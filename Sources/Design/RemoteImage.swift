import SwiftUI

/// Downloads and caches remote images for the news feed.
actor ImageLoader {
    static let shared = ImageLoader()

    private var cache: [URL: NSImage] = [:]
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    /// Returns a cached image, downloading it when needed.
    func image(for url: URL) async -> NSImage? {
        if let cached = cache[url] { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task<NSImage?, Never> {
            var request = URLRequest(url: url)
            request.setValue("GameOnLauncher/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 25
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data) else { return nil }
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache[url] = result }
        return result
    }
}

/// Renders a remote image with a graceful placeholder.
struct RemoteImage<Placeholder: View>: View {
    var url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ImageLoader.shared.image(for: url)
        }
    }
}

extension RemoteImage where Placeholder == AnyView {
    /// Convenience initialiser with a built-in shimmer placeholder.
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, contentMode: contentMode) {
            AnyView(
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.06))
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                }
            )
        }
    }
}
