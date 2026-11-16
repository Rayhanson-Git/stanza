import SwiftUI

/// Departure Board: the lyrics on a dark split-flap board. The line being sung fills the bottom rows and earlier lines
/// sit dimmer above it. When a word arrives its tiles flip through a few letters and settle on it; when a new line
/// starts the whole board ripples over. Each frame is worked out from the playback position alone: a flip is found by
/// comparing the board just before and just after each recent change, so there is no view state.
struct DepartureBoardStyle: View {
    let context: StyleContext

    var body: some View {
        let board = FlapBoard(context: context)
        // As tall as the screen and centred on the band, so a large Size is never cut off by the band.
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, size in
            board.draw(in: graphics, size: size)
        }
        .frame(width: context.canvas.width, height: context.canvas.height)
        .opacity(board.opacity)
    }
}

private enum FlapMetrics {
    static let columns = 22, rows = 5, maxCurrentRows = 3, departedLines = 2
    /// At Size 100% the board is half the canvas wide, and never taller than this share of it.
    static let widthShare: CGFloat = 0.5, heightShare: CGFloat = 0.45
    // Lengths in cell pitches (one tile plus the gap beside it).
    static let tileWidth: CGFloat = 0.9, tileHeight: CGFloat = 1.42, rowGap: CGFloat = 0.14
    static let sidePad: CGFloat = 0.75, topPad: CGFloat = 0.42, headerHeight: CGFloat = 1.0, bottomPad: CGFloat = 0.75
    static let tileRadius: CGFloat = 0.1, housingRadius: CGFloat = 0.42
    static let glyphSize: CGFloat = 1.24, headerSize: CGFloat = 0.46, headerTracking: CGFloat = 0.12
    static let hinge: CGFloat = 0.045, ledRadius: CGFloat = 0.13, markerWidth: CGFloat = 0.13
    static let shadowRadius: CGFloat = 0.9, shadowDrop: CGFloat = 0.3
    static let lowerHalfShade = 0.2, departedInk = 0.46, headerInk = 0.62, flapShade = 0.55, flapWiden: CGFloat = 0.06
    // Timing, in seconds. A word's last tile settles at most `maxDelay + delayJitter + step * 4` (0.30 s) after it starts.
    static let step = 0.04, perCellDelay = 0.018, maxDelay = 0.12, delayJitter = 0.02, maxSpins = 3
    static let window = maxDelay + delayJitter + step * Double(maxSpins + 1)
    static let fadeIn = 0.2
    static let before = 1e-6
    static let spinGlyphs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map(String.init)
}

private enum FlapSalt {
    static let delay: UInt64 = 0xF1A9, spins: UInt64 = 0x5917, glyph: UInt64 = 0x6E7F
}

private enum FlapTone: Hashable { case departed, current, singing }

private struct FlapCell {
    /// One letter, or a whole word in a script whose letters join (it spans the tiles after it, which stay blank).
    let glyph: String
    let tone: FlapTone
}

/// One word, or one row-wide piece of a word too long for a row, placed on the grid.
private struct FlapPlacement {
    let word: Int, row: Int, column: Int
    let glyphs: [String]
}

/// A tile turning from one glyph to another through a few random ones.
private struct FlapFlip {
    let from: FlapCell?, to: FlapCell?
    let begin: Double
    let spins: [FlapCell]

    /// The pair of faces being flipped between and how far the flap has turned, or nil once it has settled.
    func state(at time: Double) -> FlapState? {
        let local = time - begin
        let steps = spins.count + 1
        guard local >= 0 else { return FlapState(from: from, to: from, progress: 0) }
        let index = Int(local / FlapMetrics.step)
        guard index < steps else { return nil }
        let start = index == 0 ? from : spins[index - 1]
        let end = index + 1 == steps ? to : spins[index]
        return FlapState(from: start, to: end, progress: local / FlapMetrics.step - Double(index))
    }
}

