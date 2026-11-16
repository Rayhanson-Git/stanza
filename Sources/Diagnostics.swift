import AppKit
import SwiftUI

/// Command-line helpers for checking the app without playing music:
///   Stanza --lyrics "<artist>" "<title>" <seconds>     look a song up and report what was found
///   Stanza --render "<style name>" <output.png> [seconds]   draw one frame of a style with sample lyrics
enum Diagnostics {
    static let sampleLine = ["Paint", "the", "quiet", "harbour,", "every", "lamp", "still", "burning"]

    static func lookUp(artist: String, title: String, seconds: Double) {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let lyrics = await LyricsProvider().lyrics(for: Track(title: title, artist: artist, duration: seconds))
            if let lyrics {
                print("\(lyrics.tier.rawValue): \(lyrics.words.count) words in \(lyrics.lines.count) lines")
                for line in lyrics.lines.prefix(3) {
                    print(String(format: "  %6.2fs  ", line[0].start) + line.map(\.text).joined(separator: " "))
                }
            } else {
                print("no lyrics found")
            }
            done.signal()
        }
        done.wait()
    }

    /// Sample lyrics: six lines starting at 1, 5, 9, 13, 15.5 and 30 s, words 0.4 s apart ("harbour," held longer).
    static let sampleLyrics: TimedLyrics = {
        func line(_ texts: [String], from start: Double, number: Int) -> [TimedWord] {
            texts.enumerated().map { index, text in
                let wordStart = start + Double(index) * 0.4
                return TimedWord(text: text, start: wordStart, end: wordStart + (text.hasSuffix(",") ? 0.9 : 0.35), line: number)
            }
        }
        // Lines 0-1 run back to back; then come a short pause, a quick pair, and a long instrumental gap,
        // so styles that keep history (threads, stacks, maps) have something to show.
        let script: [(start: Double, words: [String])] = [
            (1, sampleLine),
            (5, ["while", "the", "tide", "forgets", "its", "name"]),
            (9, ["Wake", "me", "when", "the", "trains", "begin", "to", "sing"]),
            (13, ["we", "will", "walk", "the", "rooftops"]),
            (15.5, ["silver", "in", "the", "rain"]),
            (30, ["Hum", "it", "low", "so", "the", "city", "can", "rest"]),
        ]
        return TimedLyrics(tier: .wordLevel, words: script.enumerated().flatMap { number, entry in
            line(entry.words, from: entry.start, number: number)
        })
    }()

    static let defaultRenderPosition = 3.6
    static let mapTimeout = 40.0, mapPoll = 0.05

    /// The map's roads and pictures arrive asynchronously: turn the main run loop until this frame has them.
    @MainActor
    private static func waitForMap(_ context: StyleContext) -> Bool {
        let deadline = Date().addingTimeInterval(mapTimeout)
        while !MapStyle.isReady(context) {
            guard Date() < deadline else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(mapPoll))
        }
        return true
    }

    @MainActor
    static func render(style: LyricStyle, to path: String, position: Double, size: CGSize = CGSize(width: 1440, height: 900)) -> Bool {
        let lyrics = sampleLyrics
        guard let line = lyrics.line(at: position, alwaysDrawn: style.drawsWholeSong) else {
            print("nothing is on screen at \(position)s (the overlay is blank between lines)")
            return false
        }
        let settings = AppSettings.shared
        let context = StyleContext(line: line, lyrics: lyrics, position: position, clock: position, canvas: size,
                                   band: size.height * Layout.bandHeight, settings: settings, scale: style.scale(with: settings))
        let mapArrived = style != .map || waitForMap(context)
        if !mapArrived { print("map roads and pictures did not arrive within \(Int(mapTimeout)) s; drawing what there is") }
        // Drawn through the overlay's own stage, so size, footprint and a moved position come out as on screen.
        let view = ZStack {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
            LyricStage(style: style, lyrics: lyrics, position: position, clock: position, size: size, settings: settings,
                       offset: settings.lyricOffset(for: style))
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return mapArrived
        } catch {
            print("could not write \(path): \(error.localizedDescription)")
            return false
        }
    }
}

/// The view for one style. Shared by the live overlay and the diagnostic renderer.
@ViewBuilder
func styleView(_ style: LyricStyle, _ context: StyleContext) -> some View {
    switch style {
    case .ship: WordStackStyle(context: context, kind: .ship)
    case .visual: WordStackStyle(context: context, kind: .visual)
    case .fisheye: WordStackStyle(context: context, kind: .fisheye(icons: false))
    case .fisheyeVisual: WordStackStyle(context: context, kind: .fisheye(icons: true))
    case .codestyle: CodeStyle(context: context, icons: false)
    case .codestyleVisual: CodeStyle(context: context, icons: true)
    case .branches: BranchesStyle(context: context)
    case .web: WebStyle(context: context)
    case .constellation: ConstellationStyle(context: context)
    case .messages: MessagesStyle(context: context)
    case .money: MoneyStyle(context: context)
    case .notifications: NotificationsStyle(context: context)
    case .map: MapStyle(context: context)
    case .stretch: StretchStyle(context: context)
    case .ransomNote: RansomNoteStyle(context: context)
    case .ink: InkStyle(context: context)
    case .liquid: LiquidStyle(context: context)
    case .departureBoard: DepartureBoardStyle(context: context)
    case .score: ScoreStyle(context: context)
    case .highlighter: HighlighterStyle(context: context)
    case .receipt: ReceiptStyle(context: context)
    case .calendar: CalendarStyle(context: context)
    case .voiceMemo: VoiceMemoStyle(context: context)
    }
}
