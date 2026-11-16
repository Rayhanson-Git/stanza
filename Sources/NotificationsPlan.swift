import AppKit
import SwiftUI

/// Notifications, the model half. The per-song plan decides which kind of item every lyric line becomes,
/// how quick banners group into stacks and where each word sits; it is built once per song and cached.
/// The feed then places the few items that are on screen for one frame. Nothing is drawn here:
/// `NotificationsStyle.swift` paints what this file places.

// MARK: Shared tables

enum NotifyKind { case banner, assistant, widget, glance }

/// Sizes in design units: the feed is a column 402 units wide that the style scales to the band.
enum NotifyMetrics {
    static let columnWidth: CGFloat = 402
    static let bannerWidth: CGFloat = 370, bannerMinHeight: CGFloat = 62.33, bannerRadius: CGFloat = 22
    static let bannerTextX: CGFloat = 62.33, bannerHeadY: CGFloat = 12, bannerBodyY: CGFloat = 29
    static let bannerBottomPad: CGFloat = 15.33, bannerBodyWrap: CGFloat = 293.67, bannerHeadFit: CGFloat = 227.67
    static let panelWidth: CGFloat = 386, panelPadding: CGFloat = 24, panelWrap: CGFloat = 338, panelRadius: CGFloat = 35
    static let widgetSize = CGSize(width: 349.67, height: 164.33)
    static let widgetRadius: CGFloat = 28, widgetTextX: CGFloat = 18, widgetTextWidth: CGFloat = 313.67
    static let glanceSize = CGSize(width: 342, height: 72)
    static let pillSize = CGSize(width: 126, height: 40)
}

enum NotifyTables {
    static let tints: [Color] = [(10, 132, 255), (48, 209, 88), (255, 159, 10), (255, 55, 95),
                                 (191, 90, 242), (64, 200, 224), (94, 92, 230), (255, 69, 58)]
        .map { Color(.sRGB, red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }
    static let rainbow: [Color] = [(1, 0.4, 0.47), (1, 0.73, 0.44), (0.96, 0.73, 0.92), (0.74, 0.51, 0.95),
                                   (0.55, 0.62, 1), (0.42, 0.84, 0.98), (0.74, 0.51, 0.95), (1, 0.4, 0.47)]
        .map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2) }
    static let apps = ["music.note", "waveform", "headphones", "music.mic", "sparkles", "heart.fill",
                       "star.fill", "bolt.fill", "flame.fill", "moon.stars.fill", "bell.fill", "quote.bubble.fill"]
    static let glanceSymbol = "music.note"
}

enum NotifySalt {
    static let firstTint: UInt64 = 0x4E01, kind: UInt64 = 0x4E02, stack: UInt64 = 0x4E03, tintStep: UInt64 = 0x4E04
    static let app: UInt64 = 0x4E05, wobbleSign: UInt64 = 0x4E06, kickAngle: UInt64 = 0x4E07, kickTilt: UInt64 = 0x4E08
    static let slotTilt: UInt64 = 0x4E09, rainbowPhase: UInt64 = 0x4E0A, blobOrder: UInt64 = 0x4E0B, paletteStart: UInt64 = 0x4E0C
}

// MARK: Motion curves

enum NotifyMath {
    static let attack = 0.025       // every decaying wobble fades in over this, so nothing jumps on its first frame
    static let settled = 0.0005

    static func smooth(_ value: Double) -> Double {
        let x = min(max(value, 0), 1)
        return x * x * (3 - 2 * x)
    }

    static func lerp(_ from: CGFloat, _ to: CGFloat, _ fraction: CGFloat) -> CGFloat { from + (to - from) * fraction }

    /// A decaying sine with a soft attack: e^(−t/decay)·sin(ωt).
    static func ring(_ time: Double, decay: Double, omega: Double) -> Double {
        time > 0 ? exp(-time / decay) * sin(omega * time) * (1 - exp(-time / attack)) : 0
    }

