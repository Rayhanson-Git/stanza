import SwiftUI

/// Liquid: the line is set centred in up to three rows. Each word flows out of the word before it as a thread of
/// goo that pools into soft, blobby letters and firms up into crisp type as it is sung. When the line is done it sags,
/// drips and drains away. The goo is metaballs: shapes blurred together on a layer and cut at an alpha threshold.
/// Everything is a closed-form function of the song position, so no SwiftUI state is needed.
struct LiquidStyle: View {
    let context: StyleContext

    var body: some View {
        let scene = LiquidScene(context: context)
        // The blurred layers cost by area, so the canvas only covers the text block and the room its drips need.
        Canvas { graphics, _ in scene.draw(in: &graphics) }
            .frame(width: scene.frame.width, height: scene.frame.height)
            .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
            .position(x: scene.frame.midX, y: scene.frame.midY)
            .frame(width: context.canvas.width, height: context.band)
    }
}

private enum Metrics {
    // Type (fractions of the screen) and rows
    static let fontSize = 0.088, rowWidth = 0.5, widestRow = 0.92, lineHeight = 1.2, maxRows = 3
    static let maxBlock = 0.9, measuringSize = 100.0, shrinkStep = 0.9, shrinkTries = 14, balanceStep = 1.03
    static let margin = 0.7, dripRoom = 2.4                     // of the font size, around and below the block

    // Goo (of the font size)
    static let blur = 0.05, threshold = 0.5, dilation = 0.018   // the text is drawn thickened so thin strokes survive
    static let gooOpacity = 0.92

    // Flowing in
    static let longestFlow = 0.42, shortestFlow = 0.12, flowShare = 0.85   // seconds, and share of the gap before a word
    static let firstFlow = 0.24, firstFirm = 0.14, firmTime = 0.2
    static let threadRadius = 0.17, frontRadius = 0.2, swellRadius = 0.3, beadSpacing = 0.6

    // Melting
    static let meltTime = 0.7, shortestMelt = 0.25, vanishMargin = 0.03, crispHandover = 0.3
    static let sag = 0.35, droop = 0.35, thinning = 0.45, thinFrom = 0.3, swellBy = 0.5, drainFrom = 0.6
    static let dripFall = 2.0, dripTop = 0.22, dripRadius = 0.09, dripRadiusSpread = 0.06, dripDelay = 0.3
    static let maxDrips = 2, dripSpan = 0.7, neckBreak = 0.6

    static let threadSag = 0.2, threadNeck = 0.3, sourceInset = 0.08, sourceDrop = 0.12

    static let shadowOpacity = 0.5, shadowRadius = 12.0, shadowY = 3.0
}

private enum Salt {
    static let drips: UInt64 = 0x11C0, place: UInt64 = 0x11C1, size: UInt64 = 0x11C2, delay: UInt64 = 0x11C3
    static let stride: UInt64 = 0x100
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
private func smooth(_ value: Double) -> Double { let x = unit(value); return x * x * (3 - 2 * x) }
private func easeOut(_ value: Double) -> Double { let x = unit(value); return 1 - (1 - x) * (1 - x) }

private func disc(_ centre: CGPoint, radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
}

/// Where one word sits and when it flows in. Positions are in the band's coordinates.
private struct Drop {
    let word: TimedWord
    let rect: CGRect
    /// The previous word's trailing edge, where this one flows out of; nil for a word that begins a row, which swells in place.
    let source: CGPoint?
    let flowStart: Double
    /// When it starts turning into crisp text: its sung time, a little later for a first word that only begins to swell then.
    let firmStart: Double
}

private struct LiquidScene {
    let context: StyleContext
    let fontSize: Double
    let drops: [Drop]
    /// The canvas, in the band's coordinates.
    let frame: CGRect
    let meltStart: Double, meltEnd: Double

