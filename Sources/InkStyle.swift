import SwiftUI

/// Ink: each word writes itself in the user's font, a pen tracing its glyph outlines over the time the word is
/// sung, and then the ink soaks in: the letters fill, bleed softly at the edges and dry from the highlight colour
/// to the text colour. Earlier words stay written; the line fades as a whole before the next one.
/// Everything is a pure function of the song position.
struct InkStyle: View {
    let context: StyleContext

    var body: some View {
        // GeometryReader can hand out an empty size on its first pass; there is nothing to lay out then.
        if context.canvas.width > 0, context.band > 0 {
            let page = InkPage(words: context.line.words, context: context)
            let handOff = Self.handOff(context)
            Canvas { graphics, _ in
                if let handOff { handOff.page.draw(in: graphics, opacity: handOff.opacity) }
                page.draw(in: graphics, opacity: Self.lineOpacity(context))
            }
            .frame(width: context.canvas.width, height: context.band)
        }
    }

    /// A line stays whole until the next begins, and the hand-off fades it then. With nothing following soon, it fades
    /// as it lingers, but never before its last word is written.
    private static func lineOpacity(_ context: StyleContext) -> Double {
        guard let last = context.line.words.last else { return 1 }
        let gone = last.end + Timing.lineLinger
        let next = context.line.index + 1
        if context.lyrics.lines.indices.contains(next), let start = context.lyrics.lines[next].first?.start, start <= gone { return 1 }
        let fadeStart = max(gone - Metrics.fadeOut, last.start + Pen.writingTime(of: last))
        return fadeStart < gone ? unit((gone - context.position) / (gone - fadeStart)) : 1
    }

    /// The line before, still on screen when this one began, fading out over this line's first moments.
    private static func handOff(_ context: StyleContext) -> (page: InkPage, opacity: Double)? {
        let index = context.line.index
        guard index > 0, let start = context.line.words.first?.start, let last = context.lyrics.lines[index - 1].last,
              start <= last.end + Timing.lineLinger else { return nil }
        let opacity = 1 - unit((context.position - start) / Metrics.fadeOut)
        return opacity > 0 ? (InkPage(words: context.lyrics.lines[index - 1], context: context), opacity) : nil
    }
}

// MARK: - Constants

private enum Metrics {
    static let fontSize = 0.175                      // of the band, before Size
    static let maxWidth = 0.5                        // of the screen width at Size 100%
    static let fit = 0.94                            // of the band and of the screen width the block may use
    static let wordsPerRow = 3.4                     // a line of this many words or more wraps to two rows, and so on
    static let maxRows = 3
    static let wordGap = 0.28, lineHeight = 1.12     // of the font size
    static let referenceSize: CGFloat = 100          // outlines are built once at this size and scaled
    static let strokeWidth = 0.028, minStrokeWidth: CGFloat = 1.5
    static let nibRadius = 0.05
    static let bleedRadius = 0.06, bleedOpacity = 0.55, bleedRest = 0.4
    static let shadowOpacity = 0.55, shadowRadius = 0.09, shadowDrop = 0.02
    static let fadeOut = 0.35
}

private enum Pen {
    static let minWrite = 0.22, maxWrite = 1.8      // seconds a word takes to write: its sung time, within these
    static let ease = 1.35                           // the pen slows a little towards the end of a word
    static let soakFrom = 0.8                        // of the writing time: the fill starts to soak in here…
    static let soak = 0.5                            // …over this long
    static let dry = 1.2                             // and dries from the highlight to the text colour over this long

    static func writingTime(of word: TimedWord) -> Double { min(max(word.end - word.start, minWrite), maxWrite) }
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }

/// Splits `widths` into `rows` consecutive runs (fewer when there are fewer words) so the widest run is as narrow as
/// it can be. A small dynamic programme: lines are a handful of words.
private func balancedRows(_ widths: [CGFloat], rows wanted: Int) -> [Range<Int>] {
    let count = widths.count, rows = min(max(1, wanted), count)
    guard count > 0 else { return [] }
    let prefix = widths.reduce(into: [CGFloat(0)]) { $0.append($0[$0.count - 1] + $1) }
    // best[k][i]: the narrowest widest row when the first i words fill k rows; start[k][i]: where that last row begins.
    var best = Array(repeating: Array(repeating: CGFloat.infinity, count: count + 1), count: rows + 1)
    var start = Array(repeating: Array(repeating: 0, count: count + 1), count: rows + 1)
    best[0][0] = 0
    for row in 1...rows {
        for end in row...count {
            for begin in (row - 1)..<end {
                let widest = max(best[row - 1][begin], prefix[end] - prefix[begin])
                if widest < best[row][end] { best[row][end] = widest; start[row][end] = begin }
            }
        }
    }
    var ranges: [Range<Int>] = [], end = count
    for row in stride(from: rows, to: 0, by: -1) {
        ranges.insert(start[row][end]..<end, at: 0)
        end = start[row][end]
    }
    assert(ranges.count == rows && ranges.first?.lowerBound == 0 && ranges.last?.upperBound == count
           && zip(ranges, ranges.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound && !$0.isEmpty }, "rows cover every word once")
    return ranges
}

// MARK: - Glyph outlines

/// A word's glyph outlines at `Metrics.referenceSize`, baseline at y = 0, y down, in reading order.
private struct Outline {
    let path: CGPath
    let width: CGFloat

    /// Outlines are built once per font and word; a song repeats its words, so the cache stays small.
    private static var cache: [String: Outline] = [:]
    private static let cacheLimit = 512

    static func of(_ text: String, in lyricFont: LyricFont) -> Outline {
        let key = lyricFont.rawValue + "\u{1F}" + text
        if let hit = cache[key] { return hit }
        let font = lyricFont.font(size: Metrics.referenceSize) as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            // A run may fall back to another font (accents, symbols); its glyphs belong to that font.
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var placement = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: -position.y)
                // Variable fonts draw a glyph as overlapping contours; the pen should trace only the visible edge.
                if let outline = CTFontCreatePathForGlyph(runFont, glyph, &placement) { path.addPath(outline.normalized()) }
            }
        }
        let outline = Outline(path: path, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = outline
        return outline
    }
}

// MARK: - Page

private struct InkWord {
    let word: TimedWord
    let outline: Outline
    let origin: CGPoint                               // left end of the baseline, in the canvas
}

private struct InkPage {
    let words: [InkWord]
    let fontSize: CGFloat
    let position: Double
    let text: Color, highlight: NSColor, ink: NSColor
    let reduceMotion: Bool
    let fallbackFont: Font

    init(words lineWords: [TimedWord], context: StyleContext) {
        let width = context.canvas.width, band = context.band
        let outlines = lineWords.map { Outline.of($0.text, in: context.settings.font) }
        let reference = context.settings.font.font(size: Metrics.referenceSize)
        let gap = CGFloat(Metrics.wordGap) * Metrics.referenceSize
        let lineHeight = (reference.ascender - reference.descender) * CGFloat(Metrics.lineHeight)
        // Rows are chosen at the reference size, then the whole block is scaled to the font size, or less if it must fit.
        let byCount = Int((Double(outlines.count) / Metrics.wordsPerRow).rounded(.up))
        var size = band * CGFloat(Metrics.fontSize * context.scale)
        let limit = min(width * CGFloat(Metrics.maxWidth * context.scale), width * CGFloat(Metrics.fit)) * Metrics.referenceSize / size
        let steps = outlines.map { $0.width + gap }
        let byWidth = Int((steps.reduce(0, +) / limit).rounded(.up))
        let rows = balancedRows(steps, rows: min(Metrics.maxRows, max(byCount, byWidth)))
        let rowWidths = rows.map { range in steps[range].reduce(0, +) - gap }
        let blockHeight = lineHeight * CGFloat(rows.count)
        size = min(size, width * CGFloat(Metrics.fit) * Metrics.referenceSize / max(1, rowWidths.max() ?? 1),
                   band * CGFloat(Metrics.fit) * Metrics.referenceSize / blockHeight)
        let k = size / Metrics.referenceSize
        var placed: [InkWord] = []
        for (row, range) in rows.enumerated() {
            var x = (width - rowWidths[row] * k) / 2
            let baseline = band / 2 + (CGFloat(row) * lineHeight - blockHeight / 2 + reference.ascender + (lineHeight - reference.ascender + reference.descender) / 2) * k
            for index in range {
                placed.append(InkWord(word: lineWords[index], outline: outlines[index], origin: CGPoint(x: x, y: baseline)))
                x += steps[index] * k
            }
        }
        words = placed
        fontSize = size
        position = context.position
        text = Color(nsColor: context.settings.textColor)
        highlight = context.settings.highlightColor
        ink = context.settings.textColor
        reduceMotion = context.settings.reduceMotion
        fallbackFont = context.font(size)
    }