    /// `ring` rescaled so that its first peak is 1.
    static func kick(_ time: Double, decay: Double, omega: Double) -> Double {
        guard time > 0 else { return 0 }
        let peak = atan(decay * omega) / omega
        return exp(-(time - peak) / decay) * sin(omega * time) / sin(omega * peak) * (1 - exp(-time / attack))
    }
}

/// An under-damped spring's step response: 0 until it is released, a small overshoot, then 1.
struct NotifySpring {
    let response: Double
    let damping: Double

    static let push = NotifySpring(response: 0.5, damping: 0.8)
    static let panel = NotifySpring(response: 0.51, damping: 0.6)
    static let stack = NotifySpring(response: 0.44, damping: 0.68)
    static let word = NotifySpring(response: 0.32, damping: 0.57)
    static let pill = NotifySpring(response: 0.37, damping: 0.6)

    func value(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let natural = 2 * Double.pi / response
        let root = (1 - damping * damping).squareRoot()
        let phase = natural * root * time
        let value = 1 - exp(-damping * natural * time) * (cos(phase) + damping / root * sin(phase))
        return abs(1 - value) < NotifyMath.settled ? 1 : value
    }
}

// MARK: Text layout

struct NotifyTextType {
    let size: CGFloat
    let weight: NSFont.Weight
    let lineHeight: CGFloat
    // Both fonts are made once here: the painter reads `font` for every layout on every frame.
    let nsFont: NSFont
    /// The same font the words were measured in, so drawn text lands exactly on the layout.
    let font: Font

    static let head = NotifyTextType(size: 15, weight: .semibold, lineHeight: 17)
    static let body = NotifyTextType(size: 15, weight: .regular, lineHeight: 18)
    static let panel = NotifyTextType(size: 20, weight: .regular, lineHeight: 22)

    init(size: CGFloat, weight: NSFont.Weight, lineHeight: CGFloat) {
        (self.size, self.weight, self.lineHeight) = (size, weight, lineHeight)
        nsFont = .systemFont(ofSize: size, weight: weight)
        font = Font(nsFont as CTFont)
    }
}

struct NotifyWord {
    let text: String
    let start: Double, end: Double
    /// Left edge and row top inside the layout.
    let x: CGFloat, y: CGFloat
    let width: CGFloat
    /// Held clearly longer than the line's other words: gets a bigger entrance.
    let isLong: Bool
    /// Which way the word leans as it lands (+1 or −1).
    let sign: Double
}

struct NotifyRow {
    let text: String
    let y: CGFloat
}

struct NotifyLayout {
    let type: NotifyTextType
    let words: [NotifyWord]
    let rows: [NotifyRow]
    let size: CGSize
    /// From here on nothing in the layout moves, so whole rows are drawn as plain text.
    let until: Double

    static let empty = NotifyLayout(type: .body, words: [], rows: [], size: .zero, until: -.infinity)
}

/// One lyric line measured in one font, ready to be wrapped at any width without measuring again.
struct NotifyMeasuredLine {
    let type: NotifyTextType
    let words: [TimedWord]
    let widths: [CGFloat]
    /// The space in front of each word: none before the first, none between two CJK characters.
    let gaps: [CGFloat]

    init(_ words: [TimedWord], type: NotifyTextType) {
        let attributes: [NSAttributedString.Key: Any] = [.font: type.nsFont]
        let space = (" " as NSString).size(withAttributes: attributes).width
        self.type = type
        self.words = words
        widths = words.map { ($0.text as NSString).size(withAttributes: attributes).width }
        gaps = words.indices.map { index in
            index == 0 || Self.runTogether(words[index - 1].text, words[index].text) ? 0 : space
        }
    }

