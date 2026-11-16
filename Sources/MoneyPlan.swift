import AppKit
import SwiftUI

/// Money, part 1: what the feed contains. `MoneyPlan` cuts a song into feed items once per song: chunks of
/// a few words, each with a side, a kind and a finished text layout. `MoneyFeed.swift` then places the few
/// visible items for one frame. All lengths are in "feed points": the feed is 402 points wide and scaled to
/// the lyric band by the style.

// MARK: - Shared maths

enum MoneyMath {
    static func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double { min(max(value, low), high) }

    static func smoothstep(_ value: Double) -> Double {
        let unit = clamp(value)
        return unit * unit * (3 - 2 * unit)
    }

    /// Step response of an under-damped spring: 0 until `time` 0, then it overshoots and settles at 1.
    static func spring(_ time: Double, response: Double, damping: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        let damped = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * omega * time) * (cos(damped * time) + damping * omega / damped * sin(damped * time))
    }

    /// A decaying wobble that starts at 1.
    static func ring(_ time: Double) -> Double { time < 0 ? 0 : exp(-time / ringDecay) * cos(ringSpeed * time) }

    private static let ringDecay = 0.16, ringSpeed = 15.0
}

// MARK: - Constants

private enum Chunking {
    static let maxWords = 3, maxShortCJKWords = 5, shortWordLength = 2
    static let minWordsBeforeBreak = 2, breakPause = 0.28
    static let clauseEnders: Set<Character> = [",", ".", ";", ":", "!", "?", "…"]
    static let cjkRanges: [ClosedRange<UInt32>] = [0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF,
                                                   0xF900...0xFAFF, 0xFF66...0xFF9F]
}

private enum Casting {
    static let sideFlipGap = 0.7, maxRun = 3, sideFlipChance = 0.25
    static let sectionGap = 12.0, cardSpacing = 25.0
    // One draw per chunk picks its kind; these are the upper ends of each kind's slice of 0..<1.
    static let messageBelow = 0.10, cashBelow = 0.32, payBelow = 0.46, cardBelow = 0.54, mapBelow = 0.74
    static let leadMinGap = 1.0, leadTrim = 0.25, maxLead = 2.4
    static let moneyWords: Set<String> = [
        "money", "cash", "pay", "paid", "payday", "dollar", "dollars", "bucks", "cents", "penny", "dime", "coin", "coins",
        "bank", "bill", "bills", "check", "rich", "wealth", "wealthy", "fortune", "gold", "diamond", "diamonds", "price",
        "cost", "buy", "bought", "spend", "spent", "broke", "debt", "loan", "rent", "owe", "wallet", "credit", "salary",
        "million", "millions", "billion", "bands", "racks", "stacks", "bread", "dough", "treasure", "jackpot",
    ]
    static let bubbleIcons = ["dollarsign"]
    static let islandIcons = ["music.note", "waveform", "headphones", "music.mic", "sparkles", "bolt.fill", "heart.fill",
                              "star.fill", "flame.fill", "moon.stars.fill"]
    static let cardIcons = ["music.note", "music.mic", "waveform", "music.quarternote.3"]
    static let payIcons = ["creditcard.fill"]
    static let mapIcons = ["map.fill", "mappin.and.ellipse", "location.fill", "signpost.right.fill"]
}