    init(context: StyleContext) {
        self.context = context
        let words = context.line.words
        let canvas = context.canvas
        func widths(at size: Double) -> [Double] {
            let font = context.settings.font.font(size: size)
            return words.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }
        }
        let reference = widths(at: Metrics.measuringSize)
        let referenceSpace = (" " as NSString).size(withAttributes: [.font: context.settings.font.font(size: Metrics.measuringSize)]).width
        let limit = min(canvas.width * Metrics.rowWidth * context.scale, canvas.width * Metrics.widestRow)
        var size = canvas.height * Metrics.fontSize * context.scale
        var rows = [0..<words.count]
        for _ in 0..<Metrics.shrinkTries {
            let ratio = size / Metrics.measuringSize
            if let fitted = balancedRows(reference.map { $0 * ratio }, space: referenceSpace * ratio, limit: limit),
               Double(fitted.count) * size * Metrics.lineHeight <= context.band * Metrics.maxBlock {
                rows = fitted
                break
            }
            size *= Metrics.shrinkStep
        }
        fontSize = size

        let measured = widths(at: size)
        let space = (" " as NSString).size(withAttributes: [.font: context.settings.font.font(size: size)]).width
        let lineHeight = size * Metrics.lineHeight
        let top = context.band / 2 - lineHeight * Double(rows.count) / 2
        var rects = [CGRect](repeating: .zero, count: words.count)
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = row.reduce(0) { $0 + measured[$1] } + space * Double(row.count - 1)
            var x = canvas.width / 2 - rowWidth / 2
            for index in row {
                rects[index] = CGRect(x: x, y: top + lineHeight * Double(rowIndex), width: measured[index], height: lineHeight)
                x += measured[index] + space
            }
        }
        let rowStarts = Set(rows.map(\.lowerBound))
        drops = words.indices.map { index in
            let word = words[index]
            guard index > 0 else {
                return Drop(word: word, rect: rects[0], source: nil, flowStart: word.start, firmStart: word.start + Metrics.firstFirm)
            }
            let gap = word.start - words[index - 1].start
            let flow = min(Metrics.longestFlow, max(Metrics.shortestFlow, gap * Metrics.flowShare))
            let before = rects[index - 1]
            return Drop(word: word, rect: rects[index], source: rowStarts.contains(index) ? nil : CGPoint(x: before.maxX - size * Metrics.sourceInset, y: before.midY + size * Metrics.sourceDrop),
                        flowStart: word.start - min(flow, max(0, gap)), firmStart: word.start)
        }

        let block = rects.reduce(rects.first ?? .zero) { $0.union($1) }
        let margin = size * Metrics.margin
        frame = CGRect(x: block.minX - margin, y: block.minY - margin,
                       width: block.width + 2 * margin, height: block.height + margin + size * Metrics.dripRoom)

