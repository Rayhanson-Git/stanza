import AppKit
import Combine

enum LyricFont: String, CaseIterable {
    case sfPro = "SF Pro"
    case sfRounded = "SF Rounded"
    case newYork = "New York"
    case helveticaNeue = "Helvetica Neue"
    case avenirNext = "Avenir Next"
    case futura = "Futura"
    case didot = "Didot"

    func font(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: .semibold)
        func designed(_ design: NSFontDescriptor.SystemDesign) -> NSFont {
            system.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
        switch self {
        case .sfPro: return system
        case .sfRounded: return designed(.rounded)
        case .newYork: return designed(.serif)
        case .helveticaNeue: return NSFont(name: "HelveticaNeue-Bold", size: size) ?? system
        case .avenirNext: return NSFont(name: "AvenirNext-Bold", size: size) ?? system
        case .futura: return NSFont(name: "Futura-Bold", size: size) ?? system
        case .didot: return NSFont(name: "Didot-Bold", size: size) ?? system
        }
    }
}

enum ColorSlot: String, CaseIterable {
    case text, highlight, secondary

    var title: String {
        switch self {
        case .text: return "Lyric Text"
        case .highlight: return "Highlight"
        case .secondary: return "Secondary Text"
        }
    }

    var defaultColor: NSColor { self == .secondary ? NSColor.white.withAlphaComponent(0.7) : .white }
    var defaultsKey: String { "color.\(rawValue)" }
}

extension NSColor {
    /// "#RRGGBBAA" in sRGB.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? .white
        func byte(_ component: CGFloat) -> Int { Int((component * 255).rounded()) }
        return String(format: "#%02X%02X%02X%02X", byte(color.redComponent), byte(color.greenComponent),
                      byte(color.blueComponent), byte(color.alphaComponent))
    }

    convenience init?(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        guard digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat(value >> 24 & 0xFF) / 255, green: CGFloat(value >> 16 & 0xFF) / 255,
                  blue: CGFloat(value >> 8 & 0xFF) / 255, alpha: CGFloat(value & 0xFF) / 255)
    }
}