private enum Typeset {
    static let cashFaces: [(size: CGFloat, lineHeight: CGFloat)] = [(44, 50), (36, 41), (30, 34), (25, 28)]
    static let cashTypes = cashFaces.map { MoneyType(size: $0.size, lineHeight: $0.lineHeight, weight: .semibold, isRounded: true) }
    static let cashWrap: CGFloat = 218, cashMaxLines = 2
    static let cardFaces: [(size: CGFloat, lineHeight: CGFloat)] = [(18, 23), (16, 20), (14, 17.5), (12.5, 15.625)]
    static let cardTypes = cardFaces.map { MoneyType(size: $0.size, lineHeight: $0.lineHeight, weight: .medium) }
    static let cardWrap: CGFloat = 274, cardMaxHeight: CGFloat = 48
    static let balanceStart = 0.94, balanceStep = 0.06, balanceEnd = 0.5
    static let island = MoneyType(size: 20, lineHeight: 24, weight: .medium), islandWrap: CGFloat = 266
    static let pay = MoneyType(size: 27, lineHeight: 32, weight: .regular, kerning: 1.04), payWrap: CGFloat = 284
    static let map = MoneyType(size: 17, lineHeight: 22, weight: .semibold), mapWrap: CGFloat = 260
    static let message = MoneyType(size: 17, lineHeight: 20, weight: .regular), messageWrap: CGFloat = 272
    /// Every type the feed is set in.
    static let all = cashTypes + cardTypes + [island, pay, map, message]
    static let longWord = 1.6                   // held this many times the chunk's mean duration
    static let lingerAfterEnd = 0.4, minLinger = 1.2
}

private enum Box {
    static let cashWidth: CGFloat = 250, cashChrome: CGFloat = 66
    static let islandWidth: CGFloat = 374, islandMinText: CGFloat = 44, islandChrome: CGFloat = 88
    static let payWidth: CGFloat = 374, payChrome: CGFloat = 58
    static let mapWidth: CGFloat = 340, mapChrome: CGFloat = 40
    static let messageMinWidth: CGFloat = 40, messagePadding = CGSize(width: 28, height: 20)
}

private enum Salt {
    static let wordSign: UInt64 = 0xD011, side: UInt64 = 0xD012, kind: UInt64 = 0xD013, icon: UInt64 = 0xD014
    static let islandTint: UInt64 = 0xD015, cardTint: UInt64 = 0xD016, mapTint: UInt64 = 0xD017
}

enum MoneyPalette {
    static let green = Color(red: 0.188, green: 0.820, blue: 0.345), blue = Color(red: 0, green: 0.569, blue: 1)
    static let seven: [Color] = [green, Color(red: 0.039, green: 0.518, blue: 1), Color(red: 1, green: 0.624, blue: 0.039),
                                 Color(red: 1, green: 0.216, blue: 0.373), Color(red: 0.749, green: 0.353, blue: 0.949),
                                 Color(red: 0.251, green: 0.784, blue: 0.878), Color(red: 1, green: 0.839, blue: 0.039)]

    static func pick(_ seed: Double, salt: UInt64, offset: Int = 0) -> Color {
        seven[(Int(seededUnit(seed, salt: salt) * Double(seven.count)) + offset) % seven.count]
    }
}

// MARK: - Model

enum MoneyKind: Equatable {
    case cash, island, card, pay, map, message

    /// Bubbles hug one side of the feed and have a tail; every other kind is a centred platter.
    var isBubble: Bool { self == .cash || self == .message }
}

enum MoneyWeight {
    case regular, medium, semibold

    var appKit: NSFont.Weight { self == .regular ? .regular : self == .medium ? .medium : .semibold }
    var swiftUI: Font.Weight { self == .regular ? .regular : self == .medium ? .medium : .semibold }
}

struct MoneyType: Hashable {
    let size: CGFloat
    let lineHeight: CGFloat
    let weight: MoneyWeight
    var isRounded = false
    var kerning: CGFloat = 0

    var font: Font { .system(size: size, weight: weight.swiftUI, design: isRounded ? .rounded : .default) }

    /// The AppKit twin of `font`, for measuring.
    var measuringFont: NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight.appKit)
        guard isRounded, let rounded = plain.fontDescriptor.withDesign(.rounded) else { return plain }
        return NSFont(descriptor: rounded, size: size) ?? plain
    }
}

struct MoneyWord {
    let text: String
    let start: Double
    let end: Double
    /// Left edge and line top inside the text block.
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let isLong: Bool
    /// Which way the word leans as it lands.
    let sign: Double
    /// From here on the word is drawn plainly.
    let lingerEnd: Double
}

struct MoneyLine {
    let text: String
    let x: CGFloat
    let y: CGFloat
}

