import SwiftUI

/// Ransom Note: every word is a scrap cut from a different magazine, with its own typeface, paper, tilt and
/// torn or scissored edge, some held down by a strip of tape. A word slaps onto the page when it is sung.
/// The user's font is ignored on purpose; Size still applies. Everything is a pure function of the song position.
struct RansomNoteStyle: View {
    let context: StyleContext

    var body: some View {
        // GeometryReader can hand out an empty size on its first pass; there is nothing to lay out then.
        if context.canvas.width > 0, context.band > 0 {
            let note = RansomNote(context: context)
            // Taller than the band: the layout fits the band, and a word in mid-air may reach into the margin.
            Canvas { graphics, _ in note.draw(in: graphics) }
                .frame(width: context.canvas.width, height: context.band * (1 + 2 * Metrics.overflow))
                .frame(width: context.canvas.width, height: context.band)
                .opacity(note.opacity)
        }
    }
}

// MARK: - Constants

private enum Metrics {
    static let capHeight = 0.092                     // of the band, before Size: the cap height every typeface is matched to
    static let capVariation = 0.8...1.18             // each cutting is a little bigger or smaller
    static let maxWidth = 0.5                        // of the screen width at Size 100%, before the block is clamped
    static let wordsPerRow = 3.4                     // a line of this many words or more wraps to two rows, and so on
    static let maxRows = 3
    static let padX = 0.3, padY = 0.26               // paper around the letters, in cap heights
    static let overlap = 0.12                        // neighbouring scraps overlap by this many cap heights
    static let rowGap = -0.1                         // between rows, in cap heights
    static let rowJitter = 0.2                       // vertical scatter within a row, in cap heights
    static let tiltDegrees = 7.5
    static let tornStep = 0.32, tornAmplitude = 0.05, cutAmplitude = 0.14, tornChance = 0.55
    static let tapeChance = 0.38, tapeLength = 1.7, tapeThickness = 0.5, tapeTeeth = 4, tapeTilt = 32.0
    static let tape = Color(.sRGB, red: 0.97, green: 0.95, blue: 0.86, opacity: 0.5)
    static let shadowBlur = 0.11, shadowDrop = 0.07, shadowOpacity = 0.5
    static let uppercaseChance = 0.15
    static let fit = 0.96                            // of the band and of the screen width the settled block may use
    static let overflow = 0.2                        // of the band, above and below it, for a scrap still in the air
    static let fadeOut = 0.3
    static let cacheLimit = 8                        // laid-out lines kept (one per display is plenty)
}

private enum Slap {
    static let fall = 0.15                           // seconds from lifted to flat on the page
    static let lift = 0.55                           // extra scale while it is still in the air
    static let spin = 16.0                           // extra degrees of turn while it is in the air
    static let squash = 0.05, squashDecay = 0.07, squashRate = 38.0
    static let wobble = 3.0, wobbleDecay = 0.12, wobbleRate = 30.0
    static let fadeIn = 0.04, calmFadeIn = 0.12      // calm: with Reduce Motion the scrap only fades in
}

private enum Salt {
    static let face: UInt64 = 0xA001, paper: UInt64 = 0xA002, tilt: UInt64 = 0xA003, size: UInt64 = 0xA004
    static let upper: UInt64 = 0xA005, torn: UInt64 = 0xA006, tape: UInt64 = 0xA007, tapeSpot: UInt64 = 0xA008
    static let tapeTilt: UInt64 = 0xA009, spin: UInt64 = 0xA00A, jitter: UInt64 = 0xA00B, edge: UInt64 = 0xA100
    static let place: UInt64 = 0x1_0000                // times the word's place in the line, so repeated start times differ
}

/// A typeface cut from one "magazine". `name` nil is New York, the system serif.
private struct Face {
    let name: String?
    let upper: Bool                                   // set in capitals whatever the word

