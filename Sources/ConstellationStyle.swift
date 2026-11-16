import SwiftUI

/// Constellation: the song is cut into chunks of 14 words and each chunk is one constellation. Every sung
/// word lights a four-point star labelled with the word, joined to the previous star by a line that grows
/// while the word is sung. Nothing is animated by SwiftUI: each frame is a closed-form function of the
/// playback position and the wall clock.
struct ConstellationStyle: View {
    let context: StyleContext

    var body: some View {
        let sky = Sky(context: context)
        Canvas { graphics, _ in sky?.draw(in: graphics) }
            .frame(width: context.canvas.width, height: context.band)
            .scaleEffect(context.scale)
            .offset(sky?.kick ?? .zero)
            .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
    }
}

private enum Metrics {
    static let chunkSize = 14
    static let shadowOpacity = 0.5, shadowRadius = 8.0, shadowY = 2.0

    // Stars
    static let minDuration = 0.08, minAveragedDuration = 0.01
    static let easePower = 3.0
    static let activeTail = 0.2                 // a star stays lit this long after its word ends
    static let restingBrightness = 0.55
    static let bounceDecay = 0.16, bounceSpeed = 15.0, bounceGain = 0.35
    static let twinkleDepth = 0.08, twinkleHertz = 1.4
    static let longWord = 1.6                   // held this many times the chunk's mean duration
    static let restingRadius = 9.0, activeRadius = 13.5, longRadiusScale = 1.8
    static let sparkleWaist = 0.34              // inner vertices, as a fraction of the radius
    static let glowRadius = 10.0
    static let drawThreshold = 0.01
    static let edgeWidth = 1.4, edgeOpacity = 0.5
    static let rippleRate = 1.2, rippleGrowth = 4.0, rippleOpacity = 0.8, rippleWidth = 2.0
    static let pulseGain = 0.5, pulseLength = 0.8
    static let kick = 0.014 * 0.6               // of the band

    // Shooting star
    static let streakLife = 0.5, streakGrowth = 0.3, streakLength = 0.22
    static let streakSlope = CGVector(dx: 0.8, dy: 0.6)
    static let streakOpacity = 0.9, streakWidth = 1.6

    // Labels
    static let labelThreshold = 0.6             // of the star's eased growth
    static let labelSize = 0.032, labelActiveScale = 1.8, labelLongScale = 2.4
    static let labelStarGap = 0.9, labelLineGap = 0.95
    static let labelTiltDegrees = 8.0, labelPop = 0.3, labelPopDecay = 0.1, labelFadeIn = 0.1

    // Dust
    static let dustCount: UInt64 = 26
    static let dustRadius = 1.0, dustRadiusSpread = 1.2
    static let dustGlow = 0.6, dustShimmer = 0.4, dustSpeed = 0.8, dustOpacity = 0.14

    // Layout (lengths are fractions of the band height unless noted)
    static let margin = 0.14, maxFieldAspect = 3.4, fieldInset = 4.0
    static let startInset = 0.25, startSpan = 0.5
    static let spacing = 0.22, linkReach = 0.17
    static let step = 0.34, stepBase = 0.8, stepSpread = 0.55
    static let maxLinks = 3, maxLinksPerStar = 2
    /// Step-length multiplier per attempt; its count is the number of attempts.
    static let reach: [CGFloat] = [1, 0.75, 1.25, 0.6, 1.4, 0.85, 1.15, 0.7, 1.3, 0.95, 1.5, 0.65]
    static let attemptStride = 13
    static let firstTurn = 85 * Double.pi / 180, goldenAngle = 2.399963, turnJitter = 0.6
    static let clearanceCap: CGFloat = 1.5
    static let gridColumns = 14, gridRows = 7
    static let gridClearanceCap: CGFloat = 1.6, gridLeash: CGFloat = 1.8, gridLeashWeight: CGFloat = 0.3
}