    private static func runTogether(_ left: String, _ right: String) -> Bool {
        guard let last = left.unicodeScalars.last, let first = right.unicodeScalars.first else { return false }
        return isCJK(last) && isCJK(first)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x2E80...0x9FFF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value)
    }

    func width(ofFirst count: Int) -> CGFloat {
        widths.prefix(count).reduce(0, +) + gaps.prefix(count).dropFirst().reduce(0, +)
    }

    /// Greedy wrap. A word wider than the limit gets a row to itself; nothing is truncated.
    func layout(wrappedAt limit: CGFloat, longDuration: Double) -> NotifyLayout {
        var placed: [NotifyWord] = [], rows: [NotifyRow] = []
        var cursor: CGFloat = 0, widest: CGFloat = 0, text = ""
        for (index, word) in words.enumerated() {
            if cursor > 0 && cursor + gaps[index] + widths[index] > limit {
                rows.append(NotifyRow(text: text, y: CGFloat(rows.count) * type.lineHeight))
                cursor = 0
                text = ""
            }
            let left = cursor > 0 ? cursor + gaps[index] : 0
            text += (cursor > 0 && gaps[index] > 0 ? " " : "") + word.text
            placed.append(NotifyWord(text: word.text, start: word.start, end: word.end, x: left,
                                     y: CGFloat(rows.count) * type.lineHeight, width: widths[index],
                                     isLong: word.end - word.start >= longDuration,
                                     sign: seededUnit(word.start, salt: NotifySalt.wobbleSign) >= 0.5 ? 1 : -1))
            cursor = left + widths[index]
            widest = max(widest, cursor)
        }
        if !words.isEmpty { rows.append(NotifyRow(text: text, y: CGFloat(rows.count) * type.lineHeight)) }
        let until = words.map { max($0.end + NotifyRules.holdAfterEnd, $0.start + NotifyRules.holdAfterStart) }.max() ?? -.infinity
        return NotifyLayout(type: type, words: placed, rows: rows,
                            size: CGSize(width: widest, height: CGFloat(rows.count) * type.lineHeight), until: until)
    }
}

// MARK: Plan

private enum NotifyRules {
    static let glanceGap = 6.0, glanceDelay = 1.0, firstGlanceLead = 14.0, firstGlanceEarliest = 0.2
    static let longGap = 12.0
    static let widgetSpacing = 16.0, widgetMinWords = 2, widgetRoll = 0.24
    static let panelSpacing = 9.0, panelMinWords = 3, panelRoll = 0.14
    static let stackGap = 1.6, stackMaxRun = 2, stackSkipRoll = 0.3
    static let tintStepSpread = 3.0
    static let leadMinGap = 1.0, leadTrim = 0.25, leadMax = 2.4
    static let longWord = 1.6, minAveragedDuration = 0.01
    static let holdAfterEnd = 0.4, holdAfterStart = 1.2
    // Banner title
    static let shortLine = 4
    static let headBreakPause = 0.28
    static let headBreakMarks: Set<Character> = [",", ".", ";", ":", "!", "?", "…"]
    // Widget text fit
    static let widgetSizes: [CGFloat] = [30, 26, 22, 19, 16]
    static let widgetLineHeight: CGFloat = 34, widgetLineHeightRatio: CGFloat = 1.12
    static let widgetMaxTextHeight: CGFloat = 86
    static let rebalanceWidest: CGFloat = 294.8498, rebalanceStep: CGFloat = 18.8202, rebalanceNarrowest: CGFloat = 156.835
    static let cacheSize = 2
}

/// A line that reads like something said to an assistant.
enum NotifyQuestion {
    private static let openers: Set<String> = ["what", "whats", "where", "wheres", "who", "whos", "why", "when", "how", "hey", "siri", "tell"]
    private static let auxiliaries: Set<String> = ["do", "does", "did", "can", "could", "would", "will", "should", "are", "is", "was", "have", "has"]
    private static let subjects: Set<String> = ["you", "it", "this", "we", "i", "she", "he", "they"]

    static func matches(_ texts: [String]) -> Bool {
        let plain = texts.prefix(2).map { $0.lowercased().filter(\.isLetter) }
        guard let first = plain.first else { return false }
        let asksBack = plain.count > 1 && auxiliaries.contains(first) && subjects.contains(plain[1])
        return texts.contains { $0.hasSuffix("?") } || openers.contains(first) || asksBack
    }
}

struct NotifyIcon {
    /// Song time from which this glyph shows; −∞ for the one the item arrives with.
    let at: Double
    let name: String
}