    static let all: [Face] = [
        Face(name: nil, upper: false), Face(name: "Didot-Bold", upper: false),
        Face(name: "Futura-CondensedExtraBold", upper: true), Face(name: "AvenirNextCondensed-Heavy", upper: false),
        Face(name: "AmericanTypewriter-Bold", upper: false), Face(name: "Menlo-Bold", upper: false),
        Face(name: "HelveticaNeue-CondensedBlack", upper: true), Face(name: "Rockwell-Bold", upper: false),
        Face(name: "Impact", upper: true), Face(name: "BodoniSvtyTwoITCTT-Bold", upper: false),
        Face(name: "Georgia-BoldItalic", upper: false), Face(name: "GillSans-UltraBold", upper: false),
        Face(name: "Copperplate-Bold", upper: true), Face(name: "SFRounded", upper: false),
    ]

    /// The named font, or the heavy system font when this Mac does not have it.
    func font(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: .heavy)
        switch name {
        case nil: return system.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case "SFRounded": return system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        case let name?: return NSFont(name: name, size: size) ?? system
        }
    }
}

/// Paper and the ink printed on it. Every pair is high contrast, so the words read over any wallpaper.
private struct Stock {
    let paper: Color
    let ink: Color

    static let all: [Stock] = [
        Stock(0xF2E6C9, 0x1A1712), Stock(0xD9D6CE, 0x121212), Stock(0xFAFAF5, 0xC8102E), Stock(0x161616, 0xF5F1E6),
        Stock(0xC8102E, 0xFFFFFF), Stock(0xF5C518, 0x111111), Stock(0xBFD7EA, 0x0B2545), Stock(0xF4B6C2, 0x2B0A12),
        Stock(0xC19A6B, 0x1A1209), Stock(0x2E5E4E, 0xF2E6C9),
    ]

    init(_ paper: Int, _ ink: Int) {
        func color(_ hex: Int) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        self.paper = color(paper)
        self.ink = color(ink)
    }
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

/// The glyph outlines of `text` set in `font`, baseline at y = 0, y down.
private func glyphOutline(_ text: String, font: NSFont) -> CGPath {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
        // A run may fall back to another font (accents, symbols); its glyphs belong to that font.
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font as CTFont
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        for (glyph, position) in zip(glyphs, positions) {
            var placement = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: -position.y)
            if let outline = CTFontCreatePathForGlyph(runFont, glyph, &placement) { path.addPath(outline) }
        }
    }
    return path
}

// MARK: - Layout

/// One word's cutting. Its paths are centred on the scrap; `centre` is in the block's coordinates.
private struct Scrap {
    let word: TimedWord
    let place: Int
    let letters: Path                                 // glyph outlines, ink centred on the origin
    let fallback: (text: String, font: Font)?         // for a word with no outlines to fill (an emoji, say)
    let paper: Path
    let tape: Path?
    let stock: Stock
    let cap: CGFloat
    let size: CGSize                                  // the paper's box before tilting
    let tilt: Double                                  // radians
    var centre = CGPoint.zero

    func seed(_ salt: UInt64) -> Double { Self.seed(word, place, salt) }

    static func seed(_ word: TimedWord, _ place: Int, _ salt: UInt64) -> Double {
        seededUnit(word.start, salt: salt &+ UInt64(place) &* Salt.place)
    }
}

/// A line cut and pasted once, then reused every frame it is on screen.
private struct Pasteup {
    let scraps: [Scrap]
    let origin: CGPoint                               // where the block's centre sits in the canvas
    let fitScale: CGFloat

    private static var cache: [String: Pasteup] = [:]

    static func of(_ context: StyleContext) -> Pasteup {
        let words = context.line.words
        let key = words.map { "\($0.start) \($0.text)" }.joined(separator: "|") + "|\(context.scale)|\(context.canvas.width)|\(context.band)"
        if let hit = cache[key] { return hit }
        let pasteup = Pasteup(context)
        if cache.count >= Metrics.cacheLimit { cache.removeAll() }
        cache[key] = pasteup
        return pasteup
    }