private enum Salt {
    static let startX: UInt64 = 0xC0A1, startY: UInt64 = 0xC0A2, heading: UInt64 = 0xC0A3
    static let twinkle: UInt64 = 0xC0A4, kick: UInt64 = 0xC0A5
    // Indexed salts: each block is wide enough for its largest index.
    static let step: UInt64 = 0xC100, attempt: UInt64 = 0xC200
    static let dustX: UInt64 = 0xC400, dustY: UInt64 = 0xC500, dustSize: UInt64 = 0xC600, dustPhase: UInt64 = 0xC700
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

private func clearance(of point: CGPoint, from stars: [CGPoint]) -> CGFloat {
    stars.map { distance(point, $0) }.min() ?? .greatestFiniteMagnitude
}

private func segment(from start: CGPoint, to end: CGPoint, fraction: CGFloat) -> Path {
    Path { path in
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction))
    }
}

// MARK: Layout

/// Where the stars of one chunk sit and which pairs are joined. A pure function of its inputs, so a chunk
/// never shifts between frames; small enough (14 stars × 12 tries) to rebuild every frame without a cache.
struct ConstellationMap {
    struct Edge { let from: Int, to: Int }

    let stars: [CGPoint]
    let edges: [Edge]

    init(seed: Double, width: CGFloat, band: CGFloat, textScale: Double) {
        // The scene is magnified by the text scale afterwards, so the field shrinks to stay inside the band.
        let scale = max(1, textScale)
        let fieldSize = CGSize(width: min(Metrics.maxFieldAspect * band, width * (1 - 2 * Metrics.margin) / scale),
                               height: band * (1 - 2 * Metrics.margin) / scale)
        let field = CGRect(x: (width - fieldSize.width) / 2, y: (band - fieldSize.height) / 2,
                           width: fieldSize.width, height: fieldSize.height)
        let walker = Walker(seed: seed, field: field.insetBy(dx: Metrics.fieldInset, dy: Metrics.fieldInset),
                            spacing: Metrics.spacing * band, stride: Metrics.step * band)
        var stars: [CGPoint] = [], edges: [Edge] = []
        var here = CGPoint(x: field.minX + (Metrics.startInset + Metrics.startSpan * seededUnit(seed, salt: Salt.startX)) * field.width,
                           y: field.minY + (Metrics.startInset + Metrics.startSpan * seededUnit(seed, salt: Salt.startY)) * field.height)
        var heading = 2 * Double.pi * seededUnit(seed, salt: Salt.heading)
        for index in 0..<Metrics.chunkSize {
            stars.append(here)
            if index > 0 { edges.append(Edge(from: index - 1, to: index)) }
            if let link = Self.link(to: index, stars: stars, edges: edges, reach: Metrics.linkReach * band) { edges.append(link) }
            (here, heading) = walker.next(after: index, from: here, heading: heading, avoiding: stars)
        }
        self.stars = stars
        self.edges = edges
    }

    /// An extra edge closing a loop to an earlier star that happens to be very near, if any.
    private static func link(to index: Int, stars: [CGPoint], edges: [Edge], reach: CGFloat) -> Edge? {
        let links = edges.filter { $0.to - $0.from > 1 }
        guard index > 1, links.count < Metrics.maxLinks else { return nil }
        let source = (0..<index - 1).first { candidate in
            links.filter { $0.from == candidate }.count < Metrics.maxLinksPerStar && distance(stars[index], stars[candidate]) < reach
        }
        return source.map { Edge(from: $0, to: index) }
    }
}

/// The seeded random walk that picks each next star.
private struct Walker {
    let seed: Double
    let field: CGRect
    let spacing: CGFloat
    let stride: CGFloat