private struct FlapState {
    let from: FlapCell?, to: FlapCell?
    let progress: Double
}

/// How many tiles a whole word covers in the board's glyph font (one tile pitch is 1 / glyphSize of the font size).
/// Measured once per word: the board is laid out on every frame.
@MainActor private var flapSpans: [String: Int] = [:]

private func flapSpan(of word: String) -> Int {
    if let known = MainActor.assumeIsolated({ flapSpans[word] }) { return known }
    let size: CGFloat = 100
    let font = NSFont.systemFont(ofSize: size * FlapMetrics.glyphSize, weight: .bold, width: .condensed)
    let width = NSAttributedString(string: word, attributes: [.font: font]).size().width
    let span = max(1, Int((width / size).rounded(.up)))
    MainActor.assumeIsolated {
        if flapSpans.count > 512 { flapSpans.removeAll() }
        flapSpans[word] = span
    }
    return span
}

/// Greedy word wrap onto rows of `columns` tiles; a word longer than a row is broken across rows.
private func flapWrap(_ words: [TimedWord], columns: Int) -> (placements: [FlapPlacement], rows: Int) {
    var placements = [FlapPlacement](), row = 0, column = 0
    for (index, word) in words.enumerated() {
        // Joined scripts keep the word whole in its first tile and leave blank as many tiles as it really covers.
        let glyphs: [String] = LyricsScript.joinsLetters(word.text)
            ? [word.text] + Array(repeating: "", count: flapSpan(of: word.text) - 1)
            : word.text.uppercased().map(String.init)
        var start = 0
        while start < glyphs.count {
            let chunk = Array(glyphs[start..<min(start + columns, glyphs.count)])
            if column > 0 && column + 1 + chunk.count > columns {
                row += 1
                column = 0
            } else if column > 0 {
                column += 1
            }
            placements.append(FlapPlacement(word: index, row: row, column: column, glyphs: chunk))
            column += chunk.count
            start += chunk.count
        }
    }
    return (placements, row + 1)
}

private struct FlapBoard {
    let context: StyleContext
    let cells: [FlapCell?]
    let flips: [Int: FlapFlip]
    /// The grid rows the line being sung takes up.
    let currentRows: Range<Int>
    let opacity: Double

    init(context: StyleContext) {
        self.context = context
        let lines = context.lyrics.lines, index = context.line.index, time = context.position
        let lineStart = lines[index][0].start
        // The board stays up through gaps, so every line after the first flips over the one before it.
        let previousShowing = index > 0
        let now = Self.grid(lines, line: index, at: time)
        cells = now.cells
        currentRows = now.current

        var flips = [Int: FlapFlip]()
        if !context.settings.reduceMotion {
            // Every change in the last few tenths of a second, oldest first so a newer flip of the same tile wins.
            let changes = Set(lines[index].map(\.start).filter { $0 <= time && $0 > time - FlapMetrics.window }).sorted()
            for change in changes {
                let before: [FlapCell?]
                if change == lineStart {
                    before = previousShowing ? Self.grid(lines, line: index - 1, at: change - FlapMetrics.before).cells
                                             : Array(repeating: nil, count: FlapMetrics.rows * FlapMetrics.columns)
                } else {
                    before = Self.grid(lines, line: index, at: change - FlapMetrics.before).cells
                }
                let after = Self.grid(lines, line: index, at: change).cells
                // A whole joined word does not spin through letters; it simply appears.
                let changed = after.indices.filter {
                    before[$0]?.glyph != after[$0]?.glyph && (after[$0]?.glyph.count ?? 0) <= 1 && (before[$0]?.glyph.count ?? 0) <= 1
                }
                let firstColumn = changed.map { $0 % FlapMetrics.columns }.min() ?? 0
                for cell in changed {
                    flips[cell] = Self.flip(cell: cell, line: index, change: change, firstColumn: firstColumn,
                                            from: before[cell], to: after[cell])
                }
            }
        }
        self.flips = flips

        let appear = previousShowing ? 1 : min(1, max(0, (time - lineStart) / FlapMetrics.fadeIn))
        opacity = min(appear, context.gapPresence)
    }

