import SwiftUI

/// The made-up song every preview plays: ten short lines with word timings.
enum DemoTrack {
    static let title = "Demo"
    static let artist = "Stanza"
    static let firstLineStart = 0.8
    static let lineSpacing = 1.75
    static let lineDuration = 1.5
    // A word's share of its line grows with its length; the last word is held longer, as singers do.
    static let baseWordWeight = 2.0
    static let lastWordStretch = 1.7

    static let lines = [
        "Headlights sweep the empty street",
        "All the windows hold their breath",
        "Flip a coin for the last slow dance",
        "Stay till the sun climbs over the city",
        "Who taught the rain to keep time?",
        "Fireflies drift over the wheat at dusk",
        "Count the stars from the kitchen door",
        "This old road knows the long way home",
        "A paper kite and a pocket of wind",
        "Leave the radio on for the moon",
    ]

    static func lineStart(_ index: Int) -> Double { firstLineStart + lineSpacing * Double(index) }

    static func words(of text: String, line index: Int) -> [TimedWord] {
        let texts = text.split(separator: " ").map(String.init)
        let weights = texts.enumerated().map { offset, word in
            (Double(word.filter(\.isLetter).count) + baseWordWeight) * (offset == texts.count - 1 ? lastWordStretch : 1)
        }
        let total = weights.reduce(0, +)
        let ends = weights.reduce(into: [Double]()) { ends, weight in
            ends.append((ends.last ?? lineStart(index)) + weight * lineDuration / total)
        }
        return texts.enumerated().map { offset, word in
            TimedWord(text: word, start: offset == 0 ? lineStart(index) : ends[offset - 1], end: ends[offset], line: index)
        }
    }

    static let lyrics = TimedLyrics(tier: .wordLevel, words: lines.enumerated().flatMap { words(of: $1, line: $0) })

    /// The part of the song one style is given. A style that keeps history gets everything up to its pair
    /// of lines; the others get the pair alone, so the lead-in is empty instead of showing the tail of the
    /// line before.
    static func lyrics(for style: LyricStyle) -> TimedLyrics { excerpts[style] ?? lyrics }

    private static let excerpts: [LyricStyle: TimedLyrics] = Dictionary(uniqueKeysWithValues: LyricStyle.allCases.map { style in
        let played = (style.drawsWholeSong ? 0 : style.demoFirstLine)...(style.demoFirstLine + 1)
        return (style, TimedLyrics(tier: .wordLevel, words: lyrics.words.filter { played.contains($0.line) }))
    })
}

/// One style playing two lines of the demo song on a loop, or frozen on a single frame.
struct StyleDemo {
    static let leadIn = 0.2
    static let hold = 0.5
    /// The frozen frame sits this far into the second line, when most of its words are up.
    static let stillOffset = 1.23
    static let fadeIn = 0.16
    static let fadeOut = 0.24

    let style: LyricStyle
    /// When the loop began; nil shows the still frame.
    var playingSince: Date?
    var paused = false

    private var firstStart: Double { DemoTrack.lineStart(style.demoFirstLine) }
    private var secondStart: Double { DemoTrack.lineStart(style.demoFirstLine + 1) }

    var window: ClosedRange<Double> { (firstStart - Self.leadIn)...(secondStart + DemoTrack.lineDuration + Self.hold) }
    var still: Double { secondStart + Self.stillOffset }
    var isPlaying: Bool { playingSince != nil }

    /// Seconds into the current pass of the loop.
    func phase(at now: Date) -> Double {
        guard let playingSince else { return 0 }
        return max(0, now.timeIntervalSince(playingSince)).truncatingRemainder(dividingBy: window.upperBound - window.lowerBound)
    }

    func position(at now: Date) -> Double { isPlaying ? window.lowerBound + phase(at: now) : still }

    /// Each pass fades in and out so the jump back to the start is never seen.
    func opacity(at now: Date) -> Double {
        guard isPlaying else { return 1 }
        let phase = phase(at: now)
        let remaining = window.upperBound - window.lowerBound - phase
        return min(1, max(0, min(phase / Self.fadeIn, remaining / Self.fadeOut)))
    }
}

/// The song playing right now, for previews that follow it instead of the demo song.
struct LivePreviewSource {
    let engine: LyricEngine
    let monitor: NowPlayingMonitor
}