    /// Tries a dozen directions and takes the first that lands inside the field clear of every star;
    /// if none does, falls back to the roomiest cell of a coarse grid.
    func next(after index: Int, from origin: CGPoint, heading: Double, avoiding stars: [CGPoint]) -> (CGPoint, Double) {
        let step = stride * (Metrics.stepBase + Metrics.stepSpread * seededUnit(seed, salt: Salt.step + UInt64(index)))
        var best = (score: -CGFloat.greatestFiniteMagnitude, point: origin, heading: heading)
        for attempt in Metrics.reach.indices {
            let jitter = seededUnit(seed, salt: Salt.attempt + UInt64(Metrics.attemptStride * index + attempt)) - 0.5
            let turn = attempt == 0 ? 2 * jitter * Metrics.firstTurn : Double(attempt) * Metrics.goldenAngle + jitter * Metrics.turnJitter
            let length = step * Metrics.reach[attempt]
            let raw = CGPoint(x: origin.x + cos(heading + turn) * length, y: origin.y + sin(heading + turn) * length)
            let isInside = field.contains(raw)
            let point = CGPoint(x: min(max(raw.x, field.minX), field.maxX), y: min(max(raw.y, field.minY), field.maxY))
            let room = clearance(of: point, from: stars)
            let score = min(room, Metrics.clearanceCap * spacing) - (isInside ? 0 : spacing)
            if score > best.score { best = (score, point, heading + turn) }
            if isInside && room >= spacing { break }
        }
        guard clearance(of: best.point, from: stars) < spacing else { return (best.point, best.heading) }
        let cell = roomiestCell(near: origin, step: step, avoiding: stars)
        return (cell, atan2(cell.y - origin.y, cell.x - origin.x))
    }

    private func roomiestCell(near origin: CGPoint, step: CGFloat, avoiding stars: [CGPoint]) -> CGPoint {
        let cellSize = CGSize(width: field.width / CGFloat(Metrics.gridColumns), height: field.height / CGFloat(Metrics.gridRows))
        func score(_ cell: CGPoint) -> CGFloat {
            let room: CGFloat = min(clearance(of: cell, from: stars), Metrics.gridClearanceCap * spacing)
            let overreach: CGFloat = max(0, distance(cell, origin) - Metrics.gridLeash * step)
            return room - Metrics.gridLeashWeight * overreach
        }
        var best = (score: -CGFloat.greatestFiniteMagnitude, cell: origin)
        for column in 0..<Metrics.gridColumns {
            for row in 0..<Metrics.gridRows {
                let cell = CGPoint(x: field.minX + (CGFloat(column) + 0.5) * cellSize.width,
                                   y: field.minY + (CGFloat(row) + 0.5) * cellSize.height)
                let cellScore = score(cell)
                if cellScore > best.score { best = (cellScore, cell) }
            }
        }
        return best.cell
    }
}

// MARK: Timing

/// The 14-word slice of the song that the newest sung word belongs to.
private struct Chunk {
    /// The words sung so far, oldest first.
    let words: [TimedWord]
    /// Seeds the layout and the dust, so both change together at a chunk boundary.
    let seed: Double
    let isComplete: Bool
    let longDuration: Double

    init?(context: StyleContext) {
        let all = context.lyrics.words, newest = context.newestWordIndex
        guard all.indices.contains(newest) else { return nil }
        let first = newest / Metrics.chunkSize * Metrics.chunkSize
        let whole = all[first..<min(first + Metrics.chunkSize, all.count)]
        words = Array(all[first...newest])
        seed = all[first].start
        isComplete = words.count == Metrics.chunkSize
        // Measured over the whole chunk, not just the words sung so far, so a star never changes class
        // (and jumps in size) when a later word arrives.
        longDuration = Metrics.longWord * whole.reduce(0) { $0 + max(Metrics.minAveragedDuration, $1.end - $1.start) } / Double(whole.count)
    }

    /// The whole constellation swells once, just after its last word.
    func pulse(at position: Double) -> Double {
        guard isComplete, let last = words.last else { return 1 }
        let phase = min(max((position - last.end) / Metrics.pulseLength, 0), 1)
        return 1 + Metrics.pulseGain * sin(.pi * phase)
    }
}

/// How one star looks at one instant.
private struct StarMotion {
    let age: Double
    let eased: Double
    let isActive: Bool
    let isLong: Bool
    let brightness: Double
    let bounce: Double
    let radius: CGFloat