    // MARK: The board's contents

    /// What the board shows at `time` while `line` is the line being sung.
    private static func grid(_ lines: [[TimedWord]], line index: Int, at time: Double) -> (cells: [FlapCell?], current: Range<Int>) {
        let columns = FlapMetrics.columns
        var cells = [FlapCell?](repeating: nil, count: FlapMetrics.rows * columns)
        let words = lines[index]
        let wrapped = flapWrap(words, columns: columns)
        let visible = min(wrapped.rows, FlapMetrics.maxCurrentRows)
        let started = words.prefix { $0.start <= time }.count
        // A line too long for its rows scrolls up a row at a time, keeping the newest word in view.
        let newestRow = wrapped.placements.last { $0.word < started }?.row ?? 0
        let firstRow = min(max(0, newestRow - visible + 1), wrapped.rows - visible)
        let top = FlapMetrics.rows - visible
        for placement in wrapped.placements where placement.word < started && placement.row >= firstRow && placement.row < firstRow + visible {
            let word = words[placement.word]
            let tone: FlapTone = placement.word == started - 1 && time < word.end ? .singing : .current
            put(placement, row: top + placement.row - firstRow, tone: tone, into: &cells)
        }
        // Up to two earlier lines, whole, sit in the rows above, the most recent lowest. Only the most recent may
        // lose its opening rows, when it is too long to fit at all.
        var free = top, earlier = index - 1, departed = 0
        while free > 0 && earlier >= 0 && departed < FlapMetrics.departedLines {
            let past = flapWrap(lines[earlier], columns: columns)
            guard past.rows <= free || departed == 0 else { break }
            let shift = free - past.rows
            for placement in past.placements where placement.row + shift >= 0 {
                put(placement, row: placement.row + shift, tone: .departed, into: &cells)
            }
            free = max(0, shift)
            departed += 1
            earlier -= 1
        }
        return (cells, top..<FlapMetrics.rows)
    }

    private static func put(_ placement: FlapPlacement, row: Int, tone: FlapTone, into cells: inout [FlapCell?]) {
        for (offset, glyph) in placement.glyphs.enumerated() where !glyph.trimmingCharacters(in: .whitespaces).isEmpty {
            cells[row * FlapMetrics.columns + placement.column + offset] = FlapCell(glyph: glyph, tone: tone)
        }
    }

    /// Tiles ripple left to right; one turning to a letter spins through one to three others first, one clearing just drops.
    private static func flip(cell: Int, line: Int, change: Double, firstColumn: Int, from: FlapCell?, to: FlapCell?) -> FlapFlip {
        let salt = UInt64(cell) &* 0x9E37 &+ UInt64(line) &* 0x1F3D
        let column = cell % FlapMetrics.columns
        let delay = min(FlapMetrics.maxDelay, FlapMetrics.perCellDelay * Double(column - firstColumn))
            + FlapMetrics.delayJitter * seededUnit(change, salt: salt ^ FlapSalt.delay)
        let count = to == nil ? 0 : 1 + Int(seededUnit(change, salt: salt ^ FlapSalt.spins) * Double(FlapMetrics.maxSpins))
        let spins = (0..<count).map { step -> FlapCell in
            let pick = seededUnit(change, salt: salt &+ UInt64(step + 1) &* 0x2545 ^ FlapSalt.glyph)
            return FlapCell(glyph: FlapMetrics.spinGlyphs[Int(pick * Double(FlapMetrics.spinGlyphs.count))], tone: to?.tone ?? .current)
        }
        return FlapFlip(from: from, to: to, begin: change + delay, spins: spins)
    }

    // MARK: Drawing

