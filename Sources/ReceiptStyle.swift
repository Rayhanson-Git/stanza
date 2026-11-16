import AppKit
import SwiftUI

/// Receipt: the song printed on a strip of thermal paper hanging from a till's slot. The till's name and the track
/// stay printed at the top; each word prints letter by letter as it is sung, every finished line gets a dotted rule,
/// and the paper feeds out longer until it reaches its full length, after which older lines scroll up under the
/// header. Each frame is worked out from the playback position alone, so there is no view state.
struct ReceiptStyle: View {
    let context: StyleContext

    var body: some View {
        let receipt = TillReceipt(context: context)
        // As tall as the screen and centred on the band, so a large Size is never cut off by the band.
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, size in
            receipt.draw(in: graphics, size: size)
        }
        .frame(width: context.canvas.width, height: context.canvas.height)
        .opacity(receipt.opacity)
    }
}

private enum TillMetrics {
    static let columns = 28, textColumns = 22, timeColumns = 5
    /// At Size 100% the receipt is a bit over a quarter of the canvas wide and at most this share of it tall, slot to torn edge.
    static let widthShare: CGFloat = 0.28, heightShare: CGFloat = 0.45
    /// The receipt is never shorter than this many font sizes, so a wide, short canvas still fits a few lines.
    static let minimumLength: CGFloat = 16
    static let sidePad: CGFloat = 1.5                // character advances each side of the text
    // Lengths in font sizes.
    static let slotHeight: CGFloat = 1.25, slotOverhang: CGFloat = 0.7, slitHeight: CGFloat = 0.16
    static let headerTop: CGFloat = 0.9, titleSize: CGFloat = 1.22, titleRow: CGFloat = 1.75
    static let rowHeight: CGFloat = 1.34, ruleRow: CGFloat = 0.85, headerRule: CGFloat = 1.0
    static let bottomPad: CGFloat = 0.9, toothWidth: CGFloat = 0.9, toothDepth: CGFloat = 0.5
    static let dotRadius: CGFloat = 0.075, curl: CGFloat = 1.6
    static let shadowRadius: CGFloat = 0.8, shadowDrop: CGFloat = 0.35
    static let jitterX: CGFloat = 0.12, jitterY: CGFloat = 0.16
    // Timing, in seconds.
    static let feed = 0.16, longestPrint = 0.8, fresh = 0.14, inkUp = 0.07, ruleDraw = 0.22, fadeIn = 0.2
    // Ink strengths.
    static let olderInk = 0.62, faintInk = 0.5, freshInk = 0.4

    /// The width of one character of the monospaced font, as a share of its size.
    static let advance: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .medium)
        return NSAttributedString(string: "0", attributes: [.font: font]).size().width / 100
    }()
}

private enum TillPaint {
    static let paper = Color(red: 0.976, green: 0.966, blue: 0.94)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.1)
    static let slotTop = Color(white: 0.24), slotBottom = Color(white: 0.07)
}

/// One word, or one row-wide piece of a word too long for a row, placed on a row of the paper.
private struct TillPlacement {
    let word: Int, row: Int, column: Int
    /// Where this piece starts within its word.
    let offset: Int
    /// One letter each, or a whole word in a script whose letters join, followed by blanks for the rest of its width.
    let glyphs: [String]
}

/// How many monospaced columns a whole word covers in the receipt's type.
/// Measured once per word: the receipt is laid out on every frame.
@MainActor private var tillSpans: [String: Int] = [:]

private func tillSpan(of word: String) -> Int {
    if let known = MainActor.assumeIsolated({ tillSpans[word] }) { return known }
    let size: CGFloat = 100
    let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
    let width = NSAttributedString(string: word, attributes: [.font: font]).size().width
    let span = max(1, Int((width / (TillMetrics.advance * size)).rounded(.up)))
    MainActor.assumeIsolated {
        if tillSpans.count > 512 { tillSpans.removeAll() }
        tillSpans[word] = span
    }
    return span
}

