import SwiftUI

// MARK: - Glass surfaces

/// Frosted panel with a hairline border and an accent-aware top highlight.
@MainActor
struct GlassPanel<Content: View> : View {
    var padding: CGFloat = Theme.Space.l
    var radius: CGFloat = Theme.panelRadius
    var accent: Color = Theme.accents[0].primary
    var elevated: Bool = false
    var glow: Bool = false
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(scheme == .dark ? 0.07 : 0.9),
                                        Color.white.opacity(scheme == .dark ? 0.02 : 0.55)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(elevated ? 0.55 : 0.28),
                                Color.white.opacity(scheme == .dark ? 0.10 : 0.35),
                                accent.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: elevated ? 1.4 : 1
                    )
            }
            .shadow(color: glow ? accent.opacity(0.28) : .black.opacity(scheme == .dark ? 0.35 : 0.10), radius: glow ? 22 : 12, x: 0, y: glow ? 10 : 6)
    }
}

/// Compact frosted chip used for metadata rows.
@MainActor
struct GlassChip : View {
    var text: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(filled ? tint : Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(tint.opacity(filled ? 0.16 : 0.10))
        }
        .overlay { Capsule().strokeBorder(tint.opacity(filled ? 0.35 : 0.16), lineWidth: 1) }
    }
}

// MARK: - Typography

/// Section title with an optional subtitle and trailing accessory.
@MainActor
struct SectionHeader<Accessory: View> : View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var accent: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(accent.opacity(0.14))
                    }
                    .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(accent.opacity(0.25), lineWidth: 1) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .bold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: Theme.Space.m)
            accessory
        }
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, systemImage: String? = nil, accent: Color) {
        self.init(title: title, subtitle: subtitle, systemImage: systemImage, accent: accent) { EmptyView() }
    }
}

/// Big page heading used at the top of every screen.
@MainActor
struct PageHeader<Trailing: View> : View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var accent: Color
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .heavy))
                    .tracking(2.2)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Space.l)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String, accent: Color) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, accent: accent) { EmptyView() }
    }
}

// MARK: - Buttons

/// Primary call-to-action button with a gradient fill and glow.
@MainActor
struct NeonButton : View {
    var title: String
    var systemImage: String?
    var accent: Color
    var secondary: Color
    var prominent: Bool = true
    var busy: Bool = false
    var compact: Bool = false
    /// When `false` the button uses a flat accent fill instead of a gradient.
    var gradient: Bool = true
    var action: @MainActor () -> Void

    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: compact ? 12 : 14, weight: .bold))
                }
                Text(title)
                    .font(.system(size: compact ? 12 : 14, weight: .bold))
                    .tracking(compact ? 0.3 : 0.8)
            }
            .foregroundStyle(prominent ? .white : accent)
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: prominent ? .infinity : nil)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(
                            gradient
                                ? AnyShapeStyle(LinearGradient(colors: [accent, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(accent)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .fill(
                                    LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
                                )
                        }
                } else {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .fill(accent.opacity(hovering ? 0.18 : 0.10))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(accent.opacity(prominent ? 0.0 : (hovering ? 0.55 : 0.30)), lineWidth: 1)
            }
            .shadow(color: prominent ? accent.opacity(hovering ? 0.55 : 0.35) : .clear, radius: prominent ? (hovering ? 20 : 14) : 0, y: prominent ? 6 : 0)
            .scaleEffect(pressed ? 0.97 : (hovering ? 1.015 : 1))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .onHover { hovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

/// Secondary action button with a subtle frosted fill.
@MainActor
struct GhostButton : View {
    var title: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary
    var destructive: Bool = false
    var compact: Bool = false
    var action: @MainActor () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: compact ? 11 : 12, weight: .semibold)) }
                if !title.isEmpty { Text(title).font(.system(size: compact ? 11.5 : 12.5, weight: .semibold)) }
            }
            .foregroundStyle(destructive ? Theme.danger : (hovering ? tint : Theme.textSecondary))
            .padding(.horizontal, compact ? 9 : 13)
            .padding(.vertical, compact ? 5 : 7)
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill((destructive ? Theme.danger : tint).opacity(hovering ? 0.16 : 0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .strokeBorder((destructive ? Theme.danger : tint).opacity(hovering ? 0.45 : 0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Circular icon-only button.
@MainActor
struct IconButton : View {
    var systemImage: String
    var tint: Color = Theme.textSecondary
    var size: CGFloat = 30
    var help: String = ""
    var action: @MainActor () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(hovering ? tint : Theme.textSecondary)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .fill(tint.opacity(hovering ? 0.18 : 0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(tint.opacity(hovering ? 0.5 : 0.16), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(help)
    }
}

// MARK: - Form controls

/// Styled text field used across forms.
@MainActor
struct FormTextField : View {
    var prompt: String
    @Binding var text: String
    var accent: Color = Theme.accents[0].primary

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.05)) }
            .overlay { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }
    }
}

/// Secure text field with the same styling as `FormTextField`.
@MainActor
struct FormSecureField : View {
    var prompt: String
    @Binding var text: String

    var body: some View {
        SecureField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.05)) }
            .overlay { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }
    }
}

