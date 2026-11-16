import SwiftUI

/// "All styles": every style as a tile, in one adaptive grid under the hero.
struct GalleryShelf: View {
    private enum Metrics {
        static let tileWidth: ClosedRange<CGFloat> = 232...380
        static let columnSpacing: CGFloat = 22
        static let rowSpacing: CGFloat = 28
    }

    @ObservedObject var model: GalleryModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var stills: StyleStills
    let onPick: (LyricStyle) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: Metrics.tileWidth.lowerBound, maximum: Metrics.tileWidth.upperBound),
                                spacing: Metrics.columnSpacing)]
        VStack(alignment: .leading, spacing: 18) {
            Text("All styles").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
                ForEach(LyricStyle.allCases, id: \.self) { style in
                    GalleryTile(style: style, still: stills.images[style], browsed: model.browsed == style,
                                inUse: settings.style == style, pinned: settings.pinnedStyles.contains(style),
                                stillOnly: model.tilesStillOnly, hover: model.hover, settings: settings,
                                action: { onPick(style) }, onPin: { settings.togglePin(style) })
                }
            }
            CreditLine(hover: model.hover).padding(.top, 14)
        }
        .padding(.horizontal, 44)
        .padding(.top, 26)
        .padding(.bottom, 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
    }
}

/// One style on the shelf: a still picture that starts playing when the pointer rests on it.
struct GalleryTile: View {
    private enum Metrics {
        static let aspect: CGFloat = 1.6
        static let corner: CGFloat = 20
        static let badgeHeight: CGFloat = 22
        static let inset: CGFloat = 10
    }

    let style: LyricStyle
    let still: CGImage?
    let browsed: Bool
    let inUse: Bool
    let pinned: Bool
    let stillOnly: Bool
    @ObservedObject var hover: GalleryHover
    let settings: AppSettings
    let action: () -> Void
    let onPin: () -> Void

    var body: some View {
        let hovered = hover.tile == style
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                picture(playing: hover.playingTile == style && !stillOnly)
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.rawValue).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                    Text(style.category).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                .padding(.leading, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if hovered || pinned {
                PinButton(pinned: pinned, size: PinButton.tileSize, action: onPin).padding(Metrics.inset).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onHover { hover.setTile(style, hovered: $0) }
        .accessibilityLabel("\(style.rawValue), \(style.category)")
        .accessibilityHint(style.summary)
    }

    private func picture(playing: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
        return style.placeholderColor
            .aspectRatio(Metrics.aspect, contentMode: .fit)
            .overlay {
                if let still {
                    Image(decorative: still, scale: StyleStills.scale).resizable().interpolation(.high).transition(.opacity)
                }
            }
            .overlay {
                if playing {
                    GeometryReader { geometry in
                        TileScene(demo: StyleDemo(style: style, playingSince: hover.playingSince), size: geometry.size, settings: settings)
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(browsed ? 0.9 : 0.1), lineWidth: browsed ? 1.5 : 1))
            .overlay(alignment: .topTrailing) { if inUse { inUseBadge } }
            .animation(.easeOut(duration: 0.2), value: browsed)
            .animation(.easeOut(duration: 0.25), value: playing)
    }

    private var inUseBadge: some View {
        Label("Selected", systemImage: "checkmark")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .frame(height: Metrics.badgeHeight)
            .background(Color.white, in: Capsule())
            .padding(Metrics.inset)
    }
}