    private init(_ context: StyleContext) {
        let band = context.band, width = context.canvas.width
        let cap = band * Metrics.capHeight * context.scale
        var scraps = Self.cut(context.line.words, cap: cap)
        let step: [CGFloat] = scraps.map { $0.size.width - Metrics.overlap * cap }
        let limit: CGFloat = min(width * Metrics.maxWidth * context.scale, width * Metrics.fit)
        let byWidth = Int((step.reduce(0, +) / limit).rounded(.up))
        let byCount = Int((Double(scraps.count) / Metrics.wordsPerRow).rounded(.up))
        let bounds = Self.place(&scraps, rows: balancedRows(step, rows: min(Metrics.maxRows, max(byWidth, byCount))), cap: cap)
        // A block too big for the canvas is shrunk as a whole.
        let fit: CGFloat = min(1, width * Metrics.fit / bounds.width, band * Metrics.fit / bounds.height)
        let middle: CGFloat = band * (0.5 + Metrics.overflow)
        fitScale = fit
        origin = CGPoint(x: width / 2 - bounds.midX * fit, y: middle - bounds.midY * fit)
        self.scraps = scraps
    }

    private static func cut(_ words: [TimedWord], cap baseCap: CGFloat) -> [Scrap] {
        var lastFace = -1, lastStock = -1
        return words.enumerated().map { place, word in
            func seed(_ salt: UInt64) -> Double { Scrap.seed(word, place, salt) }
            // Neighbours never share a typeface or a paper.
            var face = Int(seed(Salt.face) * Double(Face.all.count))
            if face == lastFace { face = (face + 1) % Face.all.count }
            var stock = Int(seed(Salt.paper) * Double(Stock.all.count))
            if stock == lastStock { stock = (stock + 1) % Stock.all.count }
            lastFace = face
            lastStock = stock
            let spread = Metrics.capVariation.upperBound - Metrics.capVariation.lowerBound
            let cap = baseCap * (Metrics.capVariation.lowerBound + seed(Salt.size) * spread)
            let chosen = Face.all[face]
            // Every typeface is sized to the same cap height, so a thin Didot and a fat Impact read as one size.
            let font = chosen.font(size: 100 * cap / max(1, chosen.font(size: 100).capHeight))
            let text = chosen.upper || seed(Salt.upper) < Metrics.uppercaseChance ? word.text.uppercased() : word.text
            let outline = glyphOutline(text, font: font)
            let ink = outline.isEmpty ? CGRect(x: 0, y: -cap, width: cap, height: cap) : outline.boundingBoxOfPath
            let size = CGSize(width: ink.width + 2 * Metrics.padX * cap, height: max(ink.height, cap) + 2 * Metrics.padY * cap)
            let tilt = (2 * seed(Salt.tilt) - 1) * Metrics.tiltDegrees * .pi / 180
            return Scrap(word: word, place: place, letters: Path(outline).offsetBy(dx: -ink.midX, dy: -ink.midY),
                         fallback: outline.isEmpty ? (text, Font(font)) : nil, paper: paper(size: size, cap: cap, seed: seed),
                         tape: seed(Salt.tape) < Metrics.tapeChance ? tape(size: size, cap: cap, seed: seed) : nil,
                         stock: Stock.all[stock], cap: cap, size: size, tilt: tilt)
        }
    }

