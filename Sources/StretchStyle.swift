import SwiftUI

/// Stretch: the line is set centred in up to three rows. Quick words snap in with a crisp scale settle; a held
/// word widens as it is sung and repeats its vowel ("harbour" becomes "harboooour"), then springs back once it
/// ends. Everything is a closed-form function of the song position, so no SwiftUI state is needed.
struct StretchStyle: View {
    let context: StyleContext

    var body: some View {
        let scene = StretchScene(context: context)
        Canvas { graphics, _ in scene.draw(in: &graphics) }
            .frame(width: context.canvas.width, height: context.band)
            .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
    }
}

private enum Metrics {
    // Type (fractions of the screen) and rows
    static let fontSize = 0.076, rowWidth = 0.5, widestRow = 0.92, lineHeight = 1.16, maxRows = 3
    static let maxBlock = 0.9, measuringSize = 100.0, shrinkStep = 0.9, shrinkTries = 14, balanceStep = 1.03

    // Holding
    static let holdThreshold = 0.6                  // seconds a word must be held to stretch…
    static let relativeHold = 1.4, shortestHold = 0.38  // …or this many times the line's average, if at least this long
    static let secondsPerExtra = 0.2, extraRange = 2...6
    static let widen = 0.12, squash = 0.05          // horizontal growth and vertical give at full stretch
    static let relaxTime = 0.34, recoil = 0.05, recoilRate = 26.0, recoilDecay = 0.09
    static let slideLead = 0.2, slideSpan = 0.6     // each extra letter slides out over the middle of its turn
    static let interpolatedHold = 0.45              // seconds the last word of an estimated line is held past its end

    // Arriving
    static let popScale = 0.32, popDecay = 0.075, popRate = 19.0, fadeIn = 0.05, rise = 0.12

    // Leaving
    static let fadeOut = 0.3

    static let shadowOpacity = 0.55, shadowRadius = 12.0, shadowY = 3.0
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
private func smooth(_ value: Double) -> Double { let x = unit(value); return x * x * (3 - 2 * x) }

/// The letter a singer would hold: the first vowel of the word's last vowel group, skipping a silent final "e"
/// ("love" holds its "o"). A word without a vowel holds its last letter; one without a letter is not repeated.
private func heldLetter(in characters: [Character]) -> Int? {
    let letters = characters.indices.filter { characters[$0].isLetter }
    guard let last = letters.last else { return nil }
    let vowels: Set<String> = ["a", "e", "i", "o", "u", "à", "á", "â", "ä", "å", "æ", "è", "é", "ê", "ë", "ì", "í", "î", "ï",
                               "ò", "ó", "ô", "ö", "ø", "ù", "ú", "û", "ü"]
    func isVowel(_ index: Int) -> Bool {
        let letter = characters[index].lowercased()
        return vowels.contains(letter) || (letter == "y" && index != letters.first)
    }
    var candidates = letters.filter(isVowel)
    if candidates.count > 1, let lastVowel = candidates.last, lastVowel == last,
       characters[last].lowercased() == "e", !isVowel(last - 1) {
        candidates.removeLast()
    }
    guard var held = candidates.last else { return characters[last].isASCII || characters[last].isCased ? last : nil }
    while held > 0, characters[held - 1].isLetter, isVowel(held - 1) { held -= 1 }
    return held
}

/// One word cut around the letter it repeats, measured at the drawing size.
private struct Piece {
    let word: TimedWord
    let before: String, letter: String, after: String
    let beforeWidth: Double, letterWidth: Double, width: Double
    /// When the word is held, and how many extra letters it grows by the end; nil for a quick word.
    let hold: (start: Double, end: Double, extras: Int)?

    /// How much wider the word gets at full stretch; each row keeps room for its widest stretch.
    var reserve: Double { hold.map { (width + letterWidth * Double($0.extras)) * (1 + Metrics.widen) - width } ?? 0 }
}

private struct StretchScene {
    let context: StyleContext
    let fontSize: Double
    let pieces: [Piece]
    let rows: [Range<Int>]
    let space: Double

