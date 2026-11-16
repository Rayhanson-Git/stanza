import SwiftUI

/// Codestyle: the current lyric line typed out as make-believe source code, at most three words per row,
/// with a block caret, two blurred earlier rows above it and (in the Visual variant) one word icon beside it.
/// Every frame is computed from the playback position and the wall clock; there is no view state.
struct CodeStyle: View {
    let context: StyleContext
    let icons: Bool

    var body: some View {
        let rows = CodeScript.rows(for: context.line.words)
        if !rows.isEmpty {
            block(rows)
        }
    }

    private func block(_ rows: [CodeRow]) -> some View {
        let currentIndex = rows.lastIndex { $0.start <= context.position } ?? 0
        let current = rows[currentIndex]
        let fontSize = fittedSize(for: current)
        let history = Array((previousLineRows(wanted: currentIndex < Metrics.historyRows) + rows[..<currentIndex])
            .suffix(Metrics.historyRows))
        let pose = pose(rowStart: current.start)
        return VStack(alignment: .center, spacing: fontSize * Metrics.rowSpacing) {
            ForEach(Array(history.enumerated()), id: \.offset) { index, row in
                historyRow(row, depth: history.count - 1 - index)
            }
            currentRow(current, fontSize: fontSize)
            if let caption = current.caption {
                captionView(caption, fontSize: fontSize, lineEnd: current.words[current.words.count - 1].end)
            }
        }
        .frame(width: context.canvas.width, height: context.band)
        .scaleEffect(pose.scale)
        .rotationEffect(.degrees(pose.degrees))
        .offset(pose.offset)
        // Stands in for a directional motion blur, which needs a Metal shader this project cannot compile.
        .blur(radius: pose.blur)
        .id(context.line.index)
    }

    // MARK: Rows

    private func currentRow(_ row: CodeRow, fontSize: CGFloat) -> some View {
        let iconLeads = seededUnit(row.start, salt: Salt.iconSide) < 0.5
        let renderer = TypingRenderer(row: row, position: context.position, fontSize: fontSize, caretOpacity: caretOpacity(for: row))
        return row.styledText
            .font(Metrics.font(fontSize))
            .lineLimit(1)
            .fixedSize()
            .textRenderer(renderer)
            // An overlay, not an HStack: the row must not jump sideways when an icon turns up mid-typing.
            // The zero-size anchor on the row's edge lets the icon hang outside it whatever its own width.
            .overlay(alignment: iconLeads ? .leading : .trailing) {
                Color.clear.frame(width: 0, height: 0)
                    .overlay(alignment: iconLeads ? .trailing : .leading) { icon(for: row, fontSize: fontSize) }
            }
            .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
    }

    private func historyRow(_ row: CodeRow, depth: Int) -> some View {
        row.styledText
            .font(Metrics.font(fittedSize(for: row) * Metrics.historyScale))
            .lineLimit(1)
            .fixedSize()
            .blur(radius: Metrics.historyBlur[depth])
            .opacity(Metrics.historyOpacity[depth])
    }

    /// Present (but invisible) from the moment its row shows, so the block does not hop when it fades in.
    private func captionView(_ caption: String, fontSize: CGFloat, lineEnd: Double) -> some View {
        let fade = min(max((context.position - lineEnd) / Metrics.captionFade, 0), 1)
        return Text(caption)
            .font(Metrics.font(fontSize * Metrics.captionScale))
            .foregroundStyle(Palette.comment)
            .opacity(fade * Metrics.captionOpacity)
    }