/// A demo drawn on a canvas the size of a screen, through the same `LyricStage` as the real overlay. A playing preview
/// given a `live` source shows the song playing now whenever it has a line to show.
struct StyleDemoView: View {
    let demo: StyleDemo
    @ObservedObject var settings: AppSettings
    var live: LivePreviewSource?

    var body: some View {
        GeometryReader { geometry in
            if demo.isPlaying, let live {
                FollowingDemoView(demo: demo, settings: settings, engine: live.engine, monitor: live.monitor, size: geometry.size)
            } else if demo.isPlaying {
                TimelineView(.animation(paused: demo.paused)) { timeline in
                    Self.demoFrame(demo, at: timeline.date, size: geometry.size, settings: settings)
                }
            } else {
                // A still needs no clock at all, and using its own position keeps every render of it identical.
                Self.stage(demo, position: demo.still, clock: demo.still, size: geometry.size, settings: settings)
            }
        }
    }

    /// One frame of the demo loop, faded at each end so the jump back to the start is never seen.
    static func demoFrame(_ demo: StyleDemo, at date: Date, size: CGSize, settings: AppSettings) -> some View {
        stage(demo, position: demo.position(at: date), clock: date.timeIntervalSinceReferenceDate, size: size, settings: settings)
            .opacity(demo.opacity(at: date))
    }

    static func stage(_ demo: StyleDemo, position: Double, clock: Double, size: CGSize, settings: AppSettings) -> some View {
        LyricStage(style: demo.style, lyrics: DemoTrack.lyrics(for: demo.style), position: position, clock: clock, size: size, settings: settings,
                   trackTitle: DemoTrack.title, trackArtist: DemoTrack.artist)
    }
}

/// A playing preview that shows the song playing now, in time with it, gaps included, exactly as the real lyrics do.
/// While nothing plays, or for a song without lyrics, it plays the demo instead.
private struct FollowingDemoView: View {
    let demo: StyleDemo
    @ObservedObject var settings: AppSettings
    @ObservedObject var engine: LyricEngine
    @ObservedObject var monitor: NowPlayingMonitor
    let size: CGSize

    var body: some View {
        TimelineView(.animation(paused: demo.paused)) { timeline in
            let position = engine.position(at: timeline.date)
            // Deciding per line would swap in the demo's words during every instrumental gap and back again.
            if monitor.isPlaying, let lyrics = engine.lyrics {
                LyricStage(style: demo.style, lyrics: lyrics, position: position, clock: timeline.date.timeIntervalSinceReferenceDate,
                           size: size, settings: settings, trackTitle: monitor.track?.title ?? "", trackArtist: monitor.track?.artist ?? "")
            } else {
                StyleDemoView.demoFrame(demo, at: timeline.date, size: size, settings: settings)
            }
        }
    }
}

/// A demo on a virtual screen `screenHeight` points tall, scaled to fit `size`, then magnified by `zoom`
/// about the lyric band's centre.
struct StyleStage: View {
    static let heroScreenHeight: CGFloat = 640
    static let tileScreenHeight: CGFloat = 560
    /// Styles size themselves as shares of the screen, so `screenHeight` cannot enlarge them; this does.
    static let heroZoom: CGFloat = 1.15
    static let tileZoom: CGFloat = 1.1

    let demo: StyleDemo
    let size: CGSize
    let screenHeight: CGFloat
    let settings: AppSettings
    var live: LivePreviewSource?
    var zoom: CGFloat = 1

    var body: some View {
        if size.width > 1, size.height > 1 {
            let scale = size.height / screenHeight
            StyleDemoView(demo: demo, settings: settings, live: live)
                .frame(width: size.width / scale, height: screenHeight)
                .scaleEffect(scale)
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoom, anchor: UnitPoint(x: Layout.defaultCentre.x, y: Layout.defaultCentre.y))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// What a tile shows: the style's backdrop with the whole virtual screen on top.
struct TileScene: View {
    /// Lifts the lyric band a little so it sits in the optical middle of the tile.
    static let lift = 0.06

    let demo: StyleDemo
    let size: CGSize
    let settings: AppSettings
    var live: LivePreviewSource?

    var body: some View {
        let fillsTile = demo.style == .map && settings.mapFillsDisplay
        ZStack {
            StyleBackdrop(style: demo.style)
            StyleStage(demo: demo, size: size, screenHeight: StyleStage.tileScreenHeight, settings: settings, live: live,
                       zoom: fillsTile ? 1 : StyleStage.tileZoom)
                .offset(y: fillsTile ? 0 : -Self.lift * size.height)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
