import SwiftUI

/// The whole window: a fixed hero stage behind a scroll view (hero controls, then the shelf), with the
/// top bar and at most one panel floating above. On first run the introduction takes its place.
struct GalleryView: View {
    private enum Metrics {
        static let heroShare = 0.8
        static let minHeroHeight: CGFloat = 400
        /// Past this share of the hero the preview is out of sight and stops animating.
        static let heroGoneShare = 0.85
        static let topBarInset: CGFloat = 12
        static let heroAnchor = "hero"
    }

    @ObservedObject var model: GalleryModel

    var body: some View {
        GeometryReader { geometry in
            if model.onboarding {
                OnboardingView(model: model, settings: model.settings, stills: model.stills).transition(.opacity)
            } else {
                gallery(in: geometry.size).transition(.opacity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.3), value: model.onboarding)
        .background(escapeKey)
    }

    private func gallery(in size: CGSize) -> some View {
        let hero = CGSize(width: size.width, height: max(size.height * Metrics.heroShare, Metrics.minHeroHeight))
        return ZStack(alignment: .top) {
            Color.black
            GalleryHeroStage(model: model, settings: model.settings, size: hero)
            scroller(hero: hero)
            GalleryTopBar(model: model).padding(.top, Metrics.topBarInset)
            if let menu = model.menu {
                GalleryPanel(menu: menu, model: model, maxHeight: size.height - GalleryPanel.topOffset - GalleryPanel.margin)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, GalleryPanel.margin)
                    .padding(.top, GalleryPanel.topOffset)
                    .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                    .id(menu)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.84), value: model.menu)
    }

    private func scroller(hero: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    GalleryHeroControls(model: model, settings: model.settings, size: hero).id(Metrics.heroAnchor)
                    GalleryShelf(model: model, settings: model.settings, stills: model.stills) { style in
                        model.browse(style)
                        withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(Metrics.heroAnchor, anchor: .top) }
                    }
                }
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > hero.height * Metrics.heroGoneShare } action: { _, gone in
                model.heroOffscreen = gone
            }
            .onScrollPhaseChange { _, phase in model.setScrolling(phase != .idle) }
        }
    }

    /// An invisible button that gives Esc its job: close the open panel.
    private var escapeKey: some View {
        Button("Close panel") { model.menu = nil }
            .keyboardShortcut(.cancelAction)
            .disabled(model.menu == nil)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// The four settings buttons in a centred glass capsule, and the player buttons at the right.
struct GalleryTopBar: View {
    static let height: CGFloat = 44

    @ObservedObject var model: GalleryModel

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(GalleryMenu.settings, id: \.self) { menu in
                    MenuButton(title: menu.title, isOpen: model.menu == menu, hover: model.hover) { model.toggle(menu) }
                }
            }
            .padding(4)
            .modifier(GlassSurface(shape: Capsule()))
            PlayerButtons(model: model, link: model.playerLink, monitor: model.monitor)
                .padding(4)
                .modifier(GlassSurface(shape: Capsule()))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, GalleryPanel.margin)
        }
        .frame(height: Self.height)
    }
}