    func draw(in graphics: GraphicsContext, size: CGSize) {
        let geometry = FlapGeometry(canvas: size, scale: context.scale)
        guard geometry.unit > 0 else { return }
        var glyphs = FlapGlyphs(unit: geometry.unit, graphics: graphics)
        drawHousing(geometry, in: graphics)
        drawHeader(geometry, in: graphics)

        let time = context.position
        // A tile still waiting for the ripple to reach it rests on its old face and is drawn with the others.
        var shown = cells, moving = [Int: FlapState]()
        for (cell, flip) in flips {
            guard let state = flip.state(at: time) else { continue }
            if time < flip.begin { shown[cell] = flip.from } else { moving[cell] = state }
        }
        // Resting tiles share one path per shade, so the whole board costs a handful of fills.
        var tiles = Path(), lowerHalves = Path(), hinges = Path(), highlights = Path()
        for cell in 0..<cells.count {
            let tile = geometry.tile(cell)
            let hingeY = tile.midY - geometry.unit * FlapMetrics.hinge / 2
            hinges.addRect(CGRect(x: tile.minX, y: hingeY, width: tile.width, height: geometry.unit * FlapMetrics.hinge))
            highlights.addRect(CGRect(x: tile.minX, y: hingeY + geometry.unit * FlapMetrics.hinge, width: tile.width, height: 1))
            guard moving[cell] == nil else { continue }
            tiles.addRoundedRect(in: tile, cornerSize: geometry.tileCorner)
            lowerHalves.addRect(CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2))
        }
        graphics.fill(tiles, with: .color(FlapPaint.tile))
        graphics.drawLayer { layer in
            layer.clip(to: tiles)
            layer.fill(lowerHalves, with: .color(.black.opacity(FlapMetrics.lowerHalfShade)))
        }
        for cell in 0..<cells.count where moving[cell] == nil {
            guard let content = shown[cell] else { continue }
            let tile = geometry.tile(cell)
            let text = glyphs.text(content.glyph, tone: content.tone)
            if content.glyph.count > 1 {
                graphics.draw(text, at: CGPoint(x: tile.minX, y: tile.midY), anchor: .leading)
            } else {
                graphics.draw(text, at: CGPoint(x: tile.midX, y: tile.midY))
            }
        }
        for (cell, state) in moving {
            drawFlip(state, tile: geometry.tile(cell), geometry: geometry, glyphs: &glyphs, in: graphics)
        }
        graphics.fill(hinges, with: .color(FlapPaint.hinge))
        graphics.fill(highlights, with: .color(.white.opacity(0.05)))
        drawMarker(geometry, in: graphics)
    }

    private func drawHousing(_ geometry: FlapGeometry, in graphics: GraphicsContext) {
        let unit = geometry.unit, rect = geometry.board
        let housing = Path(roundedRect: rect, cornerRadius: unit * FlapMetrics.housingRadius, style: .continuous)
        graphics.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.55), radius: unit * FlapMetrics.shadowRadius, y: unit * FlapMetrics.shadowDrop))
            layer.fill(housing, with: .linearGradient(Gradient(colors: [FlapPaint.housingTop, FlapPaint.housingBottom]),
                                                      startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                      endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
        graphics.stroke(housing, with: .color(.white.opacity(0.09)), lineWidth: 1)
        // Four small screws hold the board in its frame.
        let inset = unit * FlapMetrics.sidePad / 2, radius = unit * 0.07
        for corner in [CGPoint(x: rect.minX + inset, y: rect.minY + inset), CGPoint(x: rect.maxX - inset, y: rect.minY + inset),
                       CGPoint(x: rect.minX + inset, y: rect.maxY - inset), CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)] {
            graphics.fill(Path(ellipseIn: CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)),
                          with: .color(.white.opacity(0.16)))
        }
    }

    private func drawHeader(_ geometry: FlapGeometry, in graphics: GraphicsContext) {
        let unit = geometry.unit
        let font = Font.system(size: unit * FlapMetrics.headerSize, weight: .bold).width(.condensed)
        let ink = FlapPaint.amber.opacity(FlapMetrics.headerInk)
        let midY = geometry.headerMidY
        let singing = cells.contains { $0?.tone == .singing }
        // A lamp in the user's highlight colour, lit while a word is being sung.
        let lamp = CGPoint(x: geometry.gridLeft + unit * FlapMetrics.ledRadius, y: midY)
        let radius = unit * FlapMetrics.ledRadius
        if singing {
            graphics.fill(Path(ellipseIn: CGRect(x: lamp.x - radius * 2.2, y: lamp.y - radius * 2.2, width: radius * 4.4, height: radius * 4.4)),
                          with: .radialGradient(Gradient(colors: [FlapPaint.accent(context).opacity(0.45), .clear]),
                                                center: lamp, startRadius: 0, endRadius: radius * 2.2))
        }
        graphics.fill(Path(ellipseIn: CGRect(x: lamp.x - radius, y: lamp.y - radius, width: radius * 2, height: radius * 2)),
                      with: .color(FlapPaint.accent(context).opacity(singing ? 1 : 0.35)))
        let title = Text("DEPARTURES").font(font).tracking(unit * FlapMetrics.headerTracking).foregroundStyle(ink)
        graphics.draw(title, at: CGPoint(x: lamp.x + radius * 2.4, y: midY), anchor: .leading)
        let seconds = max(0, Int(context.position))
        let clock = Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
            .font(font.monospacedDigit()).tracking(unit * FlapMetrics.headerTracking).foregroundStyle(ink)
        graphics.draw(clock, at: CGPoint(x: geometry.gridRight, y: midY), anchor: .trailing)
    }

    /// A slim bar in the highlight colour beside the rows of the line being sung.
    private func drawMarker(_ geometry: FlapGeometry, in graphics: GraphicsContext) {
        let top = geometry.tile(currentRows.lowerBound * FlapMetrics.columns).minY
        let bottom = geometry.tile((currentRows.upperBound - 1) * FlapMetrics.columns).maxY
        let width = geometry.unit * FlapMetrics.markerWidth
        let bar = CGRect(x: geometry.gridLeft - geometry.unit * FlapMetrics.sidePad / 2 - width / 2, y: top, width: width, height: bottom - top)
        graphics.fill(Path(roundedRect: bar, cornerRadius: width / 2), with: .color(FlapPaint.accent(context)))
    }

    /// The top half of the new glyph is revealed behind a falling flap: first the old top half folds down onto the
    /// hinge, then the new bottom half unfolds from it over the old bottom half.
    private func drawFlip(_ state: FlapState, tile: CGRect, geometry: FlapGeometry, glyphs: inout FlapGlyphs, in graphics: GraphicsContext) {
        let corner = geometry.tileCorner
        let shape = Path(roundedRect: tile, cornerSize: corner)
        let upper = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height / 2)
        let lower = CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2)
        let fromText = state.from.map { glyphs.text($0.glyph, tone: $0.tone) }
        let toText = state.to.map { glyphs.text($0.glyph, tone: $0.tone) }
        let centre = CGPoint(x: tile.midX, y: tile.midY)

        func half(_ rect: CGRect, text: GraphicsContext.ResolvedText?, fold: CGFloat, widen: CGFloat, shade: Double) {
            guard fold > 0.02 else { return }
            graphics.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.scaleBy(x: 1 + widen, y: fold)
                layer.translateBy(x: -centre.x, y: -centre.y)
                layer.clip(to: Path(rect))
                layer.fill(shape, with: .color(FlapPaint.tile))
                if rect.minY >= tile.midY { layer.fill(Path(rect), with: .color(.black.opacity(FlapMetrics.lowerHalfShade))) }
                if let text { layer.draw(text, at: centre) }
                if shade > 0 { layer.fill(Path(rect), with: .color(.black.opacity(shade))) }
            }
        }

        let turn = state.progress * .pi
        let lean = CGFloat(sin(turn)) * FlapMetrics.flapWiden
        half(upper, text: toText, fold: 1, widen: 0, shade: 0)
        half(lower, text: fromText, fold: 1, widen: 0, shade: 0)
        if state.progress < 0.5 {
            half(upper, text: fromText, fold: CGFloat(cos(turn)), widen: lean, shade: FlapMetrics.flapShade * state.progress * 2)
        } else {
            half(lower, text: toText, fold: CGFloat(-cos(turn)), widen: lean, shade: FlapMetrics.flapShade * (1 - state.progress) * 2)
        }
    }
}