    // MARK: Drawing

    private struct Stage {
        let path: Path
        let trace: Path                               // the part of the outline the pen has drawn so far
        let written: Double                           // how much of the outline the pen has traced, 0…1
        let soak: Double                              // how far the fill has soaked in, 0…1
        let wet: Color                                // the fill's colour as it dries
    }

    private func stages() -> [(InkWord, Stage)] {
        words.filter { position >= $0.word.start }.map { inkWord in
            let word = inkWord.word, time = Pen.writingTime(of: word)
            let k = fontSize / Metrics.referenceSize
            let placement = CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: inkWord.origin.x, ty: inkWord.origin.y)
            let written = 1 - pow(1 - unit((position - word.start) / time), Pen.ease)
            let soak = unit((position - word.start - time * Pen.soakFrom) / Pen.soak)
            let dry = unit((position - word.start - time) / Pen.dry)
            let wet = Color(nsColor: highlight.blended(withFraction: dry, of: ink) ?? ink)
            let path = Path(inkWord.outline.path).applying(placement)
            let trace = written < 1 ? path.trimmedPath(from: 0, to: written) : path
            return (inkWord, Stage(path: path, trace: trace, written: written, soak: soak, wet: wet))
        }
    }

    func draw(in context: GraphicsContext, opacity: Double) {
        guard opacity > 0 else { return }
        var graphics = context
        graphics.opacity = opacity
        let stages = stages()
        // A soft dark halo under the ink (not the nib) keeps thin, still-wet strokes readable over a bright wallpaper.
        // The halo is cast by the finished layer as one piece; on single shapes it would darken the fill under each stroke.
        graphics.drawLayer { halo in
            halo.addFilter(.shadow(color: .black.opacity(Metrics.shadowOpacity), radius: fontSize * Metrics.shadowRadius,
                                   x: 0, y: fontSize * Metrics.shadowDrop))
            halo.drawLayer { page in
                drawBleed(stages, in: page)
                drawInk(stages, in: page)
            }
        }
        guard !reduceMotion else { return }
        for (_, stage) in stages where stage.written < 1 {
            if let nib = stage.trace.currentPoint { drawNib(at: nib, in: graphics) }
        }
    }

    /// A blurred copy of the soaking fill, so the ink spreads softly into the page, then settles to a faint edge.
    private func drawBleed(_ stages: [(InkWord, Stage)], in graphics: GraphicsContext) {
        graphics.drawLayer { layer in
            layer.addFilter(.blur(radius: fontSize * Metrics.bleedRadius))
            for (_, stage) in stages where stage.soak > 0 {
                var bleed = layer
                bleed.opacity = Metrics.bleedOpacity * stage.soak * (1 - (1 - Metrics.bleedRest) * stage.soak)
                bleed.fill(stage.path, with: .color(stage.wet))
            }
        }
    }

    private func drawInk(_ stages: [(InkWord, Stage)], in graphics: GraphicsContext) {
        let lineWidth = max(Metrics.minStrokeWidth, fontSize * Metrics.strokeWidth)
        for (inkWord, stage) in stages {
            guard !stage.path.isEmpty else {
                drawFallback(inkWord, written: stage.written, in: graphics)
                continue
            }
            if stage.soak > 0 {
                var fill = graphics
                fill.opacity = 1 - pow(1 - stage.soak, 2)
                fill.fill(stage.path, with: .color(stage.wet))
            }
            graphics.stroke(stage.trace, with: .color(text), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    /// The pen's wet tip at the end of the stroke being drawn.
    private func drawNib(at point: CGPoint, in graphics: GraphicsContext) {
        let radius = fontSize * Metrics.nibRadius
        graphics.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)),
                      with: .color(Color(nsColor: highlight)))
    }

    /// A word with no outlines to trace (an emoji, say) simply fades in as it is sung.
    private func drawFallback(_ inkWord: InkWord, written: Double, in graphics: GraphicsContext) {
        var faded = graphics
        faded.opacity = written
        faded.draw(Text(inkWord.word.text).font(fallbackFont).foregroundStyle(text), at: inkWord.origin, anchor: .bottomLeading)
    }
}
