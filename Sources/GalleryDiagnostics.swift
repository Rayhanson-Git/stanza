import AppKit
import SwiftUI

/// Pictures of the window without opening it:
///   Stanza --render-gallery <output.png> [view] [<width>x<height>]   the window laid out offscreen
///   Stanza --render-tile "<style name>" <output.png>                 one shelf tile's still
/// Nothing is saved to the preferences; pass `-textScale '<real>1.5</real>'` and the like to try variants.
/// Known limit: the window picture is taken from its layers, which cannot draw 3D transforms, so in the
/// hero the tilted words of Ship, Visual and the Fisheye styles land in the wrong place (try
/// `-lyricStyle Branches`). Tiles are drawn by SwiftUI itself and are exact.
extension Diagnostics {
    static let galleryViews = ["none", "size", "font", "lockscreen", "aesthetics", "spotify", "music", "settings", "about", "whatsnew",
                               "onboarding", "onboarding-player", "onboarding-style", "onboarding-done", "shelf"]
    static let gallerySize = CGSize(width: 1180, height: 740)
    /// Tall enough to show every row of the shelf, which the window itself would scroll.
    private static let shelfSize = CGSize(width: 1180, height: 1120)
    /// Time for the stills to render one by one and for word pictures to come back.
    // Also lands the capture about 1.4 s into the hero's loop, when its first line is fully up.
    private static let settleSeconds = 5.35
    private static let wordPictureSeconds = 1.5

    @MainActor
    static func renderGallery(to path: String, showing view: String, size requested: CGSize?) -> Bool {
        _ = NSApplication.shared
        let settings = AppSettings.shared
        // Neither the monitor nor the link is started, so nothing polls a player; the player panels show
        // their "Checking…" state.
        let monitor = NowPlayingMonitor()
        let model = GalleryModel(settings: settings, engine: LyricEngine(monitor: monitor, settings: settings), monitor: monitor,
                                 playerLink: PlayerLink(),
                                 updater: view == "settings" ? AppUpdater() : nil, onboarding: view.hasPrefix("onboarding"), watchPlayers: false,
                                 showsWhatsNew: false)
        defer { model.shutDown() }
        let menus: [String: GalleryMenu] = ["size": .size, "font": .font, "lockscreen": .lockScreen, "aesthetics": .aesthetics,
                                            "spotify": .spotify, "music": .music, "settings": .settings, "about": .about,
                                            "whatsnew": .whatsNew]
        model.menu = menus[view]
        let onboardingSteps = ["onboarding-player": 1, "onboarding-style": 2, "onboarding-done": 3]
        (0..<(onboardingSteps[view] ?? 0)).forEach { _ in model.advanceOnboarding() }

        let isShelf = view == "shelf"
        let size = requested ?? (isShelf ? shelfSize : gallerySize)
        let root = isShelf
            ? AnyView(GalleryShelf(model: model, settings: settings, stills: model.stills) { _ in }.environment(\.colorScheme, .dark))
            : AnyView(GalleryView(model: model))
        let hosting = NSHostingView(rootView: root.environment(\.flatGlass, true))
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        // Never ordered in: the window only gives the view an appearance and a layout pass. The view is a
        // subview, not the content view, so a render taller than the screen is not squeezed to fit it.
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView?.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settleSeconds))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("could not make a bitmap for the window")
            return false
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return writePNG(bitmap, to: path)
    }

    @MainActor
    static func renderTile(style: LyricStyle, to path: String) -> Bool {
        WordVisuals.shared.prepare(words: DemoTrack.lyrics.words.map(\.text))
        RunLoop.main.run(until: Date().addingTimeInterval(wordPictureSeconds))
        guard let image = StyleStills.render(style, settings: AppSettings.shared) else {
            print("could not render the \(style.rawValue) tile")
            return false
        }
        return writePNG(NSBitmapImageRep(cgImage: image), to: path)
    }

    /// "1180x740" → a size; nil for anything else.
    static func size(from text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts.allSatisfy({ $0 >= 1 }) else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    private static func writePNG(_ bitmap: NSBitmapImageRep, to path: String) -> Bool {
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            print("could not encode \(path) as PNG")
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            print("could not write \(path): \(error.localizedDescription)")
            return false
        }
    }
}