    /// Centres each row and stacks the rows; returns the settled block's bounds, tilt included.
    private static func place(_ scraps: inout [Scrap], rows: [Range<Int>], cap: CGFloat) -> CGRect {
        let heights = rows.map { range in scraps[range].map(\.size.height).max() ?? 0 }
        let total = heights.reduce(0, +) + Metrics.rowGap * cap * CGFloat(max(0, rows.count - 1))
        var y = -total / 2, bounds = CGRect.null
        for (row, range) in rows.enumerated() {
            let width = scraps[range].reduce(0) { $0 + $1.size.width } - Metrics.overlap * cap * CGFloat(range.count - 1)
            var x = -width / 2
            for index in range {
                let scrap = scraps[index]
                let jitter = (2 * scrap.seed(Salt.jitter) - 1) * Metrics.rowJitter * cap
                let centre = CGPoint(x: x + scrap.size.width / 2, y: y + heights[row] / 2 + jitter)
                scraps[index].centre = centre
                x += scrap.size.width - Metrics.overlap * cap
                // Half extents of the tilted paper.
                let cosine = abs(cos(scrap.tilt)), sine = abs(sin(scrap.tilt))
                let reach = CGSize(width: (scrap.size.width * cosine + scrap.size.height * sine) / 2,
                                   height: (scrap.size.width * sine + scrap.size.height * cosine) / 2)
                bounds = bounds.union(CGRect(x: centre.x - reach.width, y: centre.y - reach.height, width: 2 * reach.width, height: 2 * reach.height))
            }
            y += heights[row] + Metrics.rowGap * cap
        }
        return bounds
    }

    /// The scrap's outline: a ragged tear (many small steps) or a scissor cut (a few clipped corners).
    private static func paper(size: CGSize, cap: CGFloat, seed: (UInt64) -> Double) -> Path {
        let w = size.width / 2, h = size.height / 2
        let corners = [CGPoint(x: -w, y: -h), CGPoint(x: w, y: -h), CGPoint(x: w, y: h), CGPoint(x: -w, y: h)]
        let torn = seed(Salt.torn) < Metrics.tornChance
        let amplitude = (torn ? Metrics.tornAmplitude : Metrics.cutAmplitude) * cap
        var salt = Salt.edge
        func jitter() -> CGFloat { salt += 1; return CGFloat(2 * seed(salt) - 1) * amplitude }
        var path = Path()
        for side in 0..<4 {
            let from = corners[side], to = corners[(side + 1) % 4]
            let corner = CGPoint(x: from.x + jitter(), y: from.y + jitter())
            side == 0 ? path.move(to: corner) : path.addLine(to: corner)
            guard torn else { continue }
            let length = hypot(to.x - from.x, to.y - from.y)
            let steps = max(2, Int(length / (Metrics.tornStep * cap)))
            // Perpendicular to the side, pointing out of the paper.
            let normal = CGPoint(x: (to.y - from.y) / length, y: -(to.x - from.x) / length)
            for step in 1..<steps {
                let t = CGFloat(step) / CGFloat(steps), out = jitter()
                path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * t + normal.x * out, y: from.y + (to.y - from.y) * t + normal.y * out))
            }
        }
        path.closeSubpath()
        return path
    }

    /// A strip of translucent tape across the top edge, its ends torn in a zigzag.
    private static func tape(size: CGSize, cap: CGFloat, seed: (UInt64) -> Double) -> Path {
        let length = Metrics.tapeLength * cap, thickness = Metrics.tapeThickness * cap
        let along = (seed(Salt.tapeSpot) - 0.5) * 0.7 * max(0, size.width - length * 0.6)
        let angle = (2 * seed(Salt.tapeTilt) - 1) * Metrics.tapeTilt * .pi / 180
        let half = length / 2, tooth = thickness / CGFloat(Metrics.tapeTeeth)
        var path = Path()
        path.move(to: CGPoint(x: -half, y: -thickness / 2))
        path.addLine(to: CGPoint(x: half, y: -thickness / 2))
        for step in 1...Metrics.tapeTeeth {
            path.addLine(to: CGPoint(x: half + (step % 2 == 1 ? tooth * 0.5 : 0), y: -thickness / 2 + tooth * CGFloat(step)))
        }
        path.addLine(to: CGPoint(x: -half, y: thickness / 2))
        for step in 1...Metrics.tapeTeeth {
            path.addLine(to: CGPoint(x: -half - (step % 2 == 1 ? tooth * 0.5 : 0), y: thickness / 2 - tooth * CGFloat(step)))
        }
        path.closeSubpath()
        return path.applying(CGAffineTransform(translationX: CGFloat(along), y: -size.height / 2).rotated(by: angle))
    }
}

