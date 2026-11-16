import SwiftUI

/// Highlighter: the whole line is printed in pale ink on a softly rounded paper card. As each word is sung a felt
/// marker swipes across it, left to right over the word's duration, and the ink under the swipe darkens. Words held
/// a long time also get a loose pen circle drawn around them. Everything is a closed-form function of the song
/// position: the layout depends only on the line, and the marks only on each word's own timing.
struct HighlighterStyle: View {
    let context: StyleContext

    var body: some View {
        // GeometryReader can hand out an empty size on its first pass; laying out then would divide by zero.
        if context.canvas.width > 0, context.band > 0 { card(Page(context: context)) }
    }

    private func card(_ page: Page) -> some View {
        let rise = context.settings.reduceMotion ? 0 : (1 - page.presence) * Metrics.rise * page.fontSize
        return ZStack {
            // The card's shadow lives outside the Canvas so it is not redrawn by hand every frame.
            RoundedRectangle(cornerRadius: page.cornerRadius, style: .continuous)
                .fill(Metrics.paper)
                .shadow(color: .black.opacity(Metrics.farShadowOpacity), radius: Metrics.farShadowRadius, y: Metrics.farShadowY)
                .shadow(color: .black.opacity(Metrics.nearShadowOpacity), radius: Metrics.nearShadowRadius, y: Metrics.nearShadowY)
            Canvas { graphics, _ in page.draw(in: &graphics) }
        }
        .frame(width: page.size.width, height: page.size.height)
        .offset(y: rise)
        .opacity(page.presence)
    }
}

private enum Metrics {
    // Card, as fractions of its width unless noted.
    static let cardWidth = 0.5, widestCard = 0.94, tallestCard = 0.8     // of the screen
    static let narrowestCard = 0.62                                       // of the full card width
    static let fontSize = 0.078, sidePadding = 0.075
    static let topPadding = 0.75, rowHeight = 1.42, baselineDrop = 0.3   // of the font size
    static let cornerRadius = 0.035
    static let maxRows = 3, wrapFrom = 3                                  // lines of this many words or more get two rows at least
    static let paper = Color(.sRGB, red: 0.984, green: 0.973, blue: 0.945)
    static let border = Color.black.opacity(0.07)
    static let farShadowOpacity = 0.34, farShadowRadius = 22.0, farShadowY = 10.0
    static let nearShadowOpacity = 0.2, nearShadowRadius = 2.5, nearShadowY = 1.0

    // Ink
    static let ink = Color(.sRGB, red: 0.09, green: 0.086, blue: 0.11)
    static let paleInk = 0.3, sungInk = 0.96

    // Marker, as fractions of the font size.
    static let classicYellow = NSColor(srgbRed: 1, green: 0.88, blue: 0.2, alpha: 1)
    static let minSaturation = 0.3, minLuma = 0.42                      // a deep blue is "bright" in HSB but dark on paper
    static let markerOpacity = 0.72, edgeOpacity = 0.25, edgeWidth = 0.045
    static let markerTop = 0.8, markerBottom = 0.2                       // above and below the baseline
    static let overhang = 0.12, chisel = 0.03, roundness = 0.1
    static let wobble = 0.025, wobbleWave = 2.4, tilt = 0.05, drift = 0.025, swell = 0.05
    static let edgeStep = 0.22
    static let minSweep = 0.15

    // Pen circle around long-held words.
    static let longHeld = 0.85                                            // seconds; the sample's 0.9 s word must qualify
    static let longAgainstLine = 1.6                                      // times the line's mean, so slow interpolated lines are not all circled
    static let pen = Color(.sRGB, red: 0.78, green: 0.2, blue: 0.17)
    static let penOpacity = 0.85, penWidth = 0.055
    static let circleReachX = 0.26, circleReachY = 0.64, circleLift = 0.06
    static let circleTurns = 1.13, circleSpiral = 0.06, circleWobble = 0.04, circleTiltDegrees = 4.0
    static let circleSegments = 72

    // Scene
    static let fadeIn = 0.3, fadeOut = 0.5, inkIn = 0.18, rise = 0.25
}

private enum Salt {
    static let lift: UInt64 = 0x4811, height: UInt64 = 0x4812, tilt: UInt64 = 0x4813
    static let topPhase: UInt64 = 0x4814, bottomPhase: UInt64 = 0x4815, wave: UInt64 = 0x4816
    static let circleStart: UInt64 = 0x4817, circleTilt: UInt64 = 0x4818, circlePhase: UInt64 = 0x4819
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
private func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }

/// How visible the card is: it fades in after a silence and out before one, never between joined lines.
private func visibility(_ context: StyleContext) -> Double {
    let lines = context.lyrics.lines, index = context.line.index
    guard let first = context.line.words.first?.start, let lastEnd = context.line.words.last?.end else { return 1 }
    let opensAfterGap = index == 0 || first - (lines[index - 1].last?.end ?? 0) > Timing.lineLinger
    let closesIntoGap = index + 1 >= lines.count || lines[index + 1][0].start - lastEnd > Timing.lineLinger
    let fadeIn = opensAfterGap ? unit((context.position - first) / Metrics.fadeIn) : 1
    let fadeOut = closesIntoGap ? unit((lastEnd + Timing.lineLinger - context.position) / Metrics.fadeOut) : 1
    return smooth(fadeIn) * smooth(fadeOut)
}

/// The marker colour: the highlight colour when it is bright and colourful enough to read as a highlighter on
/// paper, otherwise classic yellow (the default highlight is white, which would vanish).
private func markerColor(_ highlight: NSColor) -> Color {
    let colour = highlight.usingColorSpace(.sRGB) ?? highlight
    let luma = 0.299 * colour.redComponent + 0.587 * colour.greenComponent + 0.114 * colour.blueComponent
    let usable = colour.saturationComponent >= Metrics.minSaturation && luma >= Metrics.minLuma
    return Color(nsColor: usable ? colour.withAlphaComponent(1) : Metrics.classicYellow)
}

/// The serif the card is printed in: the chosen lyric font when it is a serif, otherwise New York.
private func serif(_ font: LyricFont, size: CGFloat) -> NSFont {
    font == .newYork || font == .didot ? font.font(size: size) : LyricFont.newYork.font(size: size)
}

/// Splits widths into exactly `rows` consecutive runs with the narrowest widest run.
private func balancedBreaks(_ widths: [Double], space: Double, rows: Int) -> [Range<Int>] {
    let count = widths.count
    guard rows > 1, count > rows else { return rows >= count ? widths.indices.map { $0..<($0 + 1) } : [0..<count] }
    func span(_ range: Range<Int>) -> Double { widths[range].reduce(0, +) + Double(max(0, range.count - 1)) * space }
    // best[r][i]: the narrowest widest run when the first i words fill r rows, with where the last run starts.
    var best = Array(repeating: Array(repeating: (width: Double.infinity, from: 0), count: count + 1), count: rows + 1)
    best[0][0] = (0, 0)
    for row in 1...rows {
        for end in row...count {
            for start in (row - 1)..<end where best[row - 1][start].width < .infinity {
                let widest = max(best[row - 1][start].width, span(start..<end))
                if widest < best[row][end].width { best[row][end] = (widest, start) }
            }
        }
    }
    var ranges: [Range<Int>] = [], end = count
    for row in stride(from: rows, to: 0, by: -1) {
        let start = best[row][end].from
        ranges.insert(start..<end, at: 0)
        end = start
    }
    return ranges
}

/// One word, placed on the card.
private struct Slot {
    let word: TimedWord
    let x: Double, width: Double
    let baseline: Double
    let circled: Bool       // held long enough, in seconds and against its line, to earn a pen loop
}

private struct Page {
    let size: CGSize
    let cornerRadius: Double
    let fontSize: Double
    let font: Font
    let slots: [Slot]
    let marker: Color
    let position: Double
    let presence: Double
    let inkIn: Double

