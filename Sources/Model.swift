import Foundation

enum Timing {
    static let pollInterval = 0.5
    /// Replace the playback anchor only when a new sample disagrees by more than this (avoids jitter).
    static let resyncThreshold = 0.25
    /// Lyrics are shown slightly ahead of the audio so a word lands as it is heard.
    static let displayLead = 0.18
    /// A finished line stays on screen this long before the overlay goes blank.
    static let lineLinger = 0.8
}

struct Track: Equatable {
    let title: String
    let artist: String
    let duration: Double
}

struct Sample {
    let player: String
    let track: Track
    let position: Double
    let isPlaying: Bool
    let sampledAt: Date
}

/// A known playback position at a known moment; position in between is extrapolated.
struct Anchor {
    let position: Double
    let date: Date
    let rate: Double

    static let idle = Anchor(position: 0, date: .distantPast, rate: 0)

    func position(at now: Date) -> Double {
        rate == 0 ? position : position + rate * now.timeIntervalSince(date)
    }
}

enum LyricTier: String, Codable {
    case wordLevel
    case interpolated
}

struct TimedWord: Codable, Equatable {
    let text: String
    let start: Double
    let end: Double
    let line: Int

    func progress(at time: Double) -> Double {
        end > start ? min(1, max(0, (time - start) / (end - start))) : (time >= start ? 1 : 0)
    }
}

struct ActiveLine: Equatable {
    let index: Int
    let words: [TimedWord]
    /// How many words of the line have started; at least 1 so a line never appears empty.
    let shown: Int
}

struct TimedLyrics: Codable, Equatable {
    let tier: LyricTier
    let words: [TimedWord]
    let lines: [[TimedWord]]

    private enum CodingKeys: String, CodingKey { case tier, words }

    init(tier: LyricTier, words: [TimedWord]) {
        self.tier = tier
        self.words = words
        self.lines = words.reduce(into: [[TimedWord]]()) { lines, word in
            if let last = lines.last, last[0].line == word.line {
                lines[lines.count - 1] = last + [word]
            } else {
                lines.append([word])
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tier: try container.decode(LyricTier.self, forKey: .tier),
                  words: try container.decode([TimedWord].self, forKey: .words))
    }

    /// The line being sung at `time`, or nil before the first line, in a long gap, or after the end.
    func activeLine(at time: Double) -> ActiveLine? {
        guard let index = lines.lastIndex(where: { $0[0].start <= time }) else { return nil }
        let words = lines[index]
        guard time < (words.last?.end ?? 0) + Timing.lineLinger else { return nil }
        return ActiveLine(index: index, words: words, shown: max(1, words.filter { $0.start <= time }.count))
    }

    /// The line to hand a style at `time`. Styles that draw the whole song (threads, feeds, maps) are kept
    /// alive through gaps, so outside an active line they get the latest line begun, or the first one.
    func line(at time: Double, alwaysDrawn: Bool) -> ActiveLine? {
        if let active = activeLine(at: time) { return active }
        guard alwaysDrawn, !lines.isEmpty else { return nil }
        let index = lines.lastIndex { $0[0].start <= time } ?? 0
        return ActiveLine(index: index, words: lines[index], shown: max(1, lines[index].filter { $0.start <= time }.count))
    }
}