    /// The icon of the most recently started word of the row that has one, hung just outside the row's edge.
    @ViewBuilder
    private func icon(for row: CodeRow, fontSize: CGFloat) -> some View {
        let sung = row.words.reversed().lazy.filter { $0.start <= context.position }
        if icons, let match = sung.compactMap({ word in WordVisuals.shared.visual(for: word.text).map { (word: word, visual: $0) } }).first {
            let gap = fontSize * Metrics.iconSpacing
            WordIcon(visual: match.visual, size: fontSize * Metrics.iconScale, color: Palette.accent,
                     age: context.position - match.word.start)
                .fixedSize()
                .id(match.word.start)
                .padding(.trailing, gap)
                // The caret is parked past the trailing edge once the row is typed; the icon sits beyond it.
                .padding(.leading, gap + fontSize * (Typing.caretGap + Typing.caretWidth))
        }
    }

    private func previousLineRows(wanted: Bool) -> [CodeRow] {
        let index = context.line.index - 1
        guard wanted, context.lyrics.lines.indices.contains(index) else { return [] }
        return CodeScript.rows(for: context.lyrics.lines[index])
    }

    // MARK: Sizing and motion

    private func fittedSize(for row: CodeRow) -> CGFloat {
        let base = context.band * Metrics.baseSize * context.settings.textScale
        let width = (row.plainText as NSString).size(withAttributes: [.font: Metrics.measuringFont]).width
        return width > 0 ? min(base, context.canvas.width * Metrics.maxRowWidth * Metrics.measuringSize / width) : base
    }

    private func caretOpacity(for row: CodeRow) -> Double {
        let isTyping = row.words.contains { $0.start <= context.position && context.position < $0.start + Typing.span(of: $0) }
        let blinkIsOn = sin(2 * .pi * Typing.blinkHertz * context.clock) > 0
        return isTyping || blinkIsOn ? 1 : Typing.caretDimOpacity
    }

    private struct Pose {
        let scale: CGFloat
        let degrees: Double
        let offset: CGSize
        let blur: CGFloat
    }

    /// Where the whole block sits this frame: the line's fly-in, the row's settled jitter and punch, and a slow drift.
    private func pose(rowStart: Double) -> Pose {
        let band = Double(context.band), clock = context.clock
        let lineStart = context.line.words[0].start
        let arrived = min(max((context.position - lineStart) / Motion.flyInDuration, 0), 1)
        let remaining = pow(1 - arrived, Motion.flyInEase)
        let side: Double = seededUnit(lineStart, salt: Salt.flyInSide) < 0.5 ? -1 : 1
        let age = context.position - rowStart
        let travel = band * Motion.flyInDistance * remaining
        func jitter(_ salt: UInt64) -> Double { 2 * seededUnit(rowStart, salt: salt) - 1 }
        return Pose(
            scale: 1 + Motion.punch * (age >= 0 ? exp(-age / Motion.punchDecay) : 1),
            degrees: side * Motion.flyInTilt * remaining + jitter(Salt.tilt) * Motion.tiltJitter
                + Motion.rockDegrees * sin(Motion.rockSpeed * clock),
            offset: CGSize(
                width: band * Motion.nudge * jitter(Salt.nudgeX) + travel * Motion.flyInSideways * side
                    + band * Motion.drift * sin(Motion.driftSpeed * clock),
                height: band * Motion.nudge * jitter(Salt.nudgeY) + travel
                    + band * Motion.drift * sin(Motion.driftSpeed * Motion.driftRatio * clock + Motion.driftPhase)),
            blur: band * Motion.flyInBlur * remaining)
    }
}

// MARK: - Constants

private enum Metrics {
    static let baseSize = 0.115                     // of the band, before textScale
    static let measuringSize: CGFloat = 100
    static let measuringFont = NSFont.monospacedSystemFont(ofSize: measuringSize, weight: .bold)
    static let maxRowWidth = 0.8                    // of the screen width
    static let rowSpacing = 0.48                    // of the font size, like everything below
    static let historyScale = 0.8
    // Newest earlier row first.
    static let historyBlur: [CGFloat] = [2.0, 4.6], historyOpacity = [0.6, 0.34]
    static let historyRows = historyBlur.count
    static let shadowOpacity = 0.5, shadowRadius: CGFloat = 14, shadowY: CGFloat = 3
    static let captionScale = 0.36, captionFade = 0.3, captionOpacity = 0.8
    static let iconScale = 0.9, iconSpacing = 0.3