        // The line is gone at the earlier of its linger running out and the next line starting; the melt must be over by then.
        let nextStart = context.line.index + 1 < context.lyrics.lines.count ? context.lyrics.lines[context.line.index + 1][0].start : .infinity
        let vanish = min((words.last?.end ?? 0) + Timing.lineLinger, nextStart) - Metrics.vanishMargin
        // Never before the last word has been sung and has firmed; with too little room left there is no melt at all.
        let firmed = max((drops.last?.firmStart ?? 0) + Metrics.firmTime, words.last?.end ?? 0)
        let start = max(firmed, vanish - Metrics.meltTime)
        (meltStart, meltEnd) = vanish - start >= Metrics.shortestMelt ? (start, vanish) : (.infinity, .infinity)
    }

    private var melt: Double { unit((context.position - meltStart) / (meltEnd - meltStart)) }

    // MARK: Drawing

    func draw(in graphics: inout GraphicsContext) {
        graphics.translateBy(x: -frame.minX, y: -frame.minY)
        let time = context.position, melt = melt, motion = !context.settings.reduceMotion
        let font = context.font(fontSize)
        let settings = context.settings
        let text = Color(nsColor: settings.textColor)

        let flowing = drops.filter { time >= $0.flowStart && time < $0.firmStart + Metrics.firmTime }
        if !flowing.isEmpty {
            goo(in: graphics, color: Color(nsColor: settings.highlightColor).opacity(Metrics.gooOpacity)) { layer in
                for drop in flowing { flow(drop, at: time, font: font, motion: motion, in: &layer) }
            }
        }
        if melt > 0, motion {
            var draining = graphics
            draining.opacity = 1 - smooth((melt - Metrics.drainFrom) / (1 - Metrics.drainFrom))
            goo(in: draining, color: text) { layer in
                for (index, drop) in drops.enumerated() where time >= drop.firmStart { sag(drop, index: index, melt: melt, font: font, in: &layer) }
            }
        }

        let crisp = 1 - smooth(melt / (motion ? Metrics.crispHandover : 1))
        guard crisp > 0 else { return }
        for drop in drops where time >= drop.firmStart {
            var word = graphics
            // Crisp well before the goo has drained, so the goo is seen shrinking into solid letters rather than a fade.
            word.opacity = crisp * smooth(2 * (time - drop.firmStart) / Metrics.firmTime)
            word.draw(word.resolve(Text(drop.word.text).font(font).foregroundStyle(text)), at: CGPoint(x: drop.rect.minX, y: drop.rect.midY),
                      anchor: .leading)
        }
    }

    /// Draws `shapes` onto a layer that is blurred and then cut at an alpha threshold, so that touching shapes merge.
    private func goo(in graphics: GraphicsContext, color: Color, shapes: (inout GraphicsContext) -> Void) {
        var goo = graphics
        goo.addFilter(.alphaThreshold(min: Metrics.threshold, color: color))
        goo.addFilter(.blur(radius: fontSize * Metrics.blur))
        goo.drawLayer { layer in shapes(&layer) }
    }

    /// The word's text, thickened by drawing it a few times around its place (`swell` of the full amount).
    private func thickText(_ text: GraphicsContext.ResolvedText, at point: CGPoint, swell: Double = 1, in layer: GraphicsContext) {
        let reach = fontSize * Metrics.dilation * swell
        for (dx, dy) in [(0.0, 0.0), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
            layer.draw(text, at: CGPoint(x: point.x + dx * reach, y: point.y + dy * reach), anchor: .leading)
        }
    }

    /// A word on its way in: a thread pulled from the word before it, whose bulging front spreads along the new word and
    /// leaves soft letters behind; they shrink into the crisp text as it firms.
    private func flow(_ drop: Drop, at time: Double, font: Font, motion: Bool, in layer: inout GraphicsContext) {
        let rect = drop.rect, solid = Color.white
        let span = drop.source == nil ? Metrics.firstFlow : max(0.01, drop.firmStart - drop.flowStart)
        let progress = unit((time - drop.flowStart) / span)
        let firming = smooth((time - drop.firmStart) / Metrics.firmTime)
        let spread = easeOut(progress)

        var letters = layer
        letters.opacity = 1 - firming
        if let source = drop.source, motion {
            // The front runs from the previous word's edge to the end of this one, leaving the letters behind it.
            let front = CGPoint(x: rect.minX + rect.width * spread, y: rect.midY)
            letters.clip(to: Path(CGRect(x: rect.minX - fontSize, y: rect.minY - fontSize, width: rect.width * spread + fontSize,
                                         height: rect.height + 2 * fontSize)))
            let pinch = sqrt(1 - smooth(progress))
            thread(from: source, to: CGPoint(x: rect.minX + fontSize * Metrics.sourceInset, y: rect.midY + fontSize * Metrics.sourceDrop), radius: fontSize * Metrics.threadRadius * pinch, in: layer)
            layer.fill(disc(front, radius: fontSize * Metrics.frontRadius * sqrt(1 - progress)), with: .color(solid))
        } else {
            // A word that begins a row (or any word, with Reduce Motion) swells up in place from its middle.
            letters.clip(to: Path(CGRect(x: rect.midX - rect.width * spread / 2 - fontSize, y: rect.minY - fontSize,
                                         width: rect.width * spread + 2 * fontSize, height: rect.height + 2 * fontSize)))
            if motion {
                layer.fill(disc(CGPoint(x: rect.midX, y: rect.midY), radius: fontSize * Metrics.swellRadius * sin(.pi * progress)),
                           with: .color(solid))
            }
        }
        thickText(letters.resolve(Text(drop.word.text).font(font).foregroundStyle(solid)), at: CGPoint(x: rect.minX, y: rect.midY), in: letters)
    }

    /// A string of beads from `start` to `end`; on the threshold layer they read as one stretched thread that sags
    /// and narrows in the middle, as a pulled strand of liquid does.
    private func thread(from start: CGPoint, to end: CGPoint, radius: Double, in layer: GraphicsContext) {
        guard radius > 0.5 else { return }
        let beads = max(2, Int(hypot(end.x - start.x, end.y - start.y) / (radius * Metrics.beadSpacing * 2)))
        let sag = abs(end.x - start.x) * Metrics.threadSag
        for bead in 0...beads {
            let t = Double(bead) / Double(beads), arch = sin(.pi * t)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t + sag * arch)
            layer.fill(disc(point, radius: radius * (1 - Metrics.threadNeck * arch)), with: .color(.white))
        }
    }

    /// A word melting: it slumps and stretches downwards, thins until it breaks up, and lets fall a drip or two.
    private func sag(_ drop: Drop, index: Int, melt: Double, font: Font, in layer: inout GraphicsContext) {
        let rect = drop.rect, seed = drop.word.start + Double(index)
        var letters = layer
        // It softens from the crisp shape first, then thins until the strokes fall apart.
        letters.opacity = 1 - Metrics.thinning * smooth((melt - Metrics.thinFrom) / (1 - Metrics.thinFrom))
        letters.translateBy(x: rect.minX, y: rect.minY + fontSize * Metrics.sag * melt * melt)
        letters.scaleBy(x: 1, y: 1 + Metrics.droop * melt)
        thickText(letters.resolve(Text(drop.word.text).font(font).foregroundStyle(Color.white)), at: CGPoint(x: 0, y: rect.height / 2),
                  swell: smooth(melt / Metrics.swellBy), in: letters)

        let count = 1 + Int(seededUnit(seed, salt: Salt.drips) * Double(Metrics.maxDrips))
        for drip in 0..<min(count, Metrics.maxDrips) {
            let salt = UInt64(drip) &* Salt.stride
            let delay = Metrics.dripDelay * seededUnit(seed, salt: Salt.delay &+ salt)
            let fall = unit((melt - delay) / (1 - delay))
            guard fall > 0 else { continue }
            let x = rect.minX + rect.width * ((1 - Metrics.dripSpan) / 2 + Metrics.dripSpan * seededUnit(seed, salt: Salt.place &+ salt))
            let top = rect.midY + fontSize * Metrics.dripTop
            let radius = fontSize * (Metrics.dripRadius + Metrics.dripRadiusSpread * seededUnit(seed, salt: Salt.size &+ salt))
            let bottom = CGPoint(x: x, y: top + fontSize * Metrics.dripFall * fall * fall)
            layer.fill(disc(bottom, radius: radius * (0.6 + 0.4 * smooth(fall * 3))), with: .color(.white))
            // The neck tapers towards the word and snaps once the drop has fallen far enough.
            let neck = radius * 0.55 * (1 - smooth((fall - Metrics.neckBreak) / (1 - Metrics.neckBreak)))
            thread(from: CGPoint(x: x, y: top), to: bottom, radius: neck, in: layer)
        }
    }
}

/// Breaks words into rows no wider than `limit`, using as few rows as possible (at most `Metrics.maxRows`) and then
/// evening them out, so a line does not end in a lone short word. Nil when the words cannot fit.
private func balancedRows(_ widths: [Double], space: Double, limit: Double) -> [Range<Int>]? {
    guard let widest = widths.max(), widest <= limit else { return widths.isEmpty ? [] : nil }
    let greedy = rows(widths, space: space, limit: limit)
    guard greedy.count <= Metrics.maxRows else { return nil }
    let total = widths.reduce(0, +) + space * Double(widths.count - 1)
    var target = max(widest, total / Double(greedy.count))
    while target < limit {
        let even = rows(widths, space: space, limit: target)
        if even.count <= greedy.count { return even }
        target *= Metrics.balanceStep
    }
    return greedy
}

private func rows(_ widths: [Double], space: Double, limit: Double) -> [Range<Int>] {
    var result: [Range<Int>] = [], start = 0, used = 0.0
    for (index, width) in widths.enumerated() {
        if index > start, used + space + width > limit {
            result.append(start..<index)
            (start, used) = (index, width)
        } else {
            used += (index > start ? space : 0) + width
        }
    }
    if start < widths.count { result.append(start..<widths.count) }
    return result
}