private struct FlapGeometry {
    let unit: CGFloat
    let board: CGRect

    init(canvas: CGSize, scale: Double) {
        let m = FlapMetrics.self
        let widthUnits = CGFloat(m.columns) - (1 - m.tileWidth) + 2 * m.sidePad
        let heightUnits = m.topPad + m.headerHeight + CGFloat(m.rows) * m.tileHeight + CGFloat(m.rows - 1) * m.rowGap + m.bottomPad
        unit = min(canvas.width * m.widthShare / widthUnits, canvas.height * m.heightShare / heightUnits) * CGFloat(scale)
        let size = CGSize(width: widthUnits * unit, height: heightUnits * unit)
        board = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width, height: size.height)
    }

    var gridLeft: CGFloat { board.minX + unit * FlapMetrics.sidePad }
    var gridRight: CGFloat { board.maxX - unit * FlapMetrics.sidePad }
    var gridTop: CGFloat { board.minY + unit * (FlapMetrics.topPad + FlapMetrics.headerHeight) }
    var headerMidY: CGFloat { board.minY + unit * (FlapMetrics.topPad + FlapMetrics.headerHeight / 2) }
    var tileCorner: CGSize { CGSize(width: unit * FlapMetrics.tileRadius, height: unit * FlapMetrics.tileRadius) }

    func tile(_ cell: Int) -> CGRect {
        let row = cell / FlapMetrics.columns, column = cell % FlapMetrics.columns
        return CGRect(x: gridLeft + CGFloat(column) * unit,
                      y: gridTop + CGFloat(row) * unit * (FlapMetrics.tileHeight + FlapMetrics.rowGap),
                      width: unit * FlapMetrics.tileWidth, height: unit * FlapMetrics.tileHeight)
    }
}