/// Greedy word wrap onto rows `columns` characters wide; a word longer than a row is broken across rows.
private func tillWrap(_ words: [TimedWord], columns: Int) -> (placements: [TillPlacement], rows: Int) {
    var placements = [TillPlacement](), row = 0, column = 0
    for (index, word) in words.enumerated() {
        let glyphs: [String] = LyricsScript.joinsLetters(word.text)
            ? [word.text] + Array(repeating: "", count: tillSpan(of: word.text) - 1)
            : word.text.map(String.init)
        var start = 0
        while start < glyphs.count {
            let chunk = Array(glyphs[start..<min(start + columns, glyphs.count)])
            if column > 0 && column + 1 + chunk.count > columns {
                row += 1
                column = 0
            } else if column > 0 {
                column += 1
            }
            placements.append(TillPlacement(word: index, row: row, column: column, offset: start, glyphs: chunk))
            column += chunk.count
            start += chunk.count
        }
    }
    return (placements, row + 1)
}

/// A printed row below the header: part of a lyric line, or the dotted rule after a finished one.
private struct TillRow {
    let line: Int
    /// The wrapped row of the line, or nil for the rule.
    let row: Int?
    /// When the paper starts feeding out for it.
    let feed: Double
    let height: CGFloat
}

private struct TillReceipt {
    let context: StyleContext
    let opacity: Double

    init(context: StyleContext) {
        self.context = context
        let lines = context.lyrics.lines, index = context.line.index, time = context.position
        let lineStart = lines[index][0].start
        // The receipt fades in with the first line and then stays up through gaps, dimming like Messages.
        let appear = index > 0 ? 1 : min(1, max(0, (time - lineStart) / TillMetrics.fadeIn))
        opacity = min(appear, context.gapPresence)
    }

    private var time: Double { context.position }

    /// How far the paper has fed out for a row: 0 before it starts, 1 once it is out.
    private func fed(_ row: TillRow) -> CGFloat {
        guard time >= row.feed else { return 0 }
        if context.settings.reduceMotion { return 1 }
        let x = min(1, (time - row.feed) / TillMetrics.feed)
        return CGFloat(x * x * (3 - 2 * x))
    }

    /// The rows that can be on the paper, newest first, from the line being sung back until `room` is full.
    private func rows(room: CGFloat, font: CGFloat) -> [TillRow] {
        let lines = context.lyrics.lines
        var rows = [TillRow](), filled: CGFloat = 0
        var line = context.line.index
        while line >= 0 && filled <= room + TillMetrics.rowHeight * font {
            let words = lines[line]
            let wrapped = tillWrap(words, columns: TillMetrics.textColumns)
            var lineRows = (0..<wrapped.rows).map { row in
                let first = wrapped.placements.first { $0.row == row }.map { words[$0.word].start } ?? words[0].start
                return TillRow(line: line, row: row, feed: first, height: TillMetrics.rowHeight * font)
            }
            lineRows.append(TillRow(line: line, row: nil, feed: words.last?.end ?? words[0].start, height: TillMetrics.ruleRow * font))
            for row in lineRows.reversed() where row.feed <= time {
                rows.append(row)
                // Counted as fed so far, the same as the paper's length, so dropping older lines never shortens it.
                filled += row.height * fed(row)
            }
            line -= 1
        }
        return rows
    }

    // MARK: Drawing

