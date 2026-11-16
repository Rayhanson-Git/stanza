import Combine
import SwiftUI

/// The panels that can hang from the top bar. Only one is open at a time.
enum GalleryMenu: String, CaseIterable {
    case size, font, lockScreen, aesthetics, spotify, music, settings

    /// The lyric settings in the centre of the top bar; the players and Settings sit at its right.
    static let lyricSettings: [GalleryMenu] = [.size, .font, .lockScreen, .aesthetics]

    init(player: Player) { self = player == .spotify ? .spotify : .music }

    var title: String {
        switch self {
        case .size: return "Size"
        case .font: return "Font"
        case .lockScreen: return "Lock Screen"
        case .aesthetics: return "Aesthetics"
        case .spotify: return Player.spotify.displayName
        case .music: return Player.music.displayName
        case .settings: return "Settings"
        }
    }

    var player: Player? {
        switch self {
        case .spotify: return .spotify
        case .music: return .music
        default: return nil
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, player, style, done
}

/// Which control or tile the pointer is over. Kept apart from `GalleryModel` so that moving the mouse
/// re-evaluates a handful of small views, not the hero. (View-local @State is unavailable: see `WordIcon`.)
final class GalleryHover: ObservableObject {
    /// A tile starts playing only after the pointer has rested on it this long.
    static let tilePlayDelay = 0.18

    @Published private(set) var control: String?
    @Published private(set) var tile: LyricStyle?
    @Published private(set) var playingTile: LyricStyle?
    private(set) var playingSince = Date()
    private var playStart: DispatchWorkItem?

    func setControl(_ id: String, hovered: Bool) {
        if hovered {
            control = id
        } else if control == id {
            control = nil
        }
    }

    func setTile(_ style: LyricStyle, hovered: Bool) {
        // Leaving tile A can be reported after entering tile B; only the tile on record may clear it.
        guard hovered ? tile != style : tile == style else { return }
        playStart?.cancel()
        if playingTile != nil { playingTile = nil }
        tile = hovered ? style : nil
        guard hovered else { return }
        let start = DispatchWorkItem { [weak self] in
            self?.playingSince = Date()
            self?.playingTile = style
        }
        playStart = start
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tilePlayDelay, execute: start)
    }
}

/// Everything the window's views share: what is being browsed, which panel is open, and when to stop animating.
final class GalleryModel: ObservableObject {
    /// Scrolling counts as still going for this long after the last movement, so stills do not flicker back to live.
    private static let scrollTail = 0.25
    /// First-run previews start part-way through a line, so there are words on screen at once.
    private static let onboardingHeadStart = 1.3

    let settings: AppSettings
    let engine: LyricEngine
    let monitor: NowPlayingMonitor
    let playerLink: PlayerLink
    /// Absent in the offscreen render tool, which must never go online.
    let updater: AppUpdater?
    let loginItem = LoginItem()
    let stills: StyleStills
    let hover = GalleryHover()

    @Published private(set) var browsed: LyricStyle
    @Published private(set) var heroSince: Date
    @Published var menu: GalleryMenu?
    /// The window cannot be seen (hidden, covered, minimised, app in the background, screen locked).
    @Published var suspended = false { didSet { applyPause() } }
    @Published private(set) var scrolling = false { didSet { applyPause() } }
    @Published var heroOffscreen = false
    @Published private(set) var onboarding: Bool
    @Published private(set) var onboardingStep = OnboardingStep.welcome
    private var scrollEnd: DispatchWorkItem?
    private let watchesPlayers: Bool
    private var isShutDown = false

    /// `onboarding` overrides the saved first-run flag, and `watchPlayers: false` keeps the players from
    /// being polled (the render tool uses both; nothing is written).
    init(settings: AppSettings, engine: LyricEngine, monitor: NowPlayingMonitor, playerLink: PlayerLink, updater: AppUpdater? = nil,
         onboarding: Bool? = nil, watchPlayers: Bool = true) {
        self.settings = settings
        self.updater = updater
        self.engine = engine
        self.monitor = monitor
        self.playerLink = playerLink
        watchesPlayers = watchPlayers
        stills = StyleStills(settings: settings)
        browsed = settings.style
        let showsOnboarding = onboarding ?? !settings.onboardingDone
        self.onboarding = showsOnboarding
        heroSince = Date().addingTimeInterval(showsOnboarding ? -Self.onboardingHeadStart : 0)
        // The Visual styles need their word pictures looked up before the first preview is drawn.
        WordVisuals.shared.prepare(words: DemoTrack.lyrics.words.map(\.text))
        playerLink.isWatched = watchPlayers
    }

    /// Called when the window closes: nothing may keep polling on its behalf afterwards.
    func shutDown() {
        isShutDown = true
        scrollEnd?.cancel()
        playerLink.isWatched = false
    }

    // MARK: Browsing

    static func stepped(from style: LyricStyle, by delta: Int) -> LyricStyle {
        let all = LyricStyle.allCases
        let index = all.firstIndex(of: style) ?? 0
        return all[((index + delta) % all.count + all.count) % all.count]
    }

    func browse(_ style: LyricStyle) {
        guard style != browsed else { return }
        browsed = style
        restartHero()
    }

    func step(_ delta: Int) { browse(Self.stepped(from: browsed, by: delta)) }

    /// Makes the browsed style the one the overlay uses.
    func select() {
        if settings.style != browsed { settings.style = browsed }
    }

    func toggle(_ menu: GalleryMenu) { self.menu = self.menu == menu ? nil : menu }

    var heroDemo: StyleDemo {
        StyleDemo(style: browsed, playingSince: settings.reduceMotion ? nil : heroSince,
                  paused: suspended || heroOffscreen || scrolling)
    }

    /// Tiles fall back to their still picture whenever animating one would be wasted or would stutter.
    var tilesStillOnly: Bool { suspended || scrolling }

    private func restartHero() { heroSince = Date().addingTimeInterval(onboarding ? -Self.onboardingHeadStart : 0) }

    // MARK: Pausing

    func setScrolling(_ moving: Bool) {
        scrollEnd?.cancel()
        if moving {
            if !scrolling { scrolling = true }
            return
        }
        let end = DispatchWorkItem { [weak self] in self?.scrolling = false }
        scrollEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollTail, execute: end)
    }

    private func applyPause() {
        // A late scroll or visibility change must not restart what closing the window stopped.
        guard !isShutDown else { return }
        stills.paused = suspended || scrolling
        playerLink.isWatched = watchesPlayers && !suspended
    }

    // MARK: First run

    func advanceOnboarding() {
        guard let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) else { return finishOnboarding() }
        onboardingStep = next
    }

    func retreatOnboarding() {
        OnboardingStep(rawValue: onboardingStep.rawValue - 1).map { onboardingStep = $0 }
    }

    func finishOnboarding() {
        // The style picked along the way becomes the one in use.
        select()
        settings.onboardingDone = true
        onboarding = false
        restartHero()
        log("onboarding finished with \(browsed.rawValue)")
    }
}
