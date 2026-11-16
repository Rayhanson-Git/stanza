import SwiftUI

/// Where the big preview sits in the hero. The preview is a whole virtual screen, placed so that only its
/// lyric band lands in the free area between the top bar and the text block.
struct HeroGeometry: Equatable {
    static let topClearance: CGFloat = 86
    static let textBlock: CGFloat = 156
    static let textGap: CGFloat = 24
    static let bottomPadding: CGFloat = 52
    static let minFreeHeight: CGFloat = 120
    /// The windowed map draws a little past the band, so it gets a slightly smaller one.
    static let windowedMapShrink: CGFloat = 1.12
    static let maxAspect: CGFloat = 1.6

    /// On-screen height of the virtual screen.
    let screenHeight: CGFloat
    let offsetY: CGFloat
    /// Shown as a framed screen (the map taking over the display) instead of floating lyrics.
    let framed: Bool

    init(heroHeight: CGFloat, style: LyricStyle, mapFillsDisplay: Bool) {
        let free = max(heroHeight - Self.bottomPadding - Self.textBlock - Self.textGap - Self.topClearance, Self.minFreeHeight)
        framed = style == .map && mapFillsDisplay
        guard !framed else {
            screenHeight = free
            offsetY = Self.topClearance
            return
        }
        let band = style == .map ? free / Self.windowedMapShrink : free
        screenHeight = band / Layout.bandHeight
        offsetY = (free - band) / 2 + Self.topClearance - Layout.bandTop * screenHeight
    }
}

/// Rounds and outlines the preview when it stands for a whole display.
private struct ScreenEdge: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            content
                .clipShape(shape)
                .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
        } else {
            content
        }
    }
}

/// The backdrop and live preview of the browsed style. Fixed behind the scroll view; never takes clicks.
struct GalleryHeroStage: View {
    @ObservedObject var model: GalleryModel
    @ObservedObject var settings: AppSettings
    let size: CGSize

    var body: some View {
        let style = model.browsed
        let width = size.width - (model.menu?.hangsFromBottomBar == false ? GalleryPanel.inset : 0)
        let geometry = HeroGeometry(heroHeight: size.height, style: style, mapFillsDisplay: settings.mapFillsDisplay)
        let stage = CGSize(width: min(width, geometry.screenHeight * HeroGeometry.maxAspect), height: geometry.screenHeight)
        ZStack(alignment: .topLeading) {
            StyleBackdrop(style: style)
                .frame(width: size.width, height: size.height)
                .id(style)
                .transition(.opacity)
            LinearGradient(stops: [.init(color: .black.opacity(0.34), location: 0), .init(color: .clear, location: 0.2),
                                   .init(color: .clear, location: 0.42), .init(color: .black.opacity(0.45), location: 0.7),
                                   .init(color: .black.opacity(0.7), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            StyleStage(demo: model.heroDemo, size: stage, screenHeight: StyleStage.heroScreenHeight, settings: settings, live: model.live)
                .modifier(ScreenEdge(on: geometry.framed))
                .frame(width: width, alignment: .top)
                .offset(y: geometry.offsetY)
                .id(style)
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: style)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Everything clickable on top of the hero: chevrons, the name block with its buttons, and the page dots.
struct GalleryHeroControls: View {
    private enum Metrics {
        static let chevron = CGSize(width: 48, height: 76)
        static let chevronLift = 0.04
        static let sidePadding: CGFloat = 56
        static let dot: CGFloat = 6
        static let dotCell = CGSize(width: 12, height: 20)
    }

    @ObservedObject var model: GalleryModel
    @ObservedObject var settings: AppSettings
    let size: CGSize

    var body: some View {
        let style = model.browsed
        ZStack {
            LinearGradient(stops: [.init(color: .clear, location: 0.58), .init(color: .black.opacity(0.6), location: 0.82),
                                   .init(color: .black, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            chevrons
            textBlock(style)
                .id(style)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.horizontal, Metrics.sidePadding)
                .padding(.bottom, HeroGeometry.bottomPadding)
            pageDots
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.4), value: style)
        .background(arrowKeys)
    }

    private var chevrons: some View {
        HStack {
            chevron("chevron.compact.left", "Previous style") { model.step(-1) }
            Spacer()
            chevron("chevron.compact.right", "Next style") { model.step(1) }
        }
        .padding(.horizontal, 14)
        .padding(.trailing, model.menu?.hangsFromBottomBar == false ? GalleryPanel.inset : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -Metrics.chevronLift * size.height)
    }

    private func chevron(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .frame(width: Metrics.chevron.width, height: Metrics.chevron.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(FadeButtonStyle(rest: 0.78))
        .accessibilityLabel(label)
    }

    private func textBlock(_ style: LyricStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(style.category).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.62))
            Text(style.rawValue)
                .font(.system(size: 42, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, 3)
            Text(style.summary).font(.system(size: 14.5)).foregroundStyle(.white.opacity(0.74)).padding(.top, 7)
            HStack(spacing: 10) {
                mainAction(style)
                FavouriteButton(pinned: settings.favouriteStyles.contains(style), size: FavouriteButton.heroSize, glass: true) {
                    settings.toggleFavourite(style)
                }
                if style == .map { mapToggles }
            }
            .padding(.top, 20)
        }
    }

    @ViewBuilder private func mainAction(_ style: LyricStyle) -> some View {
        if settings.style == style {
            Label("Selected", systemImage: "checkmark")
                .modifier(PillLabel())
                .foregroundStyle(.white)
                .modifier(GlassSurface(shape: Capsule()))
                .accessibilityLabel("\(style.rawValue) is in use")
        } else {
            Button("Select") { model.select() }
                .buttonStyle(PrimaryPillStyle())
                // Return must not pick a style while the hero is scrolled out of sight.
                .keyboardShortcut(model.heroOffscreen ? nil : .defaultAction)
        }
    }

    @ViewBuilder private var mapToggles: some View {
        Button { settings.mapIn3D.toggle() } label: {
            Label(settings.mapIn3D ? "3D" : "Flat", systemImage: settings.mapIn3D ? "cube" : "map")
        }
        .buttonStyle(GlassPillStyle())
        .help("Lean the city over in 3D, or see it from directly above")
        Button { settings.mapFillsDisplay.toggle() } label: {
            Label(settings.mapFillsDisplay ? "Whole display" : "Window",
                  systemImage: settings.mapFillsDisplay ? "rectangle.inset.filled" : "macwindow")
        }
        .buttonStyle(GlassPillStyle())
        .help("Let the map take over the display, or keep it inside a window")
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(LyricStyle.allCases, id: \.self) { style in
                Button { model.browse(style) } label: {
                    Circle()
                        .fill(.white.opacity(style == model.browsed ? 1 : 0.34))
                        .frame(width: Metrics.dot, height: Metrics.dot)
                        .frame(width: Metrics.dotCell.width, height: Metrics.dotCell.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.rawValue)
                .accessibilityAddTraits(style == model.browsed ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 24)
    }

    /// Invisible buttons that give ← and → their shortcuts. Off while a panel is open (its slider wants the
    /// arrows) and while the hero is scrolled out of sight (nothing would show the change).
    private var arrowKeys: some View {
        Group {
            Button("Previous style") { model.step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next style") { model.step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .disabled(model.menu != nil || model.heroOffscreen)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