    func draw(in graphics: GraphicsContext, size: CGSize) {
        let m = TillMetrics.self
        let widthUnits = (CGFloat(m.columns) + 2 * m.sidePad) * m.advance
        let fitted = min(size.width * m.widthShare / widthUnits, size.height * m.heightShare / m.minimumLength)
        let font = fitted * CGFloat(context.scale)
        guard font > 0 else { return }
        let length = size.height * m.heightShare * CGFloat(context.scale)
        let paperWidth = widthUnits * font
        // The slot stays put while the paper feeds out below it.
        let top = (size.height - length) / 2
        let paperLeft = (size.width - paperWidth) / 2
        let paperTop = top + m.slotHeight * font / 2
        let textLeft = paperLeft + m.sidePad * m.advance * font
        let headerBottom = top + (m.slotHeight + headerRows) * font
        let room = top + length - m.toothDepth * font - m.bottomPad * font - headerBottom

        let rows = rows(room: room, font: font)
        let content = rows.reduce(0) { $0 + $1.height * fed($1) }
        let paperBottom = headerBottom + min(content, room) + m.bottomPad * font
        let paper = paperPath(left: paperLeft, top: paperTop, width: paperWidth, bottom: paperBottom, font: font)

        drawPaper(paper, left: paperLeft, width: paperWidth, top: paperTop, bottom: paperBottom, font: font, in: graphics)
        drawHeader(font: font, top: top, textLeft: textLeft, paperWidth: paperWidth, paperLeft: paperLeft, in: graphics)

        let lyricArea = CGRect(x: paperLeft, y: headerBottom, width: paperWidth, height: paperBottom + m.toothDepth * font - headerBottom)
        var cursor = headerBottom + min(content, room)
        graphics.drawLayer { layer in
            layer.clip(to: Path(lyricArea).intersection(paper))
            var cache = [String: GraphicsContext.ResolvedText]()
            for row in rows {
                let top = cursor - row.height * fed(row)
                cursor = top
                guard top + row.height > headerBottom else { break }
                if let wrappedRow = row.row {
                    drawLyricRow(line: row.line, row: wrappedRow, top: top, textLeft: textLeft, font: font, cache: &cache, in: layer)
                } else {
                    drawRule(feed: row.feed, top: top, height: row.height, textLeft: textLeft, font: font, in: layer)
                }
            }
            // Lines leaving under the header fade out instead of being cut through.
            let scroll = content - room
            if scroll > 0 {
                let fade = CGRect(x: paperLeft, y: headerBottom, width: paperWidth, height: m.rowHeight * font)
                layer.fill(Path(fade), with: .linearGradient(Gradient(colors: [TillPaint.paper.opacity(Double(min(1, scroll / fade.height))), TillPaint.paper.opacity(0)]),
                                                             startPoint: CGPoint(x: fade.midX, y: fade.minY), endPoint: CGPoint(x: fade.midX, y: fade.maxY)))
            }
        }
        drawSlot(font: font, top: top, paperLeft: paperLeft, paperWidth: paperWidth, in: graphics)
    }

    // MARK: Paper and slot