struct MoneyText {
    let words: [MoneyWord]
    let lines: [MoneyLine]
    let size: CGSize
    let type: MoneyType
    /// Once every word has landed the block is drawn line by line.
    let settledAt: Double
}

struct MoneyItem {
    let kind: MoneyKind
    let outgoing: Bool
    let start: Double
    let end: Double
    /// Seconds before `start` at which a small pill announces the item (0 = none).
    let lead: Double
    let text: MoneyText
    /// The item's box, before the wallet card is fitted to the band and before a map picture is added.
    let size: CGSize
    let tint: Color
    /// The symbol shown until a pictured word is sung.
    let icon: String
    var seed: Double { start }
}

// MARK: - Chunking and casting

enum MoneyScript {
    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in Chunking.cjkRanges.contains { $0.contains(scalar.value) } }
    }

    /// Cuts a line into chunks of at most three words (five for short CJK words), preferring pauses and commas.
    static func chunks(of line: [TimedWord]) -> [[TimedWord]] {
        let isShortCJK = line.allSatisfy { $0.text.count <= Chunking.shortWordLength } && line.contains { $0.text.contains(where: isCJK) }
        let maxWords = isShortCJK ? Chunking.maxShortCJKWords : Chunking.maxWords
        guard line.count > maxWords else { return line.isEmpty ? [] : [line] }
        let chunks = line.indices.reduce(into: [[TimedWord]]([[]])) { chunks, index in
            let word = line[index]
            chunks[chunks.count - 1].append(word)
            guard index + 1 < line.count else { return }
            let count = chunks[chunks.count - 1].count
            let pauses = line[index + 1].start - word.end >= Chunking.breakPause
                || word.text.last.map(Chunking.clauseEnders.contains) == true
            if count >= maxWords || (count >= Chunking.minWordsBeforeBreak && pauses) { chunks.append([]) }
        }
        return mergingLoneTail(chunks, maxWords: maxWords)
    }

    /// A last chunk of one word joins its neighbour, or takes that neighbour's last word when it is full.
    private static func mergingLoneTail(_ chunks: [[TimedWord]], maxWords: Int) -> [[TimedWord]] {
        guard chunks.count > 1, let tail = chunks.last, tail.count == 1 else { return chunks }
        let previous = chunks[chunks.count - 2]
        let head = Array(chunks.dropLast(2))
        guard previous.count >= maxWords, let moved = previous.last else { return head + [previous + tail] }
        return head + [Array(previous.dropLast()), [moved] + tail]
    }

    static func mentionsMoney(_ chunk: [TimedWord]) -> Bool {
        chunk.contains { Casting.moneyWords.contains($0.text.lowercased().filter(\.isLetter)) }
    }

    /// No kind comes twice in a row, except the island.
    static func kind(of chunk: [TimedWord], opensSection: Bool, cardAllowed: Bool, previous: MoneyKind?) -> MoneyKind {
        let picked = freeKind(of: chunk, opensSection: opensSection, cardAllowed: cardAllowed)
        return picked == previous ? .island : picked
    }

    private static func freeKind(of chunk: [TimedWord], opensSection: Bool, cardAllowed: Bool) -> MoneyKind {
        if opensSection && cardAllowed { return .card }
        if mentionsMoney(chunk) { return .pay }
        let draw = seededUnit(chunk[0].start, salt: Salt.kind)
        if draw < Casting.messageBelow { return .message }
        if draw < Casting.cashBelow { return .cash }
        if draw < Casting.payBelow { return .pay }
        if draw < Casting.cardBelow && cardAllowed { return .card }
        return draw < Casting.mapBelow ? .map : .island
    }

    static func icon(for kind: MoneyKind, seed: Double) -> String {
        let table: [String]
        switch kind {
        case .cash, .message: table = Casting.bubbleIcons
        case .island: table = Casting.islandIcons
        case .card: table = Casting.cardIcons
        case .pay: table = Casting.payIcons
        case .map: table = Casting.mapIcons
        }
        return table[Int(seededUnit(seed, salt: Salt.icon) * Double(table.count)) % table.count]
    }

    static func tint(for kind: MoneyKind, seed: Double) -> Color {
        switch kind {
        case .cash: return MoneyPalette.green
        case .pay, .message: return MoneyPalette.blue
        case .island: return MoneyPalette.pick(seed, salt: Salt.islandTint)
        case .card: return MoneyPalette.pick(seed, salt: Salt.cardTint)
        case .map: return MoneyPalette.pick(seed, salt: Salt.mapTint)
        }
    }
}

