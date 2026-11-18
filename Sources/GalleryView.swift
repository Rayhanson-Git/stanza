import SwiftUI

/// The whole window: a fixed hero stage behind a scroll view (hero controls, then the shelf), with the
/// top bar, the player pill, the settings bar at the bottom and at most one panel floating above.
/// On first run the introduction takes its place.
struct GalleryView: View {
    private enum Metrics {
        static let heroShare = 0.8
        static let minHeroHeight: CGFloat = 400
        /// Past this share of the hero the preview is out of sight and stops animating.
        static let heroGoneShare = 0.85
        static let topBarInset: CGFloat = 12
        /// The player pill hangs this far below the Settings gear.
        static let dockTop = topBarInset + GalleryTopBar.height + 8
        /// Between a bottom-bar panel and the bar.
        static let barPanelGap: CGFloat = 10
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
        // Settings and About open at the top right, over where the player pill sits.
        let card = model.menu.flatMap { !$0.hangsFromBottomBar && $0.player == nil ? $0 : nil }
        let calm = model.settings.reduceMotion
        return ZStack(alignment: .top) {
            Color.black
            GalleryHeroStage(model: model, settings: model.settings, size: hero)
            scroller(hero: hero)
            GallerySettingsBar(model: model)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, GallerySettingsBar.bottomInset)
            GalleryTopBar(model: model).padding(.top, Metrics.topBarInset)
            if card == nil {
                PlayerDock(model: model, link: model.playerLink, monitor: model.monitor, hover: model.hover,
                           maxHeight: size.height - Metrics.dockTop - GallerySettingsBar.clearance)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, GalleryPanel.margin)
                    .padding(.top, Metrics.dockTop)
                    .transition(.opacity)
            }
            if let card {
                GalleryPanel(menu: card, model: model, maxHeight: size.height - GalleryPanel.topOffset - GalleryPanel.margin)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, GalleryPanel.margin)
                    .padding(.top, GalleryPanel.topOffset)
                    .transition(calm ? .opacity : .scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                    .id(card)
            }
        }
        .overlayPreferenceValue(MenuButtonBounds.self) { buttons in
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Color.clear.allowsHitTesting(false)
                    if let menu = model.menu, let button = buttons[menu].map({ proxy[$0] }) {
                        barPanel(menu, button: button, in: proxy.size, calm: calm)
                    }
                }
            }
        }
        .animation(calm ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.84), value: model.menu)
        // The page behind sleeps while What's New is up: no clicks, arrows or Return reach it.
        .disabled(model.whatsNewOpen)
        .overlay { whatsNew(in: size, calm: calm) }
        .onAppear { model.presentWhatsNew() }
    }

    /// What's New over a dimmed window. The dimmed page takes the clicks, so only OK closes it.
    @ViewBuilder private func whatsNew(in size: CGSize, calm: Bool) -> some View {
        if model.whatsNewOpen {
            ZStack {
                Color.black.opacity(0.6).contentShape(Rectangle()).onTapGesture {}.transition(.opacity)
                WhatsNewCard(model: model, maxHeight: size.height - 2 * WhatsNewCard.margin)
                    .transition(calm ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// A lyric setting's panel: above the bar, centred on its button and unfolding from it.
    private func barPanel(_ menu: GalleryMenu, button: CGRect, in size: CGSize, calm: Bool) -> some View {
        let bottom = button.minY - GallerySettingsBar.padding - Metrics.barPanelGap
        let left = GalleryPanel.left(centredOn: button.midX, inWindow: size.width)
        let anchor = UnitPoint(x: (button.midX - left) / GalleryPanel.width, y: 1)
        return GalleryPanel(menu: menu, model: model, maxHeight: bottom - GalleryPanel.topOffset, edge: .bottom)
            .transition(calm ? .opacity : .scale(scale: 0.3, anchor: anchor).combined(with: .opacity))
            // Placement by alignment guides keeps the view's bounds the card's, so the anchor stays on the button.
            .alignmentGuide(.leading) { _ in -left }
            .alignmentGuide(.bottom) { d in d[.bottom] + size.height - bottom }
            .id(menu)
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
                // A click anywhere in the page closes an open panel; the click still does its own job too.
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { if model.menu != nil { model.menu = nil } })
            }
            .scrollIndicators(.never)
            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > hero.height * Metrics.heroGoneShare } action: { _, gone in
                model.heroOffscreen = gone
            }
            .onScrollPhaseChange { _, phase in model.setScrolling(phase != .idle) }
        }
    }

    /// An invisible button that gives Esc its job: close What's New or the open panel.
    private var escapeKey: some View {
        Button("Close panel") { model.whatsNewOpen ? model.dismissWhatsNew() : (model.menu = nil) }
            .keyboardShortcut(.cancelAction)
            .disabled(model.menu == nil && !model.whatsNewOpen)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// The update notice at the left and the Settings gear at the right.
struct GalleryTopBar: View {
    static let height: CGFloat = 44

    @ObservedObject var model: GalleryModel

    var body: some View {
        ZStack {
            if let updater = model.updater {
                UpdatePill(updater: updater)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, GalleryPanel.margin)
            }
            SettingsButton(model: model)
                .padding(4)
                .modifier(GlassSurface(shape: Circle()))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, GalleryPanel.margin)
        }
        .frame(height: Self.height)
    }
}

/// The four lyric settings in a slim glass capsule floating at the bottom centre. Each button reports where
/// it is, so its panel can unfold from it.
struct GallerySettingsBar: View {
    static let bottomInset: CGFloat = 20
    static let padding: CGFloat = 3
    /// The room the bar takes at the foot of the window, with a little air above it.
    static let clearance = bottomInset + MenuButton.height + 2 * padding + 14

    @ObservedObject var model: GalleryModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GalleryMenu.lyricSettings, id: \.self) { menu in
                MenuButton(title: menu.title, isOpen: model.menu == menu, hover: model.hover) { model.toggle(menu) }
                    .anchorPreference(key: MenuButtonBounds.self, value: .bounds) { [menu: $0] }
            }
        }
        .padding(Self.padding)
        .modifier(GlassSurface(shape: Capsule()))
    }
}