    init(context: StyleContext) {
        self.context = context
        let words = context.line.words
        let reference = context.settings.font.font(size: Metrics.measuringSize)
        let holds = words.indices.map { Self.hold(of: $0, in: context) }
        let measured = words.indices.map { Self.piece(words[$0], hold: holds[$0], font: reference) }
        let referenceSpace = (" " as NSString).size(withAttributes: [.font: reference]).width

        // Rows are broken once for the whole line from time-independent widths, so they never reflow while it is sung.
        let canvas = context.canvas
        let limit = min(canvas.width * Metrics.rowWidth * context.scale, canvas.width * Metrics.widestRow)
        let tallest = context.band * Metrics.maxBlock
        var size = canvas.height * Metrics.fontSize * context.scale
        var rows = [0..<words.count]
        for _ in 0..<Metrics.shrinkTries {
            let ratio = size / Metrics.measuringSize
            if let fitted = balancedRows(measured.map { ($0.width * ratio, $0.reserve * ratio) }, space: referenceSpace * ratio, limit: limit),
               Double(fitted.count) * size * Metrics.lineHeight <= tallest {
                rows = fitted
                break
            }
            size *= Metrics.shrinkStep
        }
        fontSize = size
        let font = context.settings.font.font(size: size)
        pieces = words.indices.map { Self.piece(words[$0], hold: holds[$0], font: font) }
        space = (" " as NSString).size(withAttributes: [.font: font]).width
        self.rows = rows
    }

    /// Word-level lyrics stretch every word held long enough. Estimated (interpolated) timings only reflect spelling,
    /// so there only the line's last word is held, as singers usually do, a little past its estimated end.
    private static func hold(of index: Int, in context: StyleContext) -> (start: Double, end: Double, extras: Int)? {
        let word = context.line.words[index]
        let start = word.start, end: Double
        switch context.lyrics.tier {
        case .wordLevel:
            let words = context.line.words, held = word.end - word.start
            let mean = words.reduce(0) { $0 + $1.end - $1.start } / Double(words.count)
            guard held >= Metrics.holdThreshold || (held >= Metrics.shortestHold && held >= Metrics.relativeHold * mean) else { return nil }
            end = word.end
        case .interpolated:
            guard index == context.line.words.count - 1 else { return nil }
            end = word.end + Metrics.interpolatedHold
        }
        let extras = min(max(Int(((end - start) / Metrics.secondsPerExtra).rounded()), Metrics.extraRange.lowerBound),
                         Metrics.extraRange.upperBound)
        return (start, end, extras)
    }

    private static func piece(_ word: TimedWord, hold: (start: Double, end: Double, extras: Int)?, font: NSFont) -> Piece {
        func width(_ text: String) -> Double { (text as NSString).size(withAttributes: [.font: font]).width }
        let characters = Array(word.text)
        let whole = width(word.text)
        guard hold != nil, let held = heldLetter(in: characters) else {
            return Piece(word: word, before: word.text, letter: "", after: "", beforeWidth: whole, letterWidth: 0, width: whole,
                         hold: hold.map { ($0.start, $0.end, 0) })
        }
        let before = String(characters[..<held]), letter = String(characters[held]), after = String(characters[(held + 1)...])
        let beforeWidth = width(before), letterWidth = width(letter)
        return Piece(word: word, before: before, letter: letter, after: after, beforeWidth: beforeWidth, letterWidth: letterWidth,
                     width: beforeWidth + letterWidth + width(after), hold: hold)
    }

    // MARK: Motion

    /// How far a word is stretched: grows over the hold, then relaxes with a small recoil past rest.
    private func stretch(_ piece: Piece, at time: Double) -> Double {
        guard let hold = piece.hold, time >= hold.start else { return 0 }
        let grown = smooth((time - hold.start) / max(0.01, hold.end - hold.start))
        let since = time - hold.end
        guard since > 0 else { return grown }
        let eased = 1 - smooth(since / Metrics.relaxTime)
        guard !context.settings.reduceMotion else { return eased }
        return eased - Metrics.recoil * exp(-since / Metrics.recoilDecay) * sin(Metrics.recoilRate * since)
    }

    /// The scale a word lands with: a quick overshoot that settles crisply.
    private func pop(_ age: Double) -> Double {
        context.settings.reduceMotion ? 1 : 1 + Metrics.popScale * exp(-age / Metrics.popDecay) * cos(Metrics.popRate * age)
    }

    private func extrasShown(_ piece: Piece, stretch: Double) -> Double {
        Double(piece.hold?.extras ?? 0) * max(0, stretch)
    }

    /// How far one extra letter has slid out, given how much of its turn has passed.
    private func slide(_ share: Double) -> Double { smooth((share - Metrics.slideLead) / Metrics.slideSpan) }

    /// The extra letters' total advance, in letter widths.
    private func opened(_ shown: Double) -> Double {
        (0..<Int(shown.rounded(.up))).reduce(0) { $0 + slide(shown - Double($1)) }
    }

    private func width(_ piece: Piece, stretch: Double) -> Double {
        (piece.width + piece.letterWidth * opened(extrasShown(piece, stretch: stretch))) * (1 + Metrics.widen * stretch)
    }

    // MARK: Drawing