// MARK: - Text layout

enum MoneyTypesetter {
    private struct Placed {
        let index: Int
        let x: CGFloat
        let width: CGFloat
        let spaceBefore: Bool
    }

    static func text(for chunk: [TimedWord], kind: MoneyKind) -> MoneyText {
        switch kind {
        case .cash: return cashText(chunk)
        case .card: return cardText(chunk)
        case .island: return set(chunk, type: Typeset.island, wrap: Typeset.islandWrap)
        case .pay: return set(chunk, type: Typeset.pay, wrap: Typeset.payWrap)
        case .map: return set(chunk, type: Typeset.map, wrap: Typeset.mapWrap)
        case .message: return set(chunk, type: Typeset.message, wrap: Typeset.messageWrap)
        }
    }

    static func box(for kind: MoneyKind, text: CGSize) -> CGSize {
        switch kind {
        case .cash: return CGSize(width: Box.cashWidth, height: text.height + Box.cashChrome)
        case .island: return CGSize(width: Box.islandWidth, height: max(text.height, Box.islandMinText) + Box.islandChrome)
        case .card: return MoneyGeometry.cardSize
        case .pay: return CGSize(width: Box.payWidth, height: text.height + Box.payChrome)
        case .map: return CGSize(width: Box.mapWidth, height: text.height + Box.mapChrome)
        case .message: return CGSize(width: max(Box.messageMinWidth, text.width + Box.messagePadding.width),
                                     height: text.height + Box.messagePadding.height)
        }
    }

    /// The largest rounded face that fits the cash bubble in two lines.
    private static func cashText(_ chunk: [TimedWord]) -> MoneyText {
        let attempts = Typeset.cashTypes.lazy.map { set(chunk, type: $0, wrap: Typeset.cashWrap, isCentred: true) }
        let fitting = attempts.first { $0.lines.count <= Typeset.cashMaxLines && $0.size.width <= Typeset.cashWrap }
        return fitting ?? attempts[Typeset.cashTypes.count - 1]
    }

    /// The largest face that fits the card's text area, with lines of similar length.
    private static func cardText(_ chunk: [TimedWord]) -> MoneyText {
        let attempts = Typeset.cardTypes.lazy.map { balanced(chunk, type: $0, wrap: Typeset.cardWrap) }
        return attempts.first { $0.size.height <= Typeset.cardMaxHeight } ?? attempts[Typeset.cardTypes.count - 1]
    }

    /// Narrows the wrap width for as long as that does not add a line, so the last line is not a lone word.
    private static func balanced(_ chunk: [TimedWord], type: MoneyType, wrap: CGFloat) -> MoneyText {
        let loose = set(chunk, type: type, wrap: wrap)
        let fractions = stride(from: Typeset.balanceStart, through: Typeset.balanceEnd - Typeset.balanceStep / 2, by: -Typeset.balanceStep)
        var best = loose
        for fraction in fractions {
            let tighter = set(chunk, type: type, wrap: wrap * fraction)
            guard tighter.lines.count <= loose.lines.count else { break }
            best = tighter
        }
        return best
    }

    /// What AppKit measures a word with, made once for each of the feed's types: creating the font is the
    /// costly part of setting a chunk, and a song is hundreds of chunks, most of them set several times over.
    private static let measuring: [MoneyType: [NSAttributedString.Key: Any]] = Dictionary(
        Typeset.all.map { ($0, attributes(for: $0)) }, uniquingKeysWith: { first, _ in first })