/// Glyphs resolved once per frame for each letter and tone.
private struct FlapGlyphs {
    let font: Font
    let graphics: GraphicsContext
    var resolved: [String: GraphicsContext.ResolvedText] = [:]

    init(unit: CGFloat, graphics: GraphicsContext) {
        font = Font.system(size: unit * FlapMetrics.glyphSize, weight: .bold).width(.condensed)
        self.graphics = graphics
    }

    mutating func text(_ glyph: String, tone: FlapTone) -> GraphicsContext.ResolvedText {
        let key = "\(tone)\(glyph)"
        if let text = resolved[key] { return text }
        let ink: Color
        switch tone {
        case .departed: ink = FlapPaint.amber.opacity(FlapMetrics.departedInk)
        case .current: ink = FlapPaint.amber
        case .singing: ink = FlapPaint.hot
        }
        let text = graphics.resolve(Text(glyph).font(font).foregroundStyle(ink))
        resolved[key] = text
        return text
    }
}

/// The board brings its own colours so it reads the same over any wallpaper; only its lamp and marker follow the user.
private enum FlapPaint {
    static let tile = Color(red: 0.115, green: 0.115, blue: 0.125)
    static let hinge = Color.black.opacity(0.85)
    static let housingTop = Color(red: 0.075, green: 0.075, blue: 0.08), housingBottom = Color(red: 0.035, green: 0.035, blue: 0.04)
    static let amber = Color(red: 1, green: 0.72, blue: 0.26)
    static let hot = Color(red: 1, green: 0.9, blue: 0.68)

    static func accent(_ context: StyleContext) -> Color { Color(nsColor: context.settings.highlightColor) }
}
