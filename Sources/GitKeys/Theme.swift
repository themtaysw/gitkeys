import SwiftUI

// MARK: - GitKeys design tokens
//
// Shared design system for the GitKeys "ultra-modern" re-skin.
// Everything here targets the macOS 13.0 API floor — no macOS 14+ APIs.

enum GK {
    /// Brand indigo — #6366F1.
    static let accentColor = Color(red: 0.39, green: 0.40, blue: 0.95)
    /// Brand cyan — #22D3EE.
    static let accentCyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    /// Signature indigo-to-cyan gradient used for primary buttons, badges and glows.
    static let accentGradient = LinearGradient(
        colors: [accentColor, accentCyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    /// Corner radius for cards.
    static let cardCorner: CGFloat = 14
    /// Standard page content padding.
    static let pagePadding: CGFloat = 28
    /// Standard spring used for state-change animations. Always bind it to a
    /// value (`.animation(GK.spring, value: state)` / `withAnimation(GK.spring)`).
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - Card container

extension View {
    /// Wraps the view in a glassy material card: rounded 14pt corners,
    /// hairline stroke and a soft drop shadow.
    func gkCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: GK.cardCorner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GK.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Primary button

/// Gradient-filled primary action button. White semibold label, rounded 10pt
/// corners, subtle glow, press scale and hover brighten.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GK.accentGradient)
                    .shadow(color: GK.accentColor.opacity(isEnabled ? 0.35 : 0),
                            radius: hovering ? 8 : 5, x: 0, y: 2)
            )
            .brightness(hovering && isEnabled ? 0.07 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(GK.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var gkPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

// MARK: - Busy button label

/// Label for a busy-capable action button. While `isBusy` is true the normal
/// label is hidden (but keeps its size, so the button doesn't collapse) and a
/// small spinner is shown instead. The spinner is forced into dark mode so it
/// renders white and stays visible on the `.gkPrimary` gradient in light mode.
struct GKBusyLabel<Content: View>: View {
    let isBusy: Bool
    private let content: Content

    init(isBusy: Bool, @ViewBuilder content: () -> Content) {
        self.isBusy = isBusy
        self.content = content()
    }

    var body: some View {
        ZStack {
            content.opacity(isBusy ? 0 : 1)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}

// MARK: - Secondary button

/// Quiet secondary button: quaternary fill, primary label, same geometry as
/// the primary style so the two sit side by side cleanly.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering && isEnabled
                          ? AnyShapeStyle(.tertiary.opacity(0.6))
                          : AnyShapeStyle(.quaternary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(GK.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var gkSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Destructive button

/// Destructive action button: same 10pt-radius / 16x8 geometry as the other
/// GK styles, but with a red tinted fill, stroke and label.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DestructiveButtonBody(configuration: configuration)
    }
}

private struct DestructiveButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.red.opacity(hovering && isEnabled ? 0.18 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(GK.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var gkDestructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}

// MARK: - Section header

/// Gradient icon tile + rounded bold title with an optional secondary subtitle.
struct SectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    init(icon: String, title: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GK.accentGradient)
                    .shadow(color: GK.accentColor.opacity(0.35), radius: 5, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Step badge

/// 28pt numbered circle for wizard steps. Gradient-filled; shows a checkmark
/// once the step is done.
struct StepBadge: View {
    let number: Int
    let done: Bool

    init(number: Int, done: Bool = false) {
        self.number = number
        self.done = done
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(GK.accentGradient)
                .shadow(color: GK.accentColor.opacity(0.4), radius: 4, x: 0, y: 2)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
        .animation(GK.spring, value: done)
    }
}

// MARK: - Icon tile

/// 26x26 colored rounded tile with a white SF Symbol — System Settings
/// sidebar style.
struct IconTile: View {
    let systemName: String
    let color: Color

    init(systemName: String, color: Color) {
        self.systemName = systemName
        self.color = color
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(colors: [color.opacity(0.85), color],
                                   startPoint: .top, endPoint: .bottom)
                )
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Status banner

/// Capsule status message with a success / error icon on a tinted material
/// background. Pairs well with a spring transition when inserted/removed.
struct StatusBanner: View {
    let text: String
    let isError: Bool

    init(text: String, isError: Bool) {
        self.text = text
        self.isError = isError
    }

    private var tint: Color { isError ? .red : .green }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
                Capsule(style: .continuous).fill(tint.opacity(0.12))
            }
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}

// MARK: - Empty state

/// Centered placeholder for empty lists: large hierarchical symbol + message.
struct EmptyStateView: View {
    let icon: String
    let message: String

    init(icon: String, message: String) {
        self.icon = icon
        self.message = message
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
