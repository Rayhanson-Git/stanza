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

    var body: some View {
        let band = size.height * Layout.bandHeight
        Group {
            // Nothing is drawn without lyrics, before the first word, or in a long instrumental gap.
            if let lyrics, let line = lyrics.line(at: position, alwaysDrawn: style.drawsWholeSong) {
                styleView(style, StyleContext(line: line, lyrics: lyrics, position: position, clock: clock, canvas: size,
                                              band: band, settings: settings, trackTitle: trackTitle,
                                              trackArtist: trackArtist, artworkPalette: artworkPalette))
            }
        }
        .frame(width: size.width, height: band)
        .modifier(Sway(amount: style.sway, clock: clock))
        .position(x: size.width / 2, y: size.height * Layout.bandTop + band / 2)
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
            TimelineView(.animation(paused: engine.lyrics == nil || !monitor.isPlaying || isYielding)) { timeline in
                LyricStage(style: settings.style, lyrics: engine.lyrics, position: engine.position(at: timeline.date),
                           clock: timeline.date.timeIntervalSinceReferenceDate, size: geometry.size, settings: settings,
                           trackTitle: monitor.track?.title ?? "", trackArtist: monitor.track?.artist ?? "",
                           artworkPalette: artwork.palette)
            }
        }
        .ignoresSafeArea()
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