    static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
}

private enum Motion {
    static let flyInDuration = 0.24, flyInEase = 3.0
    static let flyInDistance = 0.46                 // of the band, upwards
    static let flyInSideways = 0.35                 // of the vertical travel
    static let flyInTilt = 4.0
    static let flyInBlur = 0.028                    // of the band: a quarter of the 0.11 streak a motion blur would smear
    static let punch = 0.1, punchDecay = 0.32
    static let nudge = 0.045, tiltJitter = 2.6
    static let drift = 0.032, driftSpeed = 0.31, driftRatio = 0.73, driftPhase = 1.7
    static let rockDegrees = 2.8, rockSpeed = 0.23
}

private enum Typing {
    static let minSpan = 0.01, maxSpan = 0.45
    static let popAmount = 0.42, popDecay = 0.1, popFrequency = 20.0
    static let glowRadius = 0.32, glowBoost = 1.4, glowDecay = 0.14, glowOpacity = 0.35
    static let caretWidth = 0.58, caretHeight = 1.08, caretGap = 0.1, caretCorner = 0.12
    static let blinkHertz = 1.1, caretDimOpacity = 0.12
    // Room around the text for the glow, the pop overshoot and the caret parked after the last glyph.
    static let padding = 1.06, trailingPadding = 1.94

    static func span(of word: TimedWord) -> Double { min(max(word.end - word.start, minSpan), maxSpan) }

    /// Glyph `glyph` of the `count` a word types appears this many seconds into the song.
    static func revealTime(of word: TimedWord, glyph: Int, of count: Int) -> Double {
        word.start + span(of: word) * Double(glyph + 1) / Double(count)
    }
}

private enum Script {
    static let maxWordsPerRow = 3
    static let apostrophes: Set<Character> = ["'", "’"]
    // One draw per row picks its shape; these are the upper ends of each shape's slice of 0..<1.
    static let commentBelow = 0.12, callBelow = 0.5, bindingBelow = 0.68
    static let terminatorChance = 0.65, captionChance = 0.22
    static let selfWords: Set<String> = ["i", "im", "i'm", "ive", "i've", "id", "i'd", "ill", "i'll", "if"]
    static let otherWords: Set<String> = ["you", "your", "youre", "you're", "youve", "you've", "youll", "you'll", "u", "ur",
                                          "she", "shes", "she's", "he", "hes", "he's"]
}

private enum Salt {
    static let shape: UInt64 = 0xC0DE, terminator: UInt64 = 0x5E31, caption: UInt64 = 0xCA97
    static let flyInSide: UInt64 = 0xF1E5, nudgeX: UInt64 = 0x0D6E, nudgeY: UInt64 = 0x0D6F, tilt: UInt64 = 0x7E17
    static let iconSide: UInt64 = 0x1C09
}

private enum Palette {
    static let identifier = Color(.sRGB, red: 0.55, green: 0.65, blue: 1)
    static let keyword = Color(.sRGB, red: 1, green: 0.23, blue: 0.19)
    static let accent = Color(.sRGB, red: 1, green: 0.65, blue: 0.32)
    static let punctuation = identifier.opacity(0.75)
    static let comment = Color(.sRGB, red: 0.62, green: 0.65, blue: 0.7, opacity: 0.85)
    static let caret = Color(.sRGB, red: 1, green: 0.16, blue: 0.13)
}

// MARK: - Lyric line → rows of code

private enum CodeRole {
    case identifier, keyword, accent, argument, punctuation, comment

    var color: Color {
        switch self {
        case .identifier: return Palette.identifier
        case .keyword: return Palette.keyword
        case .accent: return Palette.accent
        case .argument: return .white
        case .punctuation: return Palette.punctuation
        case .comment: return Palette.comment
        }
    }
}