/// Segmented picker with a modern look.
@MainActor
struct SegmentBar<Value: Hashable> : View {
    var options: [(value: Value, label: String, systemImage: String?)]
    @Binding var selection: Value
    var accent: Color
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { selection = option.value }
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = option.systemImage {
                            Image(systemName: systemImage).font(.system(size: 10.5, weight: .bold))
                        }
                        Text(option.label).font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(selection == option.value ? .white : Theme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background {
                        if selection == option.value {
                            Capsule()
                                .fill(LinearGradient(colors: [accent, accent.opacity(0.72)], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: accent.opacity(0.4), radius: 7, y: 2)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background { Capsule().fill(Color.white.opacity(0.05)) }
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
    }
}

/// Slider row with a value readout.
@MainActor
struct MetricSlider : View {
    var label: String
    var systemImage: String?
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var accent: Color
    var step: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10.5, weight: .bold)).foregroundStyle(accent) }
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background { Capsule().fill(accent.opacity(0.14)) }
            }
            Slider(value: $value, in: range, step: step)
                .tint(accent)
        }
    }
}

/// Toggle row with description.
@MainActor
struct SettingToggle : View {
    var title: String
    var subtitle: String?
    var systemImage: String?
    var accent: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: Theme.Space.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 24, height: 24)
                        .background { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.opacity(0.13)) }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .tint(accent)
    }
}

// MARK: - Status

/// Coloured status dot with pulsing animation.
@MainActor
struct StatusDot : View {
    var color: Color
    var pulsing: Bool = false
    var size: CGFloat = 8

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: pulsing ? 6 : 3)
            .scaleEffect(pulsing ? (on ? 1.25 : 0.85) : 1)
            .animation(pulsing ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { if pulsing { on = true } }
    }
}

/// Horizontal progress bar.
@MainActor
struct ProgressBar : View {
    var value: Double
    var accent: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .shadow(color: accent.opacity(0.5), radius: 4)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: value)
    }
}

/// Empty state placeholder.
@MainActor
struct EmptyStateView : View {
    var systemImage: String
    var title: String
    var message: String
    var accent: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(accent.opacity(0.65))
                .frame(width: 72, height: 72)
                .background { Circle().fill(accent.opacity(0.10)) }
                .overlay { Circle().strokeBorder(accent.opacity(0.20), lineWidth: 1) }
            VStack(spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            if let actionTitle, let action {
                NeonButton(title: actionTitle, systemImage: "plus", accent: accent, secondary: accent.opacity(0.7), prominent: false, compact: true, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }
}

/// Animated inline banner for status messages.
@MainActor
struct StatusBanner : View {
    enum Kind { case info, success, warning, error }
    var kind: Kind
    var message: String
    var accent: Color

    private var tint: Color {
        switch kind {
        case .info: return accent
        case .success: return Theme.success
        case .warning: return Theme.warning
        case .error: return Theme.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(tint.opacity(0.10)) }
        .overlay { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1) }
    }
}

/// Monospaced console/log surface.
@MainActor
struct ConsoleSurface : View {
    var text: String
    var accent: Color
    var minHeight: CGFloat = 200

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "Sem saída." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Theme.Space.m)
            }
            .background {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .fill(Color.black.opacity(0.42))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous)
                    .strokeBorder(accent.opacity(0.16), lineWidth: 1)
            }
            .frame(minHeight: minHeight)
            .onChange(of: text) { _ in
                proxy.scrollTo(0, anchor: .bottom)
            }
        }
    }
}

/// Simple searchable list container.
@MainActor
struct SearchField : View {
    var systemImage: String = "magnifyingglass"
    var prompt: String
    @Binding var text: String
    var accent: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent.opacity(0.85))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).fill(Color.white.opacity(0.05)) }
        .overlay { RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1) }
    }
}
