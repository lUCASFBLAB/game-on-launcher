import SwiftUI
import AVFoundation
import AppKit

// MARK: - Ambient nebula

/// Slow-moving nebula blobs that give the launcher its futuristic depth.
@MainActor
struct NebulaBackground : View {
    var accent: Color
    var secondary: Color
    var isDark: Bool

    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Theme.void, Theme.abyss, Color(red: 0.055, green: 0.043, blue: 0.094)]
                    : [Color(red: 0.965, green: 0.969, blue: 0.980), Color(red: 0.925, green: 0.941, blue: 0.965), Color(red: 0.945, green: 0.933, blue: 0.957)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if isDark {
                blob(accent, size: 640, x: -210, y: -280, speed: 13, phase: 0)
                blob(secondary, size: 540, x: 280, y: 140, speed: 17, phase: 1.9)
                blob(accent.opacity(0.5), size: 470, x: 60, y: 340, speed: 21, phase: 3.4)
            } else {
                blob(accent.opacity(0.14), size: 620, x: -180, y: -260, speed: 13, phase: 0)
                blob(secondary.opacity(0.12), size: 520, x: 260, y: 120, speed: 17, phase: 1.9)
            }

            // Soft vignette that keeps the edges calm and the centre readable.
            RadialGradient(
                colors: [.clear, Color.black.opacity(0.34)],
                center: .center,
                startRadius: 120,
                endRadius: 720
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
        .onAppear { animate = true }
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat, speed: Double, phase: Double) -> some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSince1970
                let dx = sin(t / speed + phase) * 46
                let dy = cos(t / (speed * 1.3) + phase) * 38
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(isDark ? 0.24 : 0.13), color.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)
                    .blur(radius: 60)
                    .position(
                        x: geo.size.width * 0.5 + x + dx,
                        y: geo.size.height * 0.5 + y + dy
                    )
            }
        }
    }
}

// MARK: - Perspective grid

/// Faint perspective grid that reads as a "holographic floor".
@MainActor
struct GridOverlay : View {
    var accent: Color
    var opacity: Double = 0.16
    var scrollOffset: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let columns = 26
            let rows = 16
            let horizon = size.height * 0.42

            for column in 0...columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                var path = Path()
                path.move(to: CGPoint(x: size.width / 2, y: horizon))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(accent.opacity(opacity * 0.75)), lineWidth: 0.6)
            }

            for row in 0...rows {
                let progress = CGFloat(row) / CGFloat(rows)
                let eased = pow(progress, 2.1)
                var y = horizon + (size.height - horizon) * eased
                y = y.truncatingRemainder(dividingBy: 26)
                if y < horizon { y += 26 }
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(accent.opacity(opacity * (1 - progress * 0.55))), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
        .mask {
            LinearGradient(colors: [.clear, .black.opacity(0.25), .black], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Starfield

/// Slow drifting particles for depth.
@MainActor
struct Starfield : View {
    var accent: Color
    var count: Int = 42
    var seed: UInt64 = 0xC0FFEE

    struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let speed: Double
        let phase: Double
        let opacity: Double
    }

    private var particles: [Particle] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            Particle(
                id: index,
                x: CGFloat.random(in: 0...1, using: &generator),
                y: CGFloat.random(in: 0...1, using: &generator),
                size: CGFloat.random(in: 0.8...2.4, using: &generator),
                speed: Double.random(in: 9...26, using: &generator),
                phase: Double.random(in: 0...6.28, using: &generator),
                opacity: Double.random(in: 0.14...0.55, using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince1970
                for particle in particles {
                    let drift = sin(t / particle.speed + particle.phase) * 0.012
                    let x = (particle.x + drift) * size.width
                    let y = particle.y * size.height
                    let rect = CGRect(x: x, y: y, width: particle.size, height: particle.size)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(accent.opacity(particle.opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Scanline sheen

/// Very subtle moving sheen that suggests an active display.
@MainActor
struct ScanSheen : View {
    var accent: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let t = timeline.date.timeIntervalSince1970
            let progress = (t.truncatingRemainder(dividingBy: 7.0)) / 7.0
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, accent.opacity(0.055), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.55)
                .offset(y: progress * geo.size.height * 1.6 - geo.size.height * 0.2)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Video background

/// Looping background video backed by an `AVPlayerLayer`.
@MainActor
struct LoopingVideoBackground : NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = PlayerHostView()
        view.wantsLayer = true
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer = playerLayer
        view.layer = playerLayer
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let host = view as? PlayerHostView else { return }
        if host.playerLayer.player !== player {
            host.playerLayer.player = player
        }
    }

    final class PlayerHostView: NSView {
        var playerLayer: AVPlayerLayer!

        override func layout() {
            super.layout()
            // AVPlayerLayer does not auto-resize with the layer bounds on all macOS versions.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Deterministic pseudo random generator so the star field is stable between frames.
struct SeededGenerator : RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6364136223846793005 &+ 1442695040888963407
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