/// A coloured piece of a row. `word` is the row word whose timing types it in, so punctuation arrives with its word.
private struct CodeSegment {
    let text: String
    let role: CodeRole
    let word: Int
}

private struct CodeTag: TextAttribute {
    let word: Int
    let glow: Color
}

private struct CodeRow {
    /// Lower-cased and stripped of punctuation.
    let words: [TimedWord]
    let segments: [CodeSegment]
    let caption: String?

    var start: Double { words[0].start }
    var plainText: String { segments.map(\.text).joined() }

    var styledText: Text {
        segments.reduce(Text(verbatim: "")) { text, segment in
            let piece = Text(verbatim: segment.text).foregroundStyle(segment.role.color)
                .customAttribute(CodeTag(word: segment.word, glow: segment.role.color))
            return Text("\(text)\(piece)")
        }
    }
}

private enum CodeScript {
    private enum Shape { case comment, chain, call, binding }

    /// Splits a line into balanced rows of at most three words (4 → 2+2, 7 → 3+2+2) and dresses each as code.
    static func rows(for line: [TimedWord]) -> [CodeRow] {
        let words = line.compactMap(cleaned)
        guard let first = words.first, let last = words.last else { return [] }
        let rowCount = (words.count + Script.maxWordsPerRow - 1) / Script.maxWordsPerRow
        let size = words.count / rowCount, longer = words.count % rowCount
        return (0..<rowCount).map { row in
            let from = row * size + min(row, longer)
            let rowWords = Array(words[from..<from + size + (row < longer ? 1 : 0)])
            let isLast = row == rowCount - 1
            let hasCaption = isLast && seededUnit(first.start, salt: Salt.caption) < Script.captionChance
            return CodeRow(words: rowWords, segments: segments(for: rowWords, endsLine: isLast),
                           caption: hasCaption ? String(format: "// ran in %.2fs", last.end - first.start) : nil)
        }
    }

    private static func cleaned(_ word: TimedWord) -> TimedWord? {
        let text = word.text.lowercased().filter { $0.isLetter || $0.isNumber || Script.apostrophes.contains($0) }
        return text.isEmpty ? nil : TimedWord(text: text, start: word.start, end: word.end, line: word.line)
    }

    private static func shape(for seed: Double, wordCount: Int) -> Shape {
        let draw = seededUnit(seed, salt: Salt.shape)
        if draw < Script.commentBelow { return .comment }
        if draw < Script.callBelow { return .call }
        return draw < Script.bindingBelow && wordCount > 1 ? .binding : .chain
    }

    /// `// a b c`, `a.b.c`, `a.b(c)` / `a()`, or `let a = b.c`; the line's final row may end in `;`.
    private static func segments(for words: [TimedWord], endsLine: Bool) -> [CodeSegment] {
        let seed = words[0].start, lastIndex = words.count - 1
        let shape = shape(for: seed, wordCount: words.count)
        let isCall = shape == .call
        let body = words.enumerated().flatMap { index, word -> [CodeSegment] in
            let isArgument = isCall && index == lastIndex && index > 0
            let wordSegment = CodeSegment(text: word.text, role: role(of: word.text, in: shape, isArgument: isArgument), word: index)
            return [opening(shape, before: index, isArgument: isArgument), wordSegment].filter { !$0.text.isEmpty }
        }
        let hasTerminator = endsLine && shape != .comment && seededUnit(seed, salt: Salt.terminator) < Script.terminatorChance
        let closing = (isCall ? (lastIndex == 0 ? "()" : ")") : "") + (hasTerminator ? ";" : "")
        return body + (closing.isEmpty ? [] : [CodeSegment(text: closing, role: .punctuation, word: lastIndex)])
    }