    private static func attributes(for type: MoneyType) -> [NSAttributedString.Key: Any] {
        [.font: type.measuringFont, .kern: type.kerning]
    }

    /// Greedy wrap of a chunk, measured with AppKit so the canvas can place every word on its own.
    static func set(_ chunk: [TimedWord], type: MoneyType, wrap: CGFloat, isCentred: Bool = false) -> MoneyText {
        let attributes = measuring[type] ?? Self.attributes(for: type)
        func width(_ string: String) -> CGFloat { ceil((string as NSString).size(withAttributes: attributes).width * 100) / 100 }
        let space = width(" ")
        let rows = chunk.indices.reduce(into: [[Placed]]([[]])) { rows, index in
            let wordWidth = width(chunk[index].text)
            let spaced = index > 0 && !joinsTightly(chunk[index - 1].text, chunk[index].text)
            let cursor = rows[rows.count - 1].last.map { $0.x + $0.width + (spaced ? space : 0) } ?? 0
            if cursor > 0 && cursor + wordWidth > wrap {
                rows.append([Placed(index: index, x: 0, width: wordWidth, spaceBefore: false)])
            } else {
                rows[rows.count - 1].append(Placed(index: index, x: cursor, width: wordWidth, spaceBefore: spaced && cursor > 0))
            }
        }.filter { !$0.isEmpty }
        let rowWidths = rows.map { ($0.last?.x ?? 0) + ($0.last?.width ?? 0) }
        let blockWidth = rowWidths.max() ?? 0
        let insets = rowWidths.map { isCentred ? (blockWidth - $0) / 2 : 0 }
        let mean = chunk.reduce(0) { $0 + ($1.end - $1.start) } / Double(max(chunk.count, 1))
        let words = rows.enumerated().flatMap { row, placed in
            placed.map { word(chunk[$0.index], at: CGPoint(x: insets[row] + $0.x, y: CGFloat(row) * type.lineHeight), width: $0.width, mean: mean) }
        }
        let lines = rows.enumerated().map { row, placed in
            MoneyLine(text: placed.reduce("") { $0 + ($1.spaceBefore ? " " : "") + chunk[$1.index].text },
                      x: insets[row], y: CGFloat(row) * type.lineHeight)
        }
        return MoneyText(words: words, lines: lines, size: CGSize(width: blockWidth, height: CGFloat(rows.count) * type.lineHeight),
                         type: type, settledAt: words.map(\.lingerEnd).max() ?? 0)
    }

    private static func joinsTightly(_ left: String, _ right: String) -> Bool {
        guard let last = left.last, let first = right.first else { return true }
        return MoneyScript.isCJK(last) && MoneyScript.isCJK(first)
    }

    private static func word(_ source: TimedWord, at origin: CGPoint, width: CGFloat, mean: Double) -> MoneyWord {
        MoneyWord(text: source.text, start: source.start, end: source.end, x: origin.x, y: origin.y, width: width,
                  // Words without any duration are all equally short, not all "held".
                  isLong: mean > 0 && source.end - source.start >= Typeset.longWord * mean,
                  sign: seededUnit(source.start, salt: Salt.wordSign) >= 0.5 ? 1 : -1,
                  lingerEnd: max(source.end + Typeset.lingerAfterEnd, source.start + Typeset.minLinger))
    }
}

// MARK: - The plan

/// Every feed item of one song, oldest first. Independent of the screen, the text scale and the track's art.
struct MoneyPlan {
    let items: [MoneyItem]
    /// For each map item, the island that is drawn instead while its picture is not ready; nil for other kinds.
    let islandTwins: [MoneyItem?]
    /// Start times of the map items, for fetching their pictures ahead of time.
    let mapStarts: [Double]