// MARK: - Drawing

private struct RansomNote {
    let pasteup: Pasteup
    let shown: Int
    let position: Double
    let reduceMotion: Bool
    let opacity: Double

    init(context: StyleContext) {
        pasteup = Pasteup.of(context)
        shown = context.line.shown
        position = context.position
        reduceMotion = context.settings.reduceMotion
        opacity = Self.lineOpacity(context)
    }

    /// Fades out as the line lingers, finishing before the next line takes its place, but never before the last
    /// scrap has landed: with no gap before the next line, the line is simply replaced.
    private static func lineOpacity(_ context: StyleContext) -> Double {
        guard let last = context.line.words.last else { return 1 }
        var gone = last.end + Timing.lineLinger
        let next = context.line.index + 1
        if context.lyrics.lines.indices.contains(next), let start = context.lyrics.lines[next].first?.start { gone = min(gone, start) }
        let fadeStart = max(gone - Metrics.fadeOut, last.start + Slap.fall)
        return fadeStart < gone ? unit((gone - context.position) / (gone - fadeStart)) : 1
    }

    func draw(in graphics: GraphicsContext) {
        var block = graphics
        block.translateBy(x: pasteup.origin.x, y: pasteup.origin.y)
        block.scaleBy(x: pasteup.fitScale, y: pasteup.fitScale)
        for scrap in pasteup.scraps.prefix(shown) where position >= scrap.word.start {
            draw(scrap, in: block)
        }
    }

    private func draw(_ scrap: Scrap, in block: GraphicsContext) {
        let age = position - scrap.word.start
        let fall = unit(age / Slap.fall)
        let air = reduceMotion ? 0 : (1 - fall) * (1 - fall)          // eases in: it speeds up as it drops
        let landed = max(0, age - Slap.fall)
        let settle = reduceMotion || fall < 1 ? 0 : 1.0
        let squash = settle * Slap.squash * exp(-landed / Slap.squashDecay) * cos(landed * Slap.squashRate)
        let wobble = settle * Slap.wobble * exp(-landed / Slap.wobbleDecay) * sin(landed * Slap.wobbleRate)
        let spin = (scrap.seed(Salt.spin) < 0.5 ? -1.0 : 1.0) * Slap.spin * air
        let scale = 1 + Slap.lift * air - squash
        var graphics = block
        graphics.opacity = unit(age / (reduceMotion ? Slap.calmFadeIn : Slap.fadeIn))
        graphics.translateBy(x: scrap.centre.x, y: scrap.centre.y)
        graphics.rotate(by: .radians(scrap.tilt + (spin + wobble) * .pi / 180))
        graphics.scaleBy(x: scale, y: scale)
        // A lifted scrap throws a wider, softer, further shadow; it tightens as the paper lands.
        let lift = 1 + 2.5 * air
        var shadowed = graphics
        shadowed.addFilter(.shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowBlur * scrap.cap * lift,
                                   x: 0, y: Metrics.shadowDrop * scrap.cap * lift))
        shadowed.fill(scrap.paper, with: .color(scrap.stock.paper))
        if let fallback = scrap.fallback {
            graphics.draw(Text(fallback.text).font(fallback.font).foregroundStyle(scrap.stock.ink), at: .zero)
        } else {
            graphics.fill(scrap.letters, with: .color(scrap.stock.ink))
        }
        if let tape = scrap.tape { graphics.fill(tape, with: .color(Metrics.tape)) }
    }
}