    /// The decoration typed just before word `index`.
    private static func opening(_ shape: Shape, before index: Int, isArgument: Bool) -> CodeSegment {
        switch (shape, index) {
        case (.comment, _): return CodeSegment(text: index == 0 ? "// " : " ", role: .comment, word: index)
        case (.binding, 0): return CodeSegment(text: "let ", role: .keyword, word: index)
        case (.binding, 1): return CodeSegment(text: " = ", role: .punctuation, word: index)
        case (_, 0): return CodeSegment(text: "", role: .punctuation, word: index)
        default: return CodeSegment(text: isArgument ? "(" : ".", role: .punctuation, word: index)
        }
    }

    private static func role(of text: String, in shape: Shape, isArgument: Bool) -> CodeRole {
        if shape == .comment { return .comment }
        if isArgument { return .argument }
        if Script.selfWords.contains(text) { return .keyword }
        return Script.otherWords.contains(text) ? .accent : .identifier
    }
}

// MARK: - Typing

/// Draws the row one glyph at a time: each glyph lands with a damped bounce and a glow that settles into a
/// soft halo, and a block caret follows the last glyph typed.
private struct TypingRenderer: TextRenderer {
    let row: CodeRow
    let position: Double
    let fontSize: CGFloat
    let caretOpacity: Double

    private struct Glyph {
        let slice: Text.Layout.RunSlice
        let tag: CodeTag
    }

    var displayPadding: EdgeInsets {
        let padding = fontSize * Typing.padding
        return EdgeInsets(top: padding, leading: padding, bottom: padding, trailing: fontSize * Typing.trailingPadding)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard let line = layout.first else { return }
        let glyphs = line.flatMap { run in run[CodeTag.self].map { tag in run.map { Glyph(slice: $0, tag: tag) } } ?? [] }
        // Counted in glyphs, not characters: one word's text can be laid out as more or fewer glyphs.
        let typed = row.words.indices.flatMap { word -> [(glyph: Glyph, age: Double)] in
            let own = glyphs.filter { $0.tag.word == word }
            return own.enumerated().compactMap { index, glyph in
                let age = position - Typing.revealTime(of: row.words[word], glyph: index, of: own.count)
                return age >= 0 ? (glyph, age) : nil
            }
        }
        for item in typed { draw(item.glyph, age: item.age, in: context) }
        let lineBox = line.typographicBounds.rect
        let caretX = typed.map { $0.glyph.slice.typographicBounds.rect.maxX + fontSize * Typing.caretGap }.max() ?? lineBox.minX
        drawCaret(leftEdge: caretX, midY: lineBox.midY, in: context)
    }

    private func draw(_ glyph: Glyph, age: Double, in context: GraphicsContext) {
        let box = glyph.slice.typographicBounds.rect
        let pop = 1 + Typing.popAmount * exp(-age / Typing.popDecay) * cos(Typing.popFrequency * age)
        let glow = fontSize * Typing.glowRadius * (1 + Typing.glowBoost * exp(-age / Typing.glowDecay))
        var layer = context
        layer.translateBy(x: box.midX, y: box.midY)
        layer.scaleBy(x: pop, y: pop)
        layer.translateBy(x: -box.midX, y: -box.midY)
        layer.addFilter(.shadow(color: glyph.tag.glow.opacity(Typing.glowOpacity), radius: glow))
        layer.draw(glyph.slice, options: .disablesSubpixelQuantization)
    }

    private func drawCaret(leftEdge: CGFloat, midY: CGFloat, in context: GraphicsContext) {
        let size = CGSize(width: fontSize * Typing.caretWidth, height: fontSize * Typing.caretHeight)
        let box = CGRect(origin: CGPoint(x: leftEdge, y: midY - size.height / 2), size: size)
        let shape = Path(roundedRect: box, cornerRadius: size.width * Typing.caretCorner, style: .continuous)
        context.fill(shape, with: .color(Palette.caret.opacity(caretOpacity)))
    }
}
