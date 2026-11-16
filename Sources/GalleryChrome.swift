import SwiftUI

// The window's shared look: glass surfaces, the five button styles, and the small controls built from them.

private struct FlatGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Draw glass surfaces as flat grey. For the offscreen render tool only: a bitmap of a window that is
    /// not on screen cannot capture glass or materials, and the surfaces would simply be missing.
    var flatGlass: Bool {
        get { self[FlatGlassKey.self] }
        set { self[FlatGlassKey.self] = newValue }
    }
}

/// Liquid glass where the system has it, a thin material with a hairline edge where it does not.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    @Environment(\.flatGlass) private var flat

    func body(content: Content) -> some View {
        if flat {
            content
                .background(Color(white: 0.2).opacity(0.86), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background(tint ?? .clear, in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

/// The shape and type of the large capsule buttons.
struct PillLabel: ViewModifier {
    static let height: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .frame(height: Self.height)
    }
}

/// White content that dims while pressed; for the bare chevrons.
struct FadeButtonStyle: ButtonStyle {
    let rest: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white).opacity(configuration.isPressed ? rest * 0.55 : rest)
    }
}

struct GlassPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillLabel())
            .foregroundStyle(.white)
            .modifier(GlassSurface(shape: Capsule()))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct PrimaryPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PillLabel())
            .foregroundStyle(.black)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// The small grey capsule used inside panels (Reset and the player fixes).
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.35))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Color.white.opacity(configuration.isPressed ? 0.2 : enabled ? 0.12 : 0.05), in: Capsule())
                .contentShape(Capsule())
        }
    }
}

/// A bare icon that shrinks a touch when pressed and fades when it cannot be used.
struct DimWhenDisabledStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }

    private struct Face: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

/// Tells its content whether the pointer is over it, through the shared hover model.
struct Hoverable<Content: View>: View {
    let id: String
    @ObservedObject var hover: GalleryHover
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(hover.control == id).onHover { hover.setControl(id, hovered: $0) }
    }
}

/// Where each button of the bottom bar is, so its panel can unfold from it.
struct MenuButtonBounds: PreferenceKey {
    static let defaultValue: [GalleryMenu: SwiftUI.Anchor<CGRect>] = [:]

    static func reduce(value: inout [GalleryMenu: SwiftUI.Anchor<CGRect>], nextValue: () -> [GalleryMenu: SwiftUI.Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A text button in the bottom bar that opens a panel.
struct MenuButton: View {
    static let height: CGFloat = 30

    let title: String
    let isOpen: Bool
    let hover: GalleryHover
    let action: () -> Void

    var body: some View {
        Hoverable(id: "menu.\(title)", hover: hover) { hovered in
            Button(action: action) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isOpen || hovered ? 1 : 0.8))
                    .padding(.horizontal, 13)
                    .frame(height: Self.height)
                    .background(Color.white.opacity(isOpen ? 0.18 : hovered ? 0.08 : 0), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        }
    }
}

/// One selectable line in a panel.
struct PanelRow<Content: View>: View {
    let id: String
    var selected = false
    let hover: GalleryHover
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Hoverable(id: "row.\(id)", hover: hover) { hovered in
            Button(action: action) {
                HStack(spacing: 8) { content() }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(selected ? 0.16 : hovered ? 0.08 : 0),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// A titled switch with a line of explanation under the title.
struct SettingSwitch: View {
    let title: String
    var detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Without this the text and the spacer split the row evenly and the detail wraps early.
            .layoutPriority(1)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PanelRule: View {
    var body: some View { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
}

/// The small print at the foot of a panel.
struct PanelNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }
}

/// Stars a style as a favourite, or unstars it; favourites are what the menu bar menu lists.
struct FavouriteButton: View {
    static let tileSize: CGFloat = 28
    static let heroSize: CGFloat = 44
    private static let glyphScale = 0.42

    let pinned: Bool
    let size: CGFloat
    var glass = false
    let action: () -> Void

    var body: some View {
        let title = pinned ? "Remove from Favourites" : "Add to Favourites (they show in the menu bar menu)"
        Button(action: action) {
            Image(systemName: pinned ? "star.fill" : "star")
                .font(.system(size: size * Self.glyphScale, weight: .semibold))
                .foregroundStyle(pinned ? .black : .white)
                .frame(width: size, height: size)
                .background { backing }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(pinned ? .isSelected : [])
    }

    @ViewBuilder private var backing: some View {
        if pinned {
            Circle().fill(.white)
        } else if glass {
            Color.clear.modifier(GlassSurface(shape: Circle()))
        } else {
            Circle().fill(.black.opacity(0.55)).overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
        }
    }
}