    /// nil until the word has begun.
    init?(word: TimedWord, isLong: Bool, pulse: Double, position: Double, clock: Double) {
        let duration = word.end - word.start
        let age = max(0, position - word.start)
        let progress = min(age / max(duration, Metrics.minDuration), 1)
        guard progress > 0 else { return nil }
        let isActive = position < word.end + Metrics.activeTail
        let bounce = exp(-age / Metrics.bounceDecay) * cos(Metrics.bounceSpeed * age + .pi)
        let twinkle = 1 + Metrics.twinkleDepth * sin(2 * .pi * (seededUnit(word.start, salt: Salt.twinkle) + clock * Metrics.twinkleHertz))
        self.age = age
        self.eased = 1 - pow(1 - progress, Metrics.easePower)
        self.isActive = isActive
        self.isLong = isLong
        self.bounce = bounce
        brightness = pulse * (isActive ? 1 : Metrics.restingBrightness)
        radius = eased * (1 + Metrics.bounceGain * bounce) * (isActive ? Metrics.activeRadius : Metrics.restingRadius)
            * (isLong ? Metrics.longRadiusScale : 1) * twinkle
    }
}

// MARK: Drawing

private struct Sky {
    let context: StyleContext
    let chunk: Chunk
    let map: ConstellationMap
    /// One entry per sung word of the chunk, paired with its star.
    let lit: [(word: TimedWord, star: CGPoint, index: Int, motion: StarMotion)]

    private var textColor: Color { Color(nsColor: context.settings.textColor) }
    private var highlight: Color { Color(nsColor: context.settings.highlightColor) }
    private var secondary: Color { Color(nsColor: context.settings.secondaryColor) }

    init?(context: StyleContext) {
        guard let chunk = Chunk(context: context) else { return nil }
        let map = ConstellationMap(seed: chunk.seed, width: context.canvas.width, band: context.band,
                                   textScale: context.scale)
        let pulse = chunk.pulse(at: context.position)
        self.context = context
        self.chunk = chunk
        self.map = map
        lit = chunk.words.enumerated().compactMap { index, word in
            StarMotion(word: word, isLong: word.end - word.start >= chunk.longDuration, pulse: pulse,
                       position: context.position, clock: context.clock)
                .map { (word, map.stars[index], index, $0) }
        }
    }

    /// A small decaying jolt of the whole sky each time a word lands.
    var kick: CGSize {
        guard let newest = chunk.words.last else { return .zero }
        let age = max(0, context.position - newest.start)
        let reach = context.band * Metrics.kick * exp(-age / Metrics.bounceDecay) * cos(Metrics.bounceSpeed * age)
        let angle = 2 * Double.pi * seededUnit(newest.start, salt: Salt.kick)
        return CGSize(width: cos(angle) * reach, height: sin(angle) * reach)
    }

    /// Lines first and labels last, so a later line never crosses an earlier word.
    func draw(in graphics: GraphicsContext) {
        drawDust(in: graphics)
        lit.forEach { drawEdges(into: $0.index, $0.motion, in: graphics) }
        lit.forEach { drawStreak(to: $0.star, $0.motion, in: graphics) }
        lit.forEach { drawStar(at: $0.star, $0.motion, in: graphics) }
        lit.forEach { drawLabel($0.word.text.lowercased(), for: $0.star, $0.motion, in: graphics) }
    }