/// User preferences, persisted in UserDefaults and observed by the overlay views.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let textScaleRange = 0.5...1.5
    /// Seconds added to the lyric clock; positive shows lyrics earlier.
    static let syncOffsetRange = -1.0...1.0

    private enum Key {
        static let style = "lyricStyle", font = "lyricFont", textScale = "textScale", syncOffset = "syncOffset"
        static let autoSyncColors = "autoSyncColors", keepScreenAwake = "keepScreenAwake"
        static let showWhenUnlocked = "showWhenUnlocked", disabledDisplays = "disabledDisplays"
        static let mapIn3D = "mapIn3D", mapFillsDisplay = "mapFillsDisplay"
        static let pinnedStyles = "pinnedStyles", onboardingDone = "onboardingDone"
        static let lyricOffsetX = "lyricOffsetX", lyricOffsetY = "lyricOffsetY"
    }

    private let defaults = UserDefaults.standard

    @Published var style: LyricStyle { didSet { defaults.set(style.rawValue, forKey: Key.style); log("style → \(style.rawValue)") } }
    @Published var font: LyricFont { didSet { defaults.set(font.rawValue, forKey: Key.font); log("font → \(font.rawValue)") } }
    @Published var textScale: Double { didSet { defaults.set(textScale, forKey: Key.textScale) } }
    @Published var syncOffset: Double { didSet { defaults.set(syncOffset, forKey: Key.syncOffset) } }
    @Published var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }
    @Published var showWhenUnlocked: Bool { didSet { defaults.set(showWhenUnlocked, forKey: Key.showWhenUnlocked) } }
    /// Map style: tilt the city in 3D, or look straight down.
    @Published var mapIn3D: Bool { didSet { defaults.set(mapIn3D, forKey: Key.mapIn3D) } }
    /// Map style: make the whole display the map, or keep it a rounded window.
    @Published var mapFillsDisplay: Bool { didSet { defaults.set(mapFillsDisplay, forKey: Key.mapFillsDisplay) } }
    /// Styles kept in the status-bar menu for quick switching. No limit on how many.
    @Published private(set) var pinnedStyles: Set<LyricStyle> {
        didSet { defaults.set(Self.rawPins(pinnedStyles), forKey: Key.pinnedStyles) }
    }
    /// Where the lyrics were moved to, as a fraction of the screen away from the middle (Move Lyrics in the menu).
    /// Set it through `Layout.clampedOffset` so the lyrics can never be lost off screen.
    @Published var lyricOffset: CGPoint {
        didSet {
            defaults.set(lyricOffset.x, forKey: Key.lyricOffsetX)
            defaults.set(lyricOffset.y, forKey: Key.lyricOffsetY)
        }
    }
    /// The Map style filling the whole display has nowhere to move to, so it stays put.
    func lyricOffset(for style: LyricStyle) -> CGPoint { style == .map && mapFillsDisplay ? .zero : lyricOffset }
    /// False until the first-run introduction in the window has been finished once.
    @Published var onboardingDone: Bool { didSet { defaults.set(onboardingDone, forKey: Key.onboardingDone) } }
    /// The system "Reduce motion" accessibility setting; styles drop their decorative wobble when it is on.
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    @Published var disabledDisplays: Set<UInt32> {
        didSet { defaults.set(disabledDisplays.map(String.init).sorted(), forKey: Key.disabledDisplays) }
    }
    @Published var autoSyncColors: Bool {
        didSet {
            defaults.set(autoSyncColors, forKey: Key.autoSyncColors)
            // Album-art colours are never persisted, so switching off restores the hand-picked ones.
            if !autoSyncColors { reloadStoredColors() }
        }
    }
    /// The colours currently on screen: the stored ones, or album-art colours while auto sync is on.
    @Published private(set) var textColor = ColorSlot.text.defaultColor
    @Published private(set) var highlightColor = ColorSlot.highlight.defaultColor
    @Published private(set) var secondaryColor = ColorSlot.secondary.defaultColor
    /// True while the colours on screen come from album art instead of the stored ones.
    private var showsAccent = false

    private init() {
        let defaults = UserDefaults.standard
        func bool(_ key: String, default fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func clamped(_ key: String, _ range: ClosedRange<Double>, default fallback: Double) -> Double {
            (defaults.object(forKey: key) as? Double).map { min(max($0, range.lowerBound), range.upperBound) } ?? fallback
        }
        style = defaults.string(forKey: Key.style).flatMap(LyricStyle.init(rawValue:)) ?? LyricStyle.allCases[0]
        font = defaults.string(forKey: Key.font).flatMap(LyricFont.init(rawValue:)) ?? .sfPro
        textScale = clamped(Key.textScale, Self.textScaleRange, default: 1)
        syncOffset = clamped(Key.syncOffset, Self.syncOffsetRange, default: 0)
        keepScreenAwake = bool(Key.keepScreenAwake, default: true)
        showWhenUnlocked = bool(Key.showWhenUnlocked, default: true)
        mapIn3D = bool(Key.mapIn3D, default: true)
        mapFillsDisplay = bool(Key.mapFillsDisplay, default: false)
        autoSyncColors = bool(Key.autoSyncColors, default: false)
        disabledDisplays = Set((defaults.stringArray(forKey: Key.disabledDisplays) ?? []).compactMap(UInt32.init))
        pinnedStyles = Self.pins(from: defaults.stringArray(forKey: Key.pinnedStyles) ?? [])
        onboardingDone = bool(Key.onboardingDone, default: false)
        lyricOffset = Layout.clampedOffset(CGPoint(x: defaults.double(forKey: Key.lyricOffsetX), y: defaults.double(forKey: Key.lyricOffsetY)))
        reloadStoredColors()
    }

    func color(_ slot: ColorSlot) -> NSColor {
        switch slot {
        case .text: return textColor
        case .highlight: return highlightColor
        case .secondary: return secondaryColor
        }
    }

    func storedColor(_ slot: ColorSlot) -> NSColor {
        defaults.string(forKey: slot.defaultsKey).flatMap(NSColor.init(hex:)) ?? slot.defaultColor
    }

    func setColor(_ color: NSColor, for slot: ColorSlot) {
        defaults.set(color.hexString, forKey: slot.defaultsKey)
        show(color, in: slot)
    }

    func resetColors() {
        ColorSlot.allCases.forEach { defaults.removeObject(forKey: $0.defaultsKey) }
        // Album-art colours stay up; only the hand-picked ones underneath them were reset.
        if !showsAccent { reloadStoredColors() }
    }

    /// Derives the three lyric colours from an album-art accent, without persisting them.
    func applyAccent(_ accent: NSColor) {
        let color = accent.usingColorSpace(.sRGB) ?? accent
        // Lift dark accents: lyrics sit on arbitrary wallpapers and must stay readable.
        let highlight = NSColor(hue: color.hueComponent, saturation: color.saturationComponent,
                                brightness: max(color.brightnessComponent, 0.75), alpha: 1)
        let text = NSColor(hue: color.hueComponent, saturation: min(color.saturationComponent, 0.45), brightness: 1, alpha: 1)
        show(highlight, in: .highlight)
        show(text, in: .text)
        show(text.withAlphaComponent(0.7), in: .secondary)
        showsAccent = true
    }

    /// Back to the hand-picked colours (for a track without usable artwork).
    func clearAccent() { reloadStoredColors() }

    func toggleDisplay(_ id: UInt32) {
        disabledDisplays = disabledDisplays.symmetricDifference([id])
        log("display \(id) → \(disabledDisplays.contains(id) ? "off" : "on")")
    }

    // MARK: Pinned styles

    static func pins(from names: [String]) -> Set<LyricStyle> { Set(names.compactMap(LyricStyle.init(rawValue:))) }

    /// Stored in gallery order so the saved list reads the same however the set happens to iterate.
    static func rawPins(_ pins: Set<LyricStyle>) -> [String] { LyricStyle.allCases.filter(pins.contains).map(\.rawValue) }

    static func togglingPin(_ style: LyricStyle, in pins: Set<LyricStyle>) -> Set<LyricStyle> { pins.symmetricDifference([style]) }

    /// What the status-bar menu lists: every style, grouped as in the window, with any pinned styles
    /// repeated in a short group at the top for quick switching.
    static func menuGroups(pinned: Set<LyricStyle>) -> [(title: String, styles: [LyricStyle])] {
        let pinnedGroup = LyricStyle.allCases.filter(pinned.contains)
        let categories = LyricStyle.allCases.map(\.category).reduce(into: [String]()) { order, category in
            if !order.contains(category) { order.append(category) }
        }
        let byCategory = categories.map { category in (title: category, styles: LyricStyle.allCases.filter { $0.category == category }) }
        return (pinnedGroup.isEmpty ? [] : [(title: "Pinned", styles: pinnedGroup)]) + byCategory
    }

    func togglePin(_ style: LyricStyle) {
        pinnedStyles = Self.togglingPin(style, in: pinnedStyles)
        log("pin \(style.rawValue) → \(pinnedStyles.contains(style) ? "on" : "off")")
    }

    private func reloadStoredColors() {
        ColorSlot.allCases.forEach { show(storedColor($0), in: $0) }
        showsAccent = false
    }

    private func show(_ color: NSColor, in slot: ColorSlot) {
        switch slot {
        case .text: textColor = color
        case .highlight: highlightColor = color
        case .secondary: secondaryColor = color
        }
    }
}