struct NotifyItem {
    let kind: NotifyKind
    let start: Double, end: Double
    /// How long before `start` the listening pill appears (assistant panels after a pause only).
    let lead: Double
    let head: NotifyLayout, body: NotifyLayout
    /// Head and body words in sung order.
    let words: [NotifyWord]
    let size: CGSize
    let tint: Color
    let icons: [NotifyIcon]
    var seed: Double { start }

    static func glance(from start: Double, to end: Double) -> NotifyItem {
        NotifyItem(kind: .glance, start: start, end: end, lead: 0, head: .empty, body: .empty, words: [],
                   size: NotifyMetrics.glanceSize, tint: .white, icons: [NotifyIcon(at: -.infinity, name: NotifyTables.glanceSymbol)])
    }
}

/// Turns one lyric line into the text layouts and card size of each kind.
enum NotifyTypesetter {
    typealias Fit = (head: NotifyLayout, body: NotifyLayout, size: CGSize)

    static func fit(_ line: [TimedWord], as kind: NotifyKind) -> Fit {
        let long = longDuration(of: line)
        switch kind {
        case .banner: return banner(line, long: long)
        case .assistant:
            let body = NotifyMeasuredLine(line, type: .panel).layout(wrappedAt: NotifyMetrics.panelWrap, longDuration: long)
            return (.empty, body, CGSize(width: NotifyMetrics.panelWidth, height: body.size.height + 2 * NotifyMetrics.panelPadding))
        case .widget: return (.empty, widgetText(line, long: long), NotifyMetrics.widgetSize)
        case .glance: return (.empty, .empty, NotifyMetrics.glanceSize)
        }
    }

    private static func longDuration(of line: [TimedWord]) -> Double {
        guard line.count > 1 else { return .infinity }
        let total = line.reduce(0) { $0 + max($1.end - $1.start, NotifyRules.minAveragedDuration) }
        return NotifyRules.longWord * total / Double(line.count)
    }

    private static func banner(_ line: [TimedWord], long: Double) -> Fit {
        let count = headCount(of: line)
        let head = NotifyMeasuredLine(Array(line[..<count]), type: .head).layout(wrappedAt: .infinity, longDuration: long)
        let body = NotifyMeasuredLine(Array(line[count...]), type: .body).layout(wrappedAt: NotifyMetrics.bannerBodyWrap, longDuration: long)
        let height = max(body.size.height + NotifyMetrics.bannerBodyY + NotifyMetrics.bannerBottomPad, NotifyMetrics.bannerMinHeight)
        return (head, body, CGSize(width: NotifyMetrics.bannerWidth, height: height))
    }

    /// How many leading words form the banner's one-row title: up to the first natural break, shortened until it fits.
    static func headCount(of line: [TimedWord]) -> Int {
        let count = line.count
        let measured = NotifyMeasuredLine(Array(line.prefix(NotifyRules.shortLine)), type: .head)
        func fits(_ words: Int) -> Bool { measured.width(ofFirst: words) <= NotifyMetrics.bannerHeadFit }
        guard count >= NotifyRules.shortLine else { return fits(count) ? count : 1 }
        let furthest = min(count - 2, NotifyRules.shortLine)
        let fallback = min(furthest, NotifyRules.shortLine - 1)
        let natural = (2...furthest).first { breaks(after: $0, in: line) } ?? fallback
        return stride(from: natural, through: 2, by: -1).first(where: fits) ?? 1
    }

    private static func breaks(after count: Int, in line: [TimedWord]) -> Bool {
        let word = line[count - 1]
        let endsPhrase = word.text.last.map(NotifyRules.headBreakMarks.contains) ?? false
        return endsPhrase || line[count].start - word.end >= NotifyRules.headBreakPause
    }