    private func drawDust(in graphics: GraphicsContext) {
        for dot in 0..<Metrics.dustCount {
            let center = CGPoint(x: seededUnit(chunk.seed, salt: Salt.dustX + dot) * context.canvas.width,
                                 y: seededUnit(chunk.seed, salt: Salt.dustY + dot) * context.band)
            let radius = Metrics.dustRadius + Metrics.dustRadiusSpread * seededUnit(chunk.seed, salt: Salt.dustSize + dot)
            let phase = 2 * Double.pi * seededUnit(chunk.seed, salt: Salt.dustPhase + dot)
            let glow = Metrics.dustGlow + Metrics.dustShimmer * sin(phase + Metrics.dustSpeed * context.clock)
            graphics.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                          with: .color(textColor.opacity(glow * Metrics.dustOpacity)))
        }
    }

    private func drawEdges(into index: Int, _ motion: StarMotion, in graphics: GraphicsContext) {
        guard motion.eased > Metrics.drawThreshold else { return }
        let color = textColor.opacity(min(1, motion.brightness * Metrics.edgeOpacity))
        for edge in map.edges where edge.to == index {
            graphics.stroke(segment(from: map.stars[edge.from], to: map.stars[index], fraction: motion.eased),
                            with: .color(color), style: StrokeStyle(lineWidth: Metrics.edgeWidth, lineCap: .round))
        }
    }

    /// Long-held words arrive as a shooting star from the upper left.
    private func drawStreak(to star: CGPoint, _ motion: StarMotion, in graphics: GraphicsContext) {
        let growth = min(motion.age / Metrics.streakGrowth, 1)
        guard motion.isLong, motion.age < Metrics.streakLife, growth > Metrics.drawThreshold else { return }
        let length = Metrics.streakLength * context.band
        let tail = CGPoint(x: star.x - Metrics.streakSlope.dx * length, y: star.y - Metrics.streakSlope.dy * length)
        let fade = (1 - motion.age / Metrics.streakLife) * Metrics.streakOpacity
        graphics.stroke(segment(from: tail, to: star, fraction: growth), with: .color(highlight.opacity(fade)),
                        lineWidth: Metrics.streakWidth)
    }

    private func drawStar(at center: CGPoint, _ motion: StarMotion, in graphics: GraphicsContext) {
        var glowing = graphics
        if motion.isActive { glowing.addFilter(.shadow(color: highlight, radius: Metrics.glowRadius)) }
        glowing.fill(sparkle(at: center, radius: motion.radius),
                     with: .color((motion.isActive ? highlight : textColor).opacity(min(1, motion.brightness))))
        guard motion.isActive else { return }
        let phase = (Metrics.rippleRate * motion.age).truncatingRemainder(dividingBy: 1)
        let diameter = (1 + Metrics.rippleGrowth * phase) * motion.radius
        let ring = Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
        graphics.stroke(ring, with: .color(highlight.opacity((1 - phase) * Metrics.rippleOpacity)), lineWidth: Metrics.rippleWidth)
    }

    private func sparkle(at center: CGPoint, radius: CGFloat) -> Path {
        let waist = Metrics.sparkleWaist * radius
        let offsets: [(CGFloat, CGFloat)] = [(radius, 0), (waist, waist), (0, radius), (-waist, waist),
                                             (-radius, 0), (-waist, -waist), (0, -radius), (waist, -waist)]
        return Path { path in
            path.addLines(offsets.map { CGPoint(x: center.x + $0.0, y: center.y + $0.1) })
            path.closeSubpath()
        }
    }

    private func drawLabel(_ text: String, for star: CGPoint, _ motion: StarMotion, in graphics: GraphicsContext) {
        guard motion.eased > Metrics.labelThreshold else { return }
        let fontSize = Metrics.labelSize * context.band * (motion.isActive ? Metrics.labelActiveScale : 1)
            * (motion.isLong ? Metrics.labelLongScale : 1)
        let label = graphics.resolve(Text(text).font(context.font(fontSize)).foregroundStyle(motion.isActive ? textColor : secondary))
        // Labels sit on the side of the star that faces the middle of the band, and never run off the screen
        // (a magnified scene is wider than the screen, so its visible part is narrower than the canvas).
        let side: CGFloat = star.y > context.band / 2 ? -1 : 1
        let width = context.canvas.width
        let nearest = (width - width / max(1, context.scale) + label.measure(in: context.canvas).width) / 2
        let pop = 1 + Metrics.labelPop * exp(-motion.age / Metrics.labelPopDecay)
        var layer = graphics
        layer.opacity = min(1, min(motion.age / Metrics.labelFadeIn, 1) * motion.brightness)
        layer.translateBy(x: min(max(star.x, nearest), max(nearest, width - nearest)),
                          y: star.y + side * (Metrics.labelStarGap * motion.radius + Metrics.labelLineGap * fontSize))
        layer.rotate(by: .degrees(Metrics.labelTiltDegrees * motion.bounce))
        layer.scaleBy(x: pop, y: pop)
        layer.draw(label, at: .zero)
    }
}