    init(lyrics: TimedLyrics) {
        let drafts = lyrics.lines.reduce(into: Draft()) { draft, line in draft.add(line) }
        let order = drafts.items.indices.sorted { (drafts.items[$0].start, $0) < (drafts.items[$1].start, $1) }
        items = order.map { drafts.items[$0] }
        islandTwins = order.map { drafts.twins[$0] }
        mapStarts = items.filter { $0.kind == .map }.map(\.start)
    }

    /// The last item that has started, by binary search.
    func newestIndex(at position: Double) -> Int? {
        var low = 0, high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].start <= position { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }

    /// Running state while the song is cut up line by line.
    private struct Draft {
        var items: [MoneyItem] = []
        var twins: [MoneyItem?] = []
        var previousEnd: Double?
        var previousKind: MoneyKind?
        var lastCardStart = -Double.infinity
        var outgoing = false
        var run = 0

        mutating func add(_ line: [TimedWord]) {
            guard let lineStart = line.first?.start else { return }
            let gapBefore = previousEnd.map { lineStart - $0 }
            if let gapBefore, gapBefore >= Casting.sideFlipGap || run >= Casting.maxRun
                || seededUnit(lineStart, salt: Salt.side) < Casting.sideFlipChance {
                outgoing.toggle()
                run = 0
            }
            run += 1
            let opensSection = gapBefore.map { $0 >= Casting.sectionGap } ?? true
            for (index, chunk) in MoneyScript.chunks(of: line).enumerated() {
                add(chunk, opensSection: opensSection && index == 0)
            }
        }

        private mutating func add(_ chunk: [TimedWord], opensSection: Bool) {
            let start = chunk[0].start, end = chunk[chunk.count - 1].end
            let kind = MoneyScript.kind(of: chunk, opensSection: opensSection,
                                        cardAllowed: start - lastCardStart >= Casting.cardSpacing, previous: previousKind)
            let gap = previousEnd.map { start - $0 } ?? 0
            let lead = gap < Casting.leadMinGap ? 0 : min(gap - Casting.leadTrim, Casting.maxLead)
            func item(_ kind: MoneyKind) -> MoneyItem {
                let text = MoneyTypesetter.text(for: chunk, kind: kind)
                return MoneyItem(kind: kind, outgoing: outgoing, start: start, end: end, lead: lead, text: text,
                                 size: MoneyTypesetter.box(for: kind, text: text.size),
                                 tint: MoneyScript.tint(for: kind, seed: start), icon: MoneyScript.icon(for: kind, seed: start))
            }
            items.append(item(kind))
            twins.append(kind == .map ? item(.island) : nil)
            if kind == .card { lastCardStart = start }
            previousKind = kind
            previousEnd = end
        }
    }
}

/// Something made once per song and then asked for on every frame, such as a plan; the few most recently
/// used are kept. Songs are told apart by their lyrics themselves, not by a digest of them: comparing is
/// free while a view keeps handing over the same lyrics, and no two songs can be taken for one another.
@MainActor
final class SongCache<Value> {
    private let limit: Int
    /// Most recently used first.
    private var recent: [(lyrics: TimedLyrics, value: Value)] = []

    init(limit: Int) {
        self.limit = limit
    }

    func value(for lyrics: TimedLyrics, make: () -> Value) -> Value {
        if let hit = recent.first, hit.lyrics == lyrics { return hit.value }
        let value = recent.first { $0.lyrics == lyrics }?.value ?? make()
        recent = Array(([(lyrics: lyrics, value: value)] + recent.filter { $0.lyrics != lyrics }).prefix(limit))
        return value
    }
}

/// A song's plan, with what has to be remembered about the song from one frame to the next.
@MainActor
final class MoneySong {
    let plan: MoneyPlan
    /// Which of the map rows on screen came up with their picture.
    var pictured = MoneyPictureLatch()

    init(plan: MoneyPlan) {
        self.plan = plan
    }
}

extension MoneyPlan {
    private static let maxCached = 3
    @MainActor private static let songs = SongCache<MoneySong>(limit: maxCached)

