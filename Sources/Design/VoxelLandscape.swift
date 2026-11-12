import SwiftUI

/// A procedurally drawn blocky landscape used as the hero banner backdrop.
///
/// It mimics the layered, voxel silhouette of the official launcher panorama without
/// depending on any external asset, so it always renders instantly and offline.
struct VoxelLandscape: View {
    var accent: Color
    var secondary: Color
    var seed: UInt64 = 0x5EED

    @State private var time: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                drawSky(context: context, size: size)
                drawSun(context: context, size: size, time: t)
                drawClouds(context: context, size: size, time: t)
                drawHills(context: context, size: size, time: t)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Layers

    private func drawSky(context: GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.055, green: 0.075, blue: 0.145),
                    Color(red: 0.180, green: 0.110, blue: 0.215),
                    Color(red: 0.470, green: 0.220, blue: 0.300),
                    Color(red: 0.760, green: 0.420, blue: 0.320)
                ]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
    }

    private func drawSun(context: GraphicsContext, size: CGSize, time: Double) {
        let radius = size.height * 0.13
        let center = CGPoint(x: size.width * 0.68, y: size.height * 0.44 + sin(time / 6) * 5)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // Glow.
        context.fill(
            Path(ellipseIn: rect.insetBy(dx: -radius * 1.5, dy: -radius * 1.5)),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.40), .clear]),
                center: center,
                startRadius: 0,
                endRadius: radius * 2.4
            )
        )
        // Disc.
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.94, blue: 0.78), Color(red: 0.98, green: 0.78, blue: 0.55)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private func drawClouds(context: GraphicsContext, size: CGSize, time: Double) {
        var generator = SeededGenerator(seed: seed &+ 11)
        for index in 0..<7 {
            let x = Double.random(in: 0...1, using: &generator)
            let y = Double.random(in: 0.05...0.34, using: &generator)
            let scale = Double.random(in: 0.5...1.4, using: &generator)
            let speed = Double.random(in: 8...22, using: &generator)
            let drift = (time / speed + Double(index) * 0.37).truncatingRemainder(dividingBy: 1.4) - 0.2

            let blockSize = max(14.0, size.height * 0.035 * scale)
            let originX = (x + drift) * size.width
            let originY = y * size.height

            // Each cloud is a small cluster of blocks.
            for piece in 0..<5 {
                let offsetX = Double(piece % 3) * blockSize * 1.05
                let offsetY = Double(piece / 3) * blockSize * 0.55
                let rect = CGRect(
                    x: originX + offsetX,
                    y: originY + offsetY,
                    width: blockSize * 1.5,
                    height: blockSize * 0.62
                )
                context.fill(
                    Path(rect),
                    with: .color(Color.white.opacity(0.10))
                )
            }
        }
    }

    private func drawHills(context: GraphicsContext, size: CGSize, time: Double) {
        // Four layers of blocky terrain, from far (light) to near (dark).
        let layers: [(depth: Double, color: Color, cap: Color, base: Double, blocks: Int, height: Double, phase: Double)] = [
            (0.00, Color(red: 0.290, green: 0.231, blue: 0.341), Color(red: 0.357, green: 0.290, blue: 0.420), 0.66, 54, 0.16, 0.0),
            (0.06, Color(red: 0.200, green: 0.165, blue: 0.259), Color(red: 0.259, green: 0.208, blue: 0.310), 0.78, 46, 0.18, 1.4),
            (0.14, Color(red: 0.129, green: 0.114, blue: 0.184), Color(red: 0.173, green: 0.149, blue: 0.224), 0.90, 38, 0.20, 2.7),
            (0.24, Color(red: 0.075, green: 0.067, blue: 0.125), Color(red: 0.106, green: 0.094, blue: 0.188), 1.04, 30, 0.22, 4.1)
        ]

        for layer in layers {
            var generator = SeededGenerator(seed: seed &+ UInt64(layer.blocks))
            let blockWidth = size.width / CGFloat(layer.blocks)
            let baseline = size.height * layer.base

            for index in 0..<layer.blocks {
                // Smooth rolling profile so neighbouring blocks form a continuous ridge.
                let position = Double(index)
                let wave = sin(position * 0.42 + layer.phase) * 0.5
                    + sin(position * 0.17 + layer.phase * 2.3) * 0.32
                    + sin(position * 0.91 + layer.phase * 0.6) * 0.18
                let jitter = (Double.random(in: -0.09...0.09, using: &generator))
                let factor = 0.42 + (wave * 0.5 + 0.5) * 0.62 + jitter
                let blockHeight = size.height * layer.height * factor
                let x = CGFloat(index) * blockWidth

                context.fill(
                    Path(CGRect(x: x, y: baseline - blockHeight, width: blockWidth + 1, height: blockHeight + size.height * 0.3)),
                    with: .color(layer.color)
                )
                // Lighter cap that reads as the top face of the blocks.
                context.fill(
                    Path(CGRect(x: x, y: baseline - blockHeight, width: blockWidth + 1, height: max(1.5, blockHeight * 0.09))),
                    with: .color(layer.cap)
                )
                // Thin seam between blocks.
                context.fill(
                    Path(CGRect(x: x + blockWidth - 1, y: baseline - blockHeight, width: 1, height: blockHeight)),
                    with: .color(Color.black.opacity(0.16))
                )
            }
        }
    }
}

private extension Color {
    /// Returns a lighter variant of the colour.
    func lighter(by amount: Double) -> Color {
        let ui = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.white
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s, brightness: min(1, max(0, b + amount)), opacity: a)
    }
}
