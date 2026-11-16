import SwiftUI

/// Under the hero: the favourites (the styles the menu bar menu lists), then every style, as tiles in adaptive grids.
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
        let favourites = LyricStyle.allCases.filter(settings.favouriteStyles.contains)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Favourites").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                Text(favourites.isEmpty
                     ? "Star a style to add it here. Favourites are what the menu bar menu shows."
                     : "These are the styles in your menu bar menu.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            }
            if !favourites.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
                    ForEach(favourites, id: \.self) { tile($0, playable: true) }
                }
            }
            Text("All styles").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).padding(.top, 18)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Metrics.rowSpacing) {
                // A favourite plays in its Favourites tile only, not twice at once.
                ForEach(LyricStyle.allCases, id: \.self) { tile($0, playable: !settings.favouriteStyles.contains($0)) }
            }
            CreditLine(hover: model.hover).padding(.top, 14)
        }
        .padding(.horizontal, 44)
        .padding(.top, 26)
        .padding(.bottom, 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black)
    }

    private func tile(_ style: LyricStyle, playable: Bool) -> some View {
        GalleryTile(style: style, still: stills.images[style], browsed: model.browsed == style,
                    inUse: settings.style == style, pinned: settings.favouriteStyles.contains(style),
                    stillOnly: model.tilesStillOnly || !playable, hover: model.hover, settings: settings,
                    action: { onPick(style) }, onPin: { settings.toggleFavourite(style) }, live: model.live)
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
    var live: LivePreviewSource?

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
                FavouriteButton(pinned: pinned, size: FavouriteButton.tileSize, action: onPin).padding(Metrics.inset).transition(.opacity)
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
                        TileScene(demo: StyleDemo(style: style, playingSince: hover.playingSince), size: geometry.size, settings: settings,
                                  live: live)
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