    func draw(in graphics: inout GraphicsContext) {
        let time = context.position
        let words = context.line.words
        guard let last = words.last else { return }
        let lineHeight = fontSize * Metrics.lineHeight
        let top = context.band / 2 - lineHeight * Double(rows.count) / 2
        let leaving = (last.end + Timing.lineLinger - time) / Metrics.fadeOut
        graphics.opacity = smooth(leaving)
        let font = context.font(fontSize)
        let stretches = pieces.map { stretch($0, at: time) }
        for (rowIndex, row) in rows.enumerated() {
            let widths = row.map { width(pieces[$0], stretch: stretches[$0]) }
            let rowWidth = widths.reduce(0, +) + space * Double(row.count - 1)
            var x = context.canvas.width / 2 - rowWidth / 2
            let y = top + lineHeight * (Double(rowIndex) + 0.5)
            for (offset, index) in row.enumerated() {
                let age = time - words[index].start
                if age >= 0 {
                    drawWord(pieces[index], stretch: stretches[index], age: age,
                             centre: CGPoint(x: x + widths[offset] / 2, y: y), font: font, in: graphics)
                }
                x += widths[offset] + space
            }
        }
    }

    private func drawWord(_ piece: Piece, stretch: Double, age: Double, centre: CGPoint, font: Font, in graphics: GraphicsContext) {
        let settings = context.settings
        let text = Color(nsColor: settings.textColor), highlight = Color(nsColor: settings.highlightColor)
        let pop = pop(age), lift = settings.reduceMotion ? 0 : fontSize * Metrics.rise * exp(-age / Metrics.popDecay)
        var word = graphics
        word.opacity *= unit(age / Metrics.fadeIn)
        word.translateBy(x: centre.x, y: centre.y + lift)
        word.scaleBy(x: pop * (1 + Metrics.widen * stretch), y: pop * (1 - Metrics.squash * max(0, stretch)))

        let shown = extrasShown(piece, stretch: stretch)
        var x = -(piece.width + piece.letterWidth * opened(shown)) / 2
        func place(_ string: String, _ color: Color, advance: Double, in target: GraphicsContext) {
            guard !string.isEmpty else { return }
            target.draw(target.resolve(Text(string).font(font).foregroundStyle(color)), at: CGPoint(x: x, y: 0), anchor: .leading)
            x += advance
        }
        guard piece.hold != nil, !piece.letter.isEmpty else {
            place(piece.before, text, advance: piece.width, in: word)
            return
        }
        // The held letter and its copies glow in the highlight colour while held, and cool back as the word relaxes.
        let glow = text.mix(with: highlight, by: unit(stretch * 1.5))
        place(piece.before, text, advance: piece.beforeWidth, in: word)
        place(piece.letter, glow, advance: piece.letterWidth, in: word)
        let whole = Int(shown.rounded(.up))
        // Each copy slides out from under the one before it in a quick, eased step, so the word clicks open a letter at
        // a time without ever popping, and rarely rests half-overlapped.
        let copy = word.resolve(Text(piece.letter).font(font).foregroundStyle(glow))
        x -= piece.letterWidth
        for index in 0..<whole {
            x += piece.letterWidth * slide(shown - Double(index))
            word.draw(copy, at: CGPoint(x: x, y: 0), anchor: .leading)
        }
        x += piece.letterWidth
        place(piece.after, text, advance: 0, in: word)
    }
}

/// Breaks words into rows no wider than `limit`, using as few rows as possible (at most `Metrics.maxRows`) and then
/// evening them out, so a line does not end in a lone short word. Each word is its resting width plus the extra room
/// it needs when stretched; a row keeps room for one stretched word at a time. Nil when the words cannot fit.
private func balancedRows(_ words: [(width: Double, reserve: Double)], space: Double, limit: Double) -> [Range<Int>]? {
    guard let widest = words.map({ $0.width + $0.reserve }).max(), widest <= limit else { return words.isEmpty ? [] : nil }
    let greedy = rows(words, space: space, limit: limit)
    guard greedy.count <= Metrics.maxRows else { return nil }
    let total = words.reduce(0) { $0 + $1.width } + space * Double(words.count - 1)
    var target = max(widest, total / Double(greedy.count))
    while target < limit {
        let even = rows(words, space: space, limit: target)
        if even.count <= greedy.count { return even }
        target *= Metrics.balanceStep
    }
    return greedy
}

private func rows(_ words: [(width: Double, reserve: Double)], space: Double, limit: Double) -> [Range<Int>] {
    var result: [Range<Int>] = [], start = 0, used = 0.0, reserve = 0.0
    for (index, word) in words.enumerated() {
        if index > start, used + space + word.width + max(reserve, word.reserve) > limit {
            result.append(start..<index)
            (start, used, reserve) = (index, word.width, word.reserve)
        } else {
            used += (index > start ? space : 0) + word.width
            reserve = max(reserve, word.reserve)
        }
    }
    if start < words.count { result.append(start..<words.count) }
    return result
}