    /// The plan for these lyrics, built once per song: the style asks for it on every frame.
    @MainActor
    static func cached(for lyrics: TimedLyrics) -> MoneySong {
        songs.value(for: lyrics) { MoneySong(plan: MoneyPlan(lyrics: lyrics)) }
    }
}

// MARK: - Self-check

/// Returns the failed checks; SelfCheck.swift reports them.
func moneyStyleSelfCheck() -> [String] {
    func line(_ texts: [String], from start: Double, number: Int, spacing: Double = 0.4) -> [TimedWord] {
        texts.enumerated().map { TimedWord(text: $1, start: start + Double($0) * spacing, end: start + Double($0) * spacing + 0.35, line: number) }
    }
    let eight = line(["Paint", "the", "quiet", "harbour,", "every", "lamp", "still", "burning"], from: 1, number: 0)
    let four = line(["one", "two", "three", "four"], from: 20, number: 1)
    let cash = line(["cash", "rules"], from: 60, number: 2)
    let plan = MoneyPlan(lyrics: TimedLyrics(tier: .wordLevel, words: eight + four + cash))
    let kinds = plan.items.map(\.kind)
    func kind(opensSection: Bool, cardAllowed: Bool, after previous: MoneyKind?) -> MoneyKind {
        MoneyScript.kind(of: cash, opensSection: opensSection, cardAllowed: cardAllowed, previous: previous)
    }
    let wide = MoneyTypesetter.text(for: line(["extraordinarily", "magnificent", "constellations"], from: 0, number: 0), kind: .cash)
    let spring = MoneyMath.spring(10, response: 0.5, damping: 0.5)
    let checks: [(Bool, String)] = [
        (MoneyScript.chunks(of: eight).map(\.count) == [3, 3, 2], "money: eight evenly sung words make chunks of 3, 3 and 2"),
        (MoneyScript.chunks(of: four).map(\.count) == [2, 2], "money: a lone last word takes one from the full chunk before it"),
        (MoneyScript.chunks(of: line(["你", "好", "世", "界", "啊"], from: 0, number: 0)).count == 1, "money: five short CJK words stay together"),
        (kinds.first == .card && kinds.last == .card && kind(opensSection: true, cardAllowed: false, after: .card) == .pay,
         "money: a section opens with a card unless one came in the last 25 s"),
        (kind(opensSection: false, cardAllowed: true, after: .cash) == .pay && kind(opensSection: false, cardAllowed: true, after: .pay) == .island,
         "money: a money word pays, but not twice in a row"),
        (zip(kinds, kinds.dropFirst()).allSatisfy { $0 != $1 || $0 == .island }, "money: no kind twice in a row except the island"),
        (plan.items.map(\.start) == plan.items.map(\.start).sorted() && plan.newestIndex(at: 0.5) == nil
            && plan.newestIndex(at: 1) == 0 && plan.newestIndex(at: 99) == plan.items.count - 1, "money: items in time order, found by position"),
        (plan.items[3].lead == MoneyMath.clamp(20 - eight[7].end - 0.25, 0, 2.4) && plan.items[0].lead == 0, "money: a pause earns a lead pill"),
        (wide.type.size < 44 && wide.words.count == 3, "money: long words shrink the cash face"),
        (zip(plan.items, plan.islandTwins).allSatisfy { ($0.kind == .map) == ($1 != nil) }, "money: every map item has an island twin"),
        (abs(spring - 1) < 0.0001 && MoneyMath.spring(0, response: 0.5, damping: 0.5) == 0, "money: the spring starts at 0 and settles at 1"),
    ]
    return (checks + moneySharingChecks() + moneyMapRowChecks()).filter { !$0.0 }.map(\.1)
}

private func moneyCheckWords(_ texts: [String], from start: Double, line: Int) -> [TimedWord] {
    texts.enumerated().map { TimedWord(text: $1, start: start + Double($0) * 0.4, end: start + Double($0) * 0.4 + 0.35, line: line) }
}