    /// Straight sides, the top hidden in the slot, and a torn zigzag along the bottom.
    private func paperPath(left: CGFloat, top: CGFloat, width: CGFloat, bottom: CGFloat, font: CGFloat) -> Path {
        let teeth = max(4, Int(width / (TillMetrics.toothWidth * font)))
        let tooth = width / CGFloat(teeth)
        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom))
        for index in 0..<teeth {
            let depth = TillMetrics.toothDepth * font * CGFloat(0.55 + 0.45 * seededUnit(Double(index), salt: 0x7EA2))
            path.addLine(to: CGPoint(x: left + (CGFloat(index) + 0.5) * tooth, y: bottom + depth))
            path.addLine(to: CGPoint(x: left + CGFloat(index + 1) * tooth, y: bottom))
        }
        path.addLine(to: CGPoint(x: left + width, y: top))
        path.closeSubpath()
        return path
    }

    private func drawPaper(_ paper: Path, left: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat, font: CGFloat,
                           in graphics: GraphicsContext) {
        // The curled bottom edge lifts off the screen and casts a wider, softer shadow than the sides.
        graphics.drawLayer { layer in
            let centre = CGPoint(x: left + width / 2, y: bottom + TillMetrics.toothDepth * font)
            layer.translateBy(x: centre.x, y: centre.y)
            layer.scaleBy(x: 1, y: 0.16)
            let radius = width * 0.52
            layer.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                       with: .radialGradient(Gradient(colors: [.black.opacity(0.32), .black.opacity(0)]), center: .zero,
                                             startRadius: 0, endRadius: radius))
        }
        graphics.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.4), radius: TillMetrics.shadowRadius * font, y: TillMetrics.shadowDrop * font))
            layer.fill(paper, with: .color(TillPaint.paper))
        }
        graphics.drawLayer { layer in
            layer.clip(to: paper)
            let curl = TillMetrics.curl * font, edge = bottom + TillMetrics.toothDepth * font
            layer.fill(Path(CGRect(x: left, y: edge - curl, width: width, height: curl)),
                       with: .linearGradient(Gradient(colors: [.black.opacity(0), .black.opacity(0.1)]),
                                             startPoint: CGPoint(x: 0, y: edge - curl), endPoint: CGPoint(x: 0, y: edge)))
            // Shade where the paper leaves the slot.
            let mouth = CGRect(x: left, y: top, width: width, height: font * 1.1)
            layer.fill(Path(mouth), with: .linearGradient(Gradient(colors: [.black.opacity(0.22), .black.opacity(0)]),
                                                          startPoint: CGPoint(x: 0, y: mouth.minY), endPoint: CGPoint(x: 0, y: mouth.maxY)))
        }
    }

    private func drawSlot(font: CGFloat, top: CGFloat, paperLeft: CGFloat, paperWidth: CGFloat, in graphics: GraphicsContext) {
        let overhang = TillMetrics.slotOverhang * font, height = TillMetrics.slotHeight * font
        let bar = CGRect(x: paperLeft - overhang, y: top, width: paperWidth + overhang * 2, height: height)
        let shape = Path(roundedRect: bar, cornerRadius: height / 2, style: .continuous)
        graphics.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: font * 0.4, y: font * 0.15))
            layer.fill(shape, with: .linearGradient(Gradient(colors: [TillPaint.slotTop, TillPaint.slotBottom]),
                                                    startPoint: CGPoint(x: 0, y: bar.minY), endPoint: CGPoint(x: 0, y: bar.maxY)))
        }
        graphics.stroke(shape, with: .color(.white.opacity(0.12)), lineWidth: 1)
        let slitHeight = TillMetrics.slitHeight * font
        let slit = CGRect(x: paperLeft - font * 0.15, y: bar.midY + height * 0.12, width: paperWidth + font * 0.3, height: slitHeight)
        graphics.fill(Path(roundedRect: slit, cornerRadius: slitHeight / 2), with: .color(.black))
        // A lamp in the user's highlight colour, brighter while a letter is printing.
        let printing = context.sung.contains { time < $0.end }
        let lamp = CGPoint(x: bar.maxX - height * 0.62, y: bar.minY + height * 0.36), radius = font * 0.11
        graphics.fill(Path(ellipseIn: CGRect(x: lamp.x - radius, y: lamp.y - radius, width: radius * 2, height: radius * 2)),
                      with: .color(Color(nsColor: context.settings.highlightColor).opacity(printing ? 1 : 0.45)))
    }

    // MARK: Header

    /// The header's height in font sizes: the till's name, the track when known, the line count and clock, a rule.
    private var headerRows: CGFloat {
        let m = TillMetrics.self
        return m.headerTop + m.titleRow + (context.trackTitle.isEmpty ? 0 : m.rowHeight) + m.rowHeight + m.headerRule
    }

    private func drawHeader(font: CGFloat, top: CGFloat, textLeft: CGFloat, paperWidth: CGFloat, paperLeft: CGFloat,
                            in graphics: GraphicsContext) {
        let m = TillMetrics.self
        let centreX = paperLeft + paperWidth / 2
        var y = top + m.slotHeight * font + m.headerTop * font
        let titleFont = Font.system(size: font * m.titleSize, weight: .heavy, design: .monospaced)
        graphics.draw(Text("STANZA — LYRICS").font(titleFont).foregroundStyle(TillPaint.ink), at: CGPoint(x: centreX, y: y), anchor: .top)
        y += m.titleRow * font
        let body = Font.system(size: font, weight: .medium, design: .monospaced)
        if !context.trackTitle.isEmpty {
            let title = context.trackTitle.uppercased()
            let fitted = title.count > m.columns ? String(title.prefix(m.columns - 1)) + "…" : title
            graphics.draw(Text(fitted).font(body).foregroundStyle(TillPaint.ink), at: CGPoint(x: centreX, y: y), anchor: .top)
            y += m.rowHeight * font
        }
        let faint = TillPaint.ink.opacity(m.faintInk)
        let count = context.lyrics.lines.count
        graphics.draw(Text("LINE \(context.line.index + 1)/\(count)").font(body).foregroundStyle(faint),
                      at: CGPoint(x: textLeft, y: y), anchor: .topLeading)
        graphics.draw(Text(Self.clock(time)).font(body).foregroundStyle(faint),
                      at: CGPoint(x: textLeft + CGFloat(m.columns) * m.advance * font, y: y), anchor: .topTrailing)
        y += m.rowHeight * font + m.headerRule * font * 0.4
        var rule = Path()
        rule.move(to: CGPoint(x: textLeft, y: y))
        rule.addLine(to: CGPoint(x: textLeft + CGFloat(m.columns) * m.advance * font, y: y))
        graphics.stroke(rule, with: .color(faint), style: StrokeStyle(lineWidth: max(1, font * 0.08), dash: [font * 0.38, font * 0.22]))
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Rows

    private func drawLyricRow(line index: Int, row: Int, top: CGFloat, textLeft: CGFloat, font: CGFloat,
                              cache: inout [String: GraphicsContext.ResolvedText], in graphics: GraphicsContext) {
        let m = TillMetrics.self
        let words = context.lyrics.lines[index]
        let wrapped = tillWrap(words, columns: m.textColumns)
        let placements = wrapped.placements.filter { $0.row == row }
        let body = Font.system(size: font, weight: .medium, design: .monospaced)
        let step = m.advance * font
        // The line's start time sits at the right of its first row, like a price.
        if row == 0 {
            graphics.draw(Text(Self.clock(words[0].start)).font(body).foregroundStyle(TillPaint.ink.opacity(m.faintInk)),
                          at: CGPoint(x: textLeft + CGFloat(m.columns) * step, y: top), anchor: .topTrailing)
        }
        guard index == context.line.index else {
            // Finished lines are drawn a row at a time, at the same advance as the letters printed one by one.
            var text = [String](repeating: " ", count: m.textColumns)
            for placement in placements {
                // The blanks after a whole joined word stay spaces, so later words keep their columns.
                for (offset, glyph) in placement.glyphs.enumerated() where !glyph.isEmpty { text[placement.column + offset] = glyph }
            }
            let string = text.joined().replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            graphics.draw(Text(string).font(body).foregroundStyle(TillPaint.ink.opacity(m.olderInk)),
                          at: CGPoint(x: textLeft, y: top), anchor: .topLeading)
            return
        }
        for placement in placements {
            let word = words[placement.word]
            let count = word.text.count
            let span = min(max(0, word.end - word.start), m.longestPrint)
            for (offset, glyph) in placement.glyphs.enumerated() where !glyph.trimmingCharacters(in: .whitespaces).isEmpty {
                let place = placement.offset + offset
                let printed = word.start + span * Double(place) / Double(max(1, count))
                let age = time - printed
                guard age >= 0 else { break }
                let text: GraphicsContext.ResolvedText
                if let cached = cache[glyph] {
                    text = cached
                } else {
                    text = graphics.resolve(Text(glyph).font(body).foregroundStyle(TillPaint.ink))
                    cache[glyph] = text
                }
                var point = CGPoint(x: textLeft + CGFloat(placement.column + offset) * step, y: top)
                var layer = graphics
                // A just-printed letter lands with a tiny wobble of the print head and darkens as the ink takes.
                if age < m.fresh && !context.settings.reduceMotion {
                    let settle = CGFloat(1 - age / m.fresh)
                    let salt = UInt64(index) &* 0x10001 &+ UInt64(placement.word) &* 0x101 &+ UInt64(place)
                    point.x += (CGFloat(seededUnit(word.start, salt: salt)) - 0.5) * m.jitterX * font * settle
                    point.y += (CGFloat(seededUnit(word.start, salt: salt ^ 0xB0B)) - 0.5) * m.jitterY * font * settle
                    layer.opacity = m.freshInk + (1 - m.freshInk) * min(1, age / m.inkUp)
                }
                layer.draw(text, at: point, anchor: .topLeading)
            }
        }
    }

    /// A row of dots printed left to right once a line is finished.
    private func drawRule(feed: Double, top: CGFloat, height: CGFloat, textLeft: CGFloat, font: CGFloat, in graphics: GraphicsContext) {
        let m = TillMetrics.self
        let dots = m.columns / 2
        let drawn = context.settings.reduceMotion ? dots : Int((Double(dots) * min(1, (time - feed) / m.ruleDraw)).rounded(.up))
        let step = m.advance * font * 2, radius = m.dotRadius * font
        var path = Path()
        for index in 0..<min(dots, drawn) {
            let centre = CGPoint(x: textLeft + step * (CGFloat(index) + 0.25), y: top + height * 0.45)
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }
        graphics.fill(path, with: .color(TillPaint.ink.opacity(m.faintInk)))
    }
}