    /// The widget's big lyric: the largest size whose rows fit, with rows evened out.
    private static func widgetText(_ line: [TimedWord], long: Double) -> NotifyLayout {
        func attempt(_ size: CGFloat) -> NotifyLayout {
            let isLargest = size == NotifyRules.widgetSizes[0]
            let lineHeight = isLargest ? NotifyRules.widgetLineHeight : (NotifyRules.widgetLineHeightRatio * size).rounded()
            return balanced(NotifyMeasuredLine(line, type: NotifyTextType(size: size, weight: .bold, lineHeight: lineHeight)), long: long)
        }
        let smallest = NotifyRules.widgetSizes[NotifyRules.widgetSizes.count - 1]
        return NotifyRules.widgetSizes.lazy.map(attempt).first { $0.size.height <= NotifyRules.widgetMaxTextHeight } ?? attempt(smallest)
    }

    /// Narrows a multi-row layout as far as it goes without adding a row, so the rows come out similar in length.
    private static func balanced(_ measured: NotifyMeasuredLine, long: Double) -> NotifyLayout {
        let full = measured.layout(wrappedAt: NotifyMetrics.widgetTextWidth, longDuration: long)
        guard full.rows.count > 1 else { return full }
        var best = full
        for width in stride(from: NotifyRules.rebalanceWidest, through: NotifyRules.rebalanceNarrowest, by: -NotifyRules.rebalanceStep) {
            let narrower = measured.layout(wrappedAt: width, longDuration: long)
            guard narrower.rows.count <= full.rows.count else { break }
            best = narrower
        }
        return best
    }
}

/// Walks the lines once, in order, carrying what the rules need to remember.
private struct NotifyPlanBuilder {
    private(set) var items: [NotifyItem] = []
    private(set) var slots: [Range<Int>] = []
    private var isFirst = true
    private var previousEnd = 0.0
    private var previousKind: NotifyKind?
    private var lastWidget = -Double.infinity, lastPanel = -Double.infinity
    private var run = 0
    private var tintIndex: Int
    private var app = NotifyTables.apps[0]

    init(firstStart: Double) {
        tintIndex = Int(seededUnit(firstStart, salt: NotifySalt.firstTint) * Double(NotifyTables.tints.count))
    }

    mutating func add(_ line: [TimedWord]) {
        // Overlapping voices need not be in time order: a line spans its earliest start to its latest end.
        guard let start = line.map(\.start).min(), let end = line.map(\.end).max() else { return }
        let rawGap = start - previousEnd
        let gap = addGlance(before: start, rawGap: rawGap)
        let kind = kind(for: line, at: start, afterGap: isFirst || rawGap >= NotifyRules.longGap)
        let joins = kind == .banner && previousKind == .banner && gap < NotifyRules.stackGap && run <= NotifyRules.stackMaxRun
            && seededUnit(start, salt: NotifySalt.stack) >= NotifyRules.stackSkipRoll
        if joins {
            run += 1
            slots[slots.count - 1] = slots[slots.count - 1].lowerBound..<items.count + 1
        } else {
            run = 1
            tintIndex += Int(seededUnit(start, salt: NotifySalt.tintStep) * NotifyRules.tintStepSpread) + 1
            app = NotifyTables.apps[Int(seededUnit(start, salt: NotifySalt.app) * Double(NotifyTables.apps.count)) % NotifyTables.apps.count]
            slots.append(items.count..<items.count + 1)
        }
        let lead = kind == .assistant && gap >= NotifyRules.leadMinGap ? min(gap - NotifyRules.leadTrim, NotifyRules.leadMax) : 0
        items.append(item(kind, line: line, start: start, end: end, lead: lead))
        if kind == .widget { lastWidget = start }
        if kind == .assistant { lastPanel = start }
        (isFirst, previousEnd, previousKind) = (false, end, kind)
    }

    /// A long silence gets a glance row in a slot of its own. Returns the gap the remaining rules see.
    private mutating func addGlance(before start: Double, rawGap: Double) -> Double {
        guard rawGap >= NotifyRules.glanceGap else { return rawGap }
        let from = isFirst ? max(NotifyRules.firstGlanceEarliest, start - NotifyRules.firstGlanceLead) : previousEnd + NotifyRules.glanceDelay
        slots.append(items.count..<items.count + 1)
        items.append(.glance(from: from, to: start))
        previousKind = .glance
        return isFirst ? rawGap : 0
    }