/// Checks of what outlives a frame: the per-song cache and the verdict on each map row.
private func moneySharingChecks() -> [(Bool, String)] {
    // The same word count, first word and end points: only the words in between tell these two songs apart.
    let twins = [["we", "walk", "the", "line"], ["we", "ride", "the", "tide"]].map {
        TimedLyrics(tier: .wordLevel, words: moneyCheckWords($0, from: 1, line: 0))
    }
    let keepsApart = MainActor.assumeIsolated {
        twins.allSatisfy { lyrics in MoneyPlan.cached(for: lyrics).plan.items.flatMap { $0.text.words.map(\.text) } == lyrics.words.map(\.text) }
            && MoneyPlan.cached(for: twins[0]) === MoneyPlan.cached(for: twins[0])
    }
    var latch = MoneyPictureLatch()
    let row = MoneyPictureLatch.Row(start: 5, canvas: CGSize(width: 1440, height: 900))
    // The row comes up before its picture; the picture then arrives while the song is paused on it.
    let staysIsland = !latch.holds(row, isOnScreen: true, isReady: false) && !latch.holds(row, isOnScreen: true, isReady: true)
    let otherView = latch.holds(MoneyPictureLatch.Row(start: 5, canvas: CGSize(width: 640, height: 400)), isOnScreen: true, isReady: true)
    // A seek back to before the row opens the question again; the picture is later dropped and fetched anew.
    let comesUpAgain = latch.holds(row, isOnScreen: false, isReady: true) && latch.holds(row, isOnScreen: true, isReady: true)
    let staysPicture = latch.holds(row, isOnScreen: true, isReady: false)
    let instant = MoneyTypesetter.text(for: ["a", "b", "c"].map { TimedWord(text: $0, start: 1, end: 1, line: 0) }, kind: .message)
    return [
        (keepsApart, "money: songs that differ only in their middle words get their own plans, each made once"),
        (staysIsland && otherView && comesUpAgain && staysPicture,
         "money: a map row keeps the kind it came up as, in each view, whenever its picture comes or goes"),
        (!instant.words.contains(where: \.isLong), "money: words without any duration are not held"),
    ]
}

/// Checks that the feed asks about a map item the right way, and that a picture row keeps its shape.
private func moneyMapRowChecks() -> [(Bool, String)] {
    // A two-word line some seconds after a card, tried at one start time after another until it is cast as a map item.
    let lines = stride(from: 6.0, to: 12.0, by: 0.25).map { moneyCheckWords(["la", "la"], from: $0, line: 1) }
    guard let mapLine = lines.first(where: { MoneyScript.kind(of: $0, opensSection: false, cardAllowed: false, previous: .card) == .map }),
          let geometry = MoneyGeometry(canvas: CGSize(width: 1440, height: 900), band: 504, textScale: 1) else {
        return [(false, "money: the self-check has a map item to try")]
    }
    let plan = MoneyPlan(lyrics: TimedLyrics(tier: .wordLevel, words: moneyCheckWords(["one", "two"], from: 1, line: 0) + mapLine))
    let start = mapLine[0].start
    func feed(at position: Double, as row: MoneyMapRow) -> (hasComeUp: Bool?, newest: MoneySlot?) {
        var hasComeUp: Bool?
        let feed = MoneyFeed(plan: plan, geometry: geometry, position: position, energy: 0) { _, answer in
            hasComeUp = answer
            return row
        }
        return (hasComeUp, feed.slots.last)
    }
    let pictured = feed(at: start + 0.5, as: .pictured(nil)).newest, island = feed(at: start + 0.5, as: .island).newest
    return [
        (plan.items.last?.kind == .map && feed(at: start - 3, as: .island).hasComeUp == false
            && feed(at: start - 1, as: .island).hasComeUp == true && feed(at: start + 0.5, as: .island).hasComeUp == true,
         "money: a map item counts as on screen from its pill onwards"),
        (pictured?.item.kind == .map && (pictured?.pictureHeight ?? 0) > 0 && island?.item.kind == .island && island?.pictureHeight == 0,
         "money: a picture row keeps its shape while its picture is away; without one the island twin is drawn"),
    ]
}