    init(context: StyleContext) {
        let words = context.line.words
        let meanHeld = words.reduce(0) { $0 + ($1.end - $1.start) } / Double(max(1, words.count))
        let fullWidth = min(context.canvas.width * Metrics.widestCard, context.canvas.width * Metrics.cardWidth * context.scale)
        let inner = fullWidth * (1 - 2 * Metrics.sidePadding)
        let wish = fullWidth * Metrics.fontSize
        let measuring = serif(context.settings.font, size: wish)
        let widths = words.map { Double(($0.text as NSString).size(withAttributes: [.font: measuring]).width) }
        let space = Double((" " as NSString).size(withAttributes: [.font: measuring]).width)
        let total = widths.reduce(0, +) + Double(max(0, words.count - 1)) * space
        let floor = words.count >= Metrics.wrapFrom ? 2 : 1
        let rows = min(words.count, max(floor, min(Metrics.maxRows, Int((total / inner).rounded(.up)))))
        let ranges = balancedBreaks(widths, space: space, rows: max(1, rows))
        let widest = ranges.map { range in widths[range].reduce(0, +) + Double(max(0, range.count - 1)) * space }.max() ?? 0
        // Shrink to fit the widest row across, and the whole card into the screen's height.
        let tallest = context.canvas.height * Metrics.tallestCard
        let heightPerFont = Double(ranges.count) * Metrics.rowHeight + 2 * Metrics.topPadding
        let fit = min(1, widest > 0 ? inner / widest : 1, tallest / (heightPerFont * wish))
        let fontSize = wish * fit
        self.fontSize = fontSize
        // A short line gets a narrower card rather than a lot of empty paper.
        let cardWidth = max(fullWidth * Metrics.narrowestCard, widest * fit + 2 * fullWidth * Metrics.sidePadding)
        size = CGSize(width: cardWidth, height: heightPerFont * fontSize)
        cornerRadius = fullWidth * Metrics.cornerRadius
        font = Font(serif(context.settings.font, size: fontSize) as CTFont)
        slots = ranges.enumerated().flatMap { row, range -> [Slot] in
            let rowWidth = (widths[range].reduce(0, +) + Double(max(0, range.count - 1)) * space) * fit
            let baseline = (Metrics.topPadding + (Double(row) + 0.5) * Metrics.rowHeight + Metrics.baselineDrop) * fontSize
            var x = (cardWidth - rowWidth) / 2
            return range.map { index in
                defer { x += (widths[index] + space) * fit }
                let held = words[index].end - words[index].start
                return Slot(word: words[index], x: x, width: widths[index] * fit, baseline: baseline,
                            circled: held >= Metrics.longHeld && held >= Metrics.longAgainstLine * meanHeld)
            }
        }
        marker = markerColor(context.settings.highlightColor)
        position = context.position
        presence = visibility(context)
        let first = words.first?.start ?? context.position
        inkIn = context.settings.reduceMotion ? 1 : smooth(unit((context.position - first) / Metrics.inkIn))
    }

    // MARK: Drawing

