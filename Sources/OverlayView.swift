import SwiftUI

enum LyricStyle: String, CaseIterable {
    case ship = "Ship"
    case fisheye = "Fisheye"
    case visual = "Visual"
    case fisheyeVisual = "Fisheye Visual"
    case codestyle = "Codestyle"
    case codestyleVisual = "Codestyle Visual"
    case branches = "Branches"
    case web = "Web"
    case constellation = "Constellation"
    // The "phone screen" styles: each lyric line arrives as a message, a payment, a notification or a map turn.
    case messages = "Messages"
    case money = "Money"
    case notifications = "Notifications"
    case map = "Map"

    /// These styles show history and react to gaps, so they are drawn for the whole song, not just while a line is sung.
    var drawsWholeSong: Bool {
        switch self {
        case .messages, .money, .notifications, .map: return true
        default: return false
        }
    }

    /// These styles tint their cards with colours from the album cover.
    var usesArtworkPalette: Bool { self == .money || self == .notifications }

    /// Evens out how much of the screen each style takes at the same Size: a style that is large by nature is scaled
    /// down, a small one up, so all of them fill about the same box (measured with `--render`, see the README).
    var footprint: Double {
        // Each fits a box half the screen wide and 45% tall at 100%. Branches and Constellation are drawn as a line
        // across the whole screen by design, so only their height is matched.
        switch self {
        case .ship: return 0.75
        case .fisheye, .fisheyeVisual: return 0.98
        case .visual: return 0.99
        case .codestyle, .codestyleVisual: return 0.96
        case .branches: return 0.92
        case .web: return 0.87
        case .constellation: return 0.89
        case .messages: return 1.15
        case .money: return 0.81
        case .notifications: return 1.08
        case .map: return 0.69
        }
    }

    /// The one scale a style draws at: the Size setting times its `footprint`. The Map filling the whole display keeps
    /// its full size and only scales its text.
    func scale(with settings: AppSettings) -> Double {
        self == .map && settings.mapFillsDisplay ? 1 : settings.textScale * footprint
    }

    /// How strongly the whole lyric block slowly sways in 3D (0 = perfectly still).
    var sway: Double {
        switch self {
        case .ship: return 1
        case .visual: return 0.5
        default: return 0
        }
    }
}

enum Layout {
    /// Lyrics live in a band this tall (fraction of the screen), starting `bandTop` from the top.
    static let bandHeight = 0.56
    static let bandTop = 0.28
    static let swayYawDegrees = 16.0, swayYawSpeed = 0.35
    static let swayPitchDegrees = 7.0, swayPitchSpeed = 0.22
    static let swayScale = 0.035, swayScaleSpeed = 0.17
    static let swayPerspective = 0.45
    /// Where the band's centre sits until it is moved, as a fraction of the screen measured from the top left.
    static let defaultCentre = CGPoint(x: 0.5, y: bandTop + bandHeight / 2)
    /// How close to the sides and to the top or bottom a moved centre may go, as a fraction of the screen. Lines are
    /// centred on it and can be wide, so the sides keep more room.
    static let sideMargin = 0.2, endMargin = 0.12

    /// Keeps a moved band on screen. `offset` is a fraction of the screen away from `defaultCentre`.
    static func clampedOffset(_ offset: CGPoint) -> CGPoint {
        func clamp(_ shift: Double, from centre: Double, margin: Double) -> Double { min(max(centre + shift, margin), 1 - margin) - centre }
        return CGPoint(x: clamp(offset.x, from: defaultCentre.x, margin: sideMargin),
                       y: clamp(offset.y, from: defaultCentre.y, margin: endMargin))
    }
}

/// Everything a style needs to draw one frame.
struct StyleContext {
    let line: ActiveLine
    let lyrics: TimedLyrics
    /// Seconds into the song.
    let position: Double
    /// Wall-clock seconds, for motion that runs regardless of the music.
    let clock: Double
    let canvas: CGSize
    let band: CGFloat
    let settings: AppSettings
    /// Size times the style's footprint (`LyricStyle.scale(with:)`); styles scale by this, never by Size directly.
    var scale: Double = 1
    /// What is playing, for styles that show it (empty in previews without a real track).
    var trackTitle = ""
    var trackArtist = ""
    /// A few colours taken from the album cover, for styles that tint cards with it; nil when there is none.
    var artworkPalette: [NSColor]?

    /// The words of the current line that have started; the newest is last.
    var sung: [TimedWord] { Array(line.words.prefix(line.shown)) }
    /// Index in `lyrics.words` of the newest started word of the current line. Lines are consecutive
    /// slices of `words`, so this is exact even when lines overlap in time (duets), where searching
    /// by start time would land in the wrong line.
    var newestWordIndex: Int { lyrics.lines[..<line.index].reduce(0) { $0 + $1.count } + max(1, line.shown) - 1 }
    func font(_ size: CGFloat) -> Font { Font(settings.font.font(size: size) as CTFont) }
}

/// Deterministic value in 0..<1 derived from a seed (usually a word's start time), so each word keeps the
/// same tilt and placement for as long as it is on screen. SplitMix64 finaliser.
func seededUnit(_ seed: Double, salt: UInt64) -> Double {
    var value = seed.bitPattern &* 0x9E37_79B9_7F4A_7C15 &+ salt
    value = (value ^ (value >> 31)) &* 0x94D0_49BB_1331_11EB
    return Double((value ^ (value >> 29)) % 10_000) / 10_000
}