    private func kind(for line: [TimedWord], at start: Double, afterGap: Bool) -> NotifyKind {
        let widgetDue = line.count >= NotifyRules.widgetMinWords && start - lastWidget >= NotifyRules.widgetSpacing
        let panelDue = line.count >= NotifyRules.panelMinWords && start - lastPanel >= NotifyRules.panelSpacing
        let roll = seededUnit(start, salt: NotifySalt.kind)
        let wanted: NotifyKind
        if widgetDue && afterGap {
            wanted = .widget
        } else if panelDue && (NotifyQuestion.matches(line.map(\.text)) || roll < NotifyRules.panelRoll) {
            wanted = .assistant
        } else if widgetDue && roll < NotifyRules.widgetRoll {
            wanted = .widget
        } else {
            wanted = .banner
        }
        // Two panels or two widgets back to back would read as one card changing its text.
        return wanted != .banner && wanted == previousKind ? .banner : wanted
    }

    private func item(_ kind: NotifyKind, line: [TimedWord], start: Double, end: Double, lead: Double) -> NotifyItem {
        let fit = NotifyTypesetter.fit(line, as: kind)
        // Word symbols are looked up once, here; `NotifyPlanCache` rebuilds the plan when later ones arrive.
        let symbols = line.compactMap { word -> NotifyIcon? in
            guard case .symbol(let name)? = WordVisuals.shared.visual(for: word.text) else { return nil }
            return NotifyIcon(at: word.start, name: name)
        }
        return NotifyItem(kind: kind, start: start, end: end, lead: lead, head: fit.head, body: fit.body,
                          words: fit.head.words + fit.body.words, size: fit.size,
                          tint: NotifyTables.tints[tintIndex % NotifyTables.tints.count],
                          icons: [NotifyIcon(at: -.infinity, name: app)] + symbols)
    }
}

final class NotifyPlan {
    let items: [NotifyItem]
    /// Runs of items that share one place in the feed: a single item, or a stack of up to three banners.
    let slots: [Range<Int>]
    let slotOf: [Int]
    /// Where the last word ends.
    let length: Double

    init(lyrics: TimedLyrics) {
        // An empty word would leave a doubled space in its row.
        let lines = lyrics.lines.map { $0.filter { !$0.text.isEmpty } }.filter { !$0.isEmpty }
        var builder = NotifyPlanBuilder(firstStart: lines.first?[0].start ?? 0)
        lines.forEach { builder.add($0) }
        items = builder.items
        slots = builder.slots
        slotOf = builder.slots.enumerated().flatMap { index, range in Array(repeating: index, count: range.count) }
        length = lyrics.words.map(\.end).max() ?? 0
    }

    /// The newest item that has started. Not a binary search: with overlapping voices the starts need not be in order.
    func currentIndex(at position: Double) -> Int? { items.lastIndex { $0.start <= position } }
}

/// The plans of the last two songs, so a frame never rebuilds one. Main actor only; hence no lock.
@MainActor enum NotifyPlanCache {
    private struct Entry {
        /// Compared whole, so corrected lyrics of the same shape get a new plan.
        let lyrics: TimedLyrics
        /// `WordVisuals.revision` when the plan was built: it holds the word symbols known at that moment.
        let revision: Int
        let plan: NotifyPlan
    }

    private static var entries: [Entry] = []

    static func plan(for lyrics: TimedLyrics) -> NotifyPlan {
        let revision = WordVisuals.shared.revision
        // Arrays that share storage compare without looking at their elements, which is the case on every frame of a song.
        if let hit = entries.first(where: { $0.lyrics == lyrics }), hit.revision == revision { return hit.plan }
        let plan = NotifyPlan(lyrics: lyrics)
        // A plan rebuilt for new word symbols replaces its predecessor, so the other song keeps its place.
        let others = entries.filter { $0.lyrics != lyrics }
        entries = Array((others + [Entry(lyrics: lyrics, revision: revision, plan: plan)]).suffix(NotifyRules.cacheSize))
        return plan
    }
}