    func draw(in graphics: inout GraphicsContext) {
        let card = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius, style: .continuous)
        graphics.fill(card, with: .color(Metrics.paper))
        graphics.stroke(card, with: .color(Metrics.border), lineWidth: 1)
        let sweeps = slots.map { sweep(of: $0.word) }
        // Marker first and multiplied, as ink soaks into paper; overlapping swipes darken a little where they meet.
        var markerLayer = graphics
        markerLayer.blendMode = .multiply
        for (slot, sweep) in zip(slots, sweeps) where sweep > 0 { drawSwipe(slot, sweep: sweep, in: &markerLayer) }
        for (slot, sweep) in zip(slots, sweeps) { drawWord(slot, sweep: sweep, in: &graphics) }
        for (slot, sweep) in zip(slots, sweeps) where sweep > 0 && slot.circled {
            drawCircle(slot, sweep: sweep, in: &graphics)
        }
    }

    /// How far the marker has crossed the word, 0...1, easing out like a hand slowing at the end of a stroke.
    private func sweep(of word: TimedWord) -> Double {
        let raw = unit((position - word.start) / max(Metrics.minSweep, word.end - word.start))
        return 1 - pow(1 - raw, 1.6)
    }

    private func drawSwipe(_ slot: Slot, sweep: Double, in graphics: inout GraphicsContext) {
        let f = fontSize, seed = slot.word.start
        func jitter(_ salt: UInt64) -> Double { 2 * seededUnit(seed, salt: salt) - 1 }
        let start = slot.x - Metrics.overhang * f
        let end = start + (slot.width + 2 * Metrics.overhang * f) * sweep
        let lift = Metrics.drift * f * jitter(Salt.lift)
        let swell = 1 + Metrics.swell * jitter(Salt.height)
        let top = slot.baseline - Metrics.markerTop * f * swell + lift, bottom = slot.baseline + Metrics.markerBottom * f * swell + lift
        let slope = Metrics.tilt * f * jitter(Salt.tilt) / max(f, slot.width)
        let wave = 2 * .pi / (Metrics.wobbleWave * f * (0.8 + 0.4 * seededUnit(seed, salt: Salt.wave)))
        let topPhase = 2 * .pi * seededUnit(seed, salt: Salt.topPhase), bottomPhase = 2 * .pi * seededUnit(seed, salt: Salt.bottomPhase)
        func edge(_ x: Double, _ y: Double, _ phase: Double) -> CGPoint {
            CGPoint(x: x, y: y + slope * (x - start) + Metrics.wobble * f * (sin(wave * x + phase) + 0.5 * sin(2.3 * wave * x + 2 * phase)))
        }
        let steps = max(2, Int(((end - start) / (Metrics.edgeStep * f)).rounded(.up)))
        let xs = (0...steps).map { start + (end - start) * Double($0) / Double(steps) }
        let chisel = Metrics.chisel * f
        let topEdge = xs.map { edge($0, top, topPhase) }, bottomEdge = xs.map { edge($0, bottom, bottomPhase) }
        let round = Metrics.roundness * f
        func middle(_ index: Int) -> Double { (topEdge[index].y + bottomEdge[index].y) / 2 }
        // The felt tip leans a little, and its worn ends are rounded.
        let shape = Path { path in
            path.move(to: CGPoint(x: topEdge[0].x + chisel, y: topEdge[0].y))
            // addLines would start a new subpath, so the edges are followed point by point.
            for point in topEdge.dropFirst() { path.addLine(to: CGPoint(x: point.x + chisel, y: point.y)) }
            path.addQuadCurve(to: CGPoint(x: bottomEdge[steps].x - chisel, y: bottomEdge[steps].y),
                              control: CGPoint(x: end + round, y: middle(steps)))
            for point in bottomEdge.reversed().dropFirst() { path.addLine(to: CGPoint(x: point.x - chisel, y: point.y)) }
            path.addQuadCurve(to: CGPoint(x: topEdge[0].x + chisel, y: topEdge[0].y), control: CGPoint(x: start - round, y: middle(0)))
            path.closeSubpath()
        }
        graphics.fill(shape, with: .color(marker.opacity(Metrics.markerOpacity)))
        // Ink pools a little along the edges of a felt stroke.
        let edges = Path { path in
            path.addLines(topEdge.map { CGPoint(x: $0.x + chisel, y: $0.y) })
            path.addLines(bottomEdge.map { CGPoint(x: $0.x - chisel, y: $0.y) })
        }
        graphics.stroke(edges, with: .color(marker.opacity(Metrics.edgeOpacity)),
                        style: StrokeStyle(lineWidth: Metrics.edgeWidth * f, lineCap: .round, lineJoin: .round))
    }

    private func drawWord(_ slot: Slot, sweep: Double, in graphics: inout GraphicsContext) {
        var resolved = graphics.resolve(Text(slot.word.text).font(font))
        let measured = resolved.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
        let origin = CGPoint(x: slot.x, y: slot.baseline - resolved.firstBaseline(in: measured))
        resolved.shading = .color(Metrics.ink.opacity(Metrics.paleInk * inkIn))
        graphics.draw(resolved, at: origin, anchor: .topLeading)
        guard sweep > 0 else { return }
        // The ink darkens exactly as far as the marker has reached.
        var inked = graphics
        let reach = slot.x - Metrics.overhang * fontSize + (slot.width + 2 * Metrics.overhang * fontSize) * sweep
        inked.clip(to: Path(CGRect(x: 0, y: 0, width: reach, height: size.height)))
        resolved.shading = .color(Metrics.ink.opacity(Metrics.sungInk))
        inked.draw(resolved, at: origin, anchor: .topLeading)
    }

    /// A loose pen loop around the word: a little more than one turn, wobbling and spiralling out so its ends cross.
    private func drawCircle(_ slot: Slot, sweep: Double, in graphics: inout GraphicsContext) {
        let f = fontSize, seed = slot.word.start
        let centre = CGPoint(x: slot.x + slot.width / 2, y: slot.baseline - (Metrics.markerTop - Metrics.markerBottom) / 2 * f - Metrics.circleLift * f)
        let radiusX = slot.width / 2 + Metrics.circleReachX * f, radiusY = Metrics.circleReachY * f
        let tilt = Metrics.circleTiltDegrees * .pi / 180 * (2 * seededUnit(seed, salt: Salt.circleTilt) - 1)
        let begin = .pi * (0.95 + 0.25 * seededUnit(seed, salt: Salt.circleStart))   // upper left, where a hand starts a loop
        let phase = 2 * .pi * seededUnit(seed, salt: Salt.circlePhase)
        let points = (0...Metrics.circleSegments).map { step -> CGPoint in
            let t = Double(step) / Double(Metrics.circleSegments)
            let angle = begin + 2 * .pi * Metrics.circleTurns * t
            let grow = 1 + Metrics.circleSpiral * t + Metrics.circleWobble * sin(2 * angle + phase)
            let x = radiusX * grow * cos(angle), y = radiusY * grow * sin(angle)
            return CGPoint(x: centre.x + x * cos(tilt) - y * sin(tilt), y: centre.y + x * sin(tilt) + y * cos(tilt))
        }
        let loop = Path { $0.addLines(points) }.trimmedPath(from: 0, to: sweep)
        graphics.stroke(loop, with: .color(Metrics.pen.opacity(Metrics.penOpacity)),
                        style: StrokeStyle(lineWidth: Metrics.penWidth * f, lineCap: .round, lineJoin: .round))
    }
}