/// Black or white, whichever reads better on `background`.
func contrastColor(on background: NSColor) -> Color {
    let color = background.usingColorSpace(.sRGB) ?? background
    let luma = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    return luma > 0.55 ? .black : .white
}

/// The slow 3D drift of the whole lyric block. Skipped entirely for styles that stay still.
private struct Sway: ViewModifier {
    let amount: Double
    let clock: Double

    func body(content: Content) -> some View {
        if amount == 0 {
            content
        } else {
            content
                .rotation3DEffect(.degrees(sin(clock * Layout.swayYawSpeed) * Layout.swayYawDegrees * amount),
                                  axis: (x: 0, y: 1, z: 0), perspective: Layout.swayPerspective)
                .rotation3DEffect(.degrees(sin(clock * Layout.swayPitchSpeed) * Layout.swayPitchDegrees * amount),
                                  axis: (x: 1, y: 0, z: 0), perspective: Layout.swayPerspective)
                .scaleEffect(1 + sin(clock * Layout.swayScaleSpeed) * Layout.swayScale * amount)
        }
    }
}

/// Which displays the overlay currently gives up to the Stanza window, so lyrics never sit on top of it.
final class OverlayPresence: ObservableObject {
    @Published var yielding: Set<UInt32> = []
    /// Nothing has played for a while, so the lyrics are put away instead of hanging on the paused line.
    @Published var idle = false
}

/// One frame of a style, placed in the lyric band of a screen-sized canvas. The live overlay and the
/// window's previews both draw through this, so a preview cannot drift from the real thing.
struct LyricStage: View {
    let style: LyricStyle
    let lyrics: TimedLyrics?
    let position: Double
    let clock: Double
    let size: CGSize
    let settings: AppSettings
    var trackTitle = ""
    var trackArtist = ""
    var artworkPalette: [NSColor]?
    /// Where the user moved the lyrics, as a fraction of the screen; previews in the window leave it at zero.
    var offset = CGPoint.zero

    var body: some View {
        let band = size.height * Layout.bandHeight
        Group {
            // Nothing is drawn without lyrics, before the first word, or in a long instrumental gap.
            if let lyrics, let line = lyrics.line(at: position, alwaysDrawn: style.drawsWholeSong) {
                styleView(style, StyleContext(line: line, lyrics: lyrics, position: position, clock: clock, canvas: size,
                                              band: band, settings: settings, scale: style.scale(with: settings),
                                              trackTitle: trackTitle, trackArtist: trackArtist, artworkPalette: artworkPalette))
            }
        }
        .frame(width: size.width, height: band)
        .modifier(Sway(amount: style.sway, clock: clock))
        .position(x: size.width * (Layout.defaultCentre.x + offset.x), y: size.height * (Layout.defaultCentre.y + offset.y))
    }
}

struct LyricOverlayView: View {
    @ObservedObject var engine: LyricEngine
    @ObservedObject var monitor: NowPlayingMonitor
    @ObservedObject var settings: AppSettings
    @ObservedObject var artwork: ArtworkColorSync
    @ObservedObject var presence: OverlayPresence
    /// The display this overlay covers; nil in tools that draw it without a screen.
    var display: UInt32?

    var body: some View {
        GeometryReader { geometry in
            // Redrawing every frame is only needed while lyrics are moving and can be seen; otherwise the overlay costs nothing.
            TimelineView(.animation(paused: engine.lyrics == nil || !monitor.isPlaying || isYielding || presence.idle)) { timeline in
                LyricStage(style: settings.style, lyrics: engine.lyrics, position: engine.position(at: timeline.date),
                           clock: timeline.date.timeIntervalSinceReferenceDate, size: geometry.size, settings: settings,
                           trackTitle: monitor.track?.title ?? "", trackArtist: monitor.track?.artist ?? "",
                           artworkPalette: artwork.palette, offset: settings.lyricOffset(for: settings.style))
            }
        }
        .ignoresSafeArea()
        // Fades away after a long pause, and is back the instant music plays again.
        .opacity(presence.idle ? 0 : 1)
        .animation(presence.idle ? .easeOut(duration: 0.8) : nil, value: presence.idle)
    }

    private var isYielding: Bool { display.map(presence.yielding.contains) ?? false }
}

/// The little picture that accompanies a word in the "Visual" styles.
struct WordIcon: View {
    let visual: WordVisual
    let size: CGFloat
    let color: Color
    /// Seconds since the word it belongs to started. Drives the entrance flourish without view state
    /// (the @State macro needs full Xcode, and this builds with the command-line tools alone).
    let age: Double

    var body: some View {
        let arrived = age > 0.03
        Group {
            switch visual {
            case .emoji(let character):
                Text(character)
                    .font(.system(size: size))
                    .rotationEffect(.degrees(arrived ? 0 : -14))
                    .animation(.spring(response: 0.3, dampingFraction: 0.25), value: arrived)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(color)
                    .symbolEffect(.wiggle, options: .speed(1.5), value: arrived)
            }
        }
        .transition(.scale(scale: 0.2).combined(with: .opacity))
    }
}
