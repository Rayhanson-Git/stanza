import SwiftUI

/// Web: a spider's web that fills with words. The song is cut into pages of 48 words. As each word is sung
/// it shoots a silk thread from the hub to the next free node (nodes fill from left to right), ties itself
/// to neighbours that already hold a word, and hangs its text there. A spider at the hub draws itself as
/// the page fills. Every frame is a closed-form function of the playback position and the clock.
struct WebStyle: View {
    let context: StyleContext

    var body: some View {
        if let scene = WebScene(context: context) {
            let scale = context.settings.textScale
            // The scene is scaled inside the canvas so text stays sharp; a canvas clips, so it gets room to grow.
            let height = context.band * (max(1, scale) + 2 * WebMetrics.canvasMargin)
            Canvas { graphics, size in
                var scaled = graphics
                scaled.translateBy(x: size.width / 2, y: size.height / 2)
                scaled.scaleBy(x: scale, y: scale)
                scaled.translateBy(x: -scene.size.width / 2, y: -scene.size.height / 2)
                scene.draw(in: scaled)
            }
            .frame(width: context.canvas.width, height: height)
            .frame(width: context.canvas.width, height: context.band)
            .offset(scene.kick)
            .shadow(color: .black.opacity(WebMetrics.shadowOpacity), radius: WebMetrics.shadowRadius, y: WebMetrics.shadowY)
        }
    }
}

private enum WebMetrics {
    // The web: 12 spokes × 4 rings, one node for each word of a page.
    static let pageSize = 48, spokes = 12
    static let ringFractions = [0.3, 0.55, 0.78, 1]
    static let radius = 0.46                    // of the band
    static let widening = 1.25                  // the web is wider than tall
    static let maxHalfWidth = 0.47              // of the screen width, so a narrow screen still holds the web
    static let spokeJitter = 0.09               // radians
    // Silk
    static let spokeSamples = 13, spokeBow = 0.05
    static let arcSamples = 15, arcSag = 0.18
    static let spokeWidth = (hub: 3.4, node: 0.5), arcWidth = (ends: 0.5, swell: 2.22)
    static let hairline = 0.1, hairlineHalfWidth = 0.05, minTangent = 0.001, trimCutoff = 0.005
    static let spokeOpacity = 0.85, arcOpacity = 0.7, minSilkAlpha = 0.3
    // How a word arrives
    static let minWordDuration = 0.08, activeTail = 0.2
    static let twangDecay = 0.16, twangFrequency = 15.0
    static let stretchGain = 0.21, popGain = 0.4, tiltDegrees = 8.0
    static let nodeGate = 0.85                  // thread growth at which the dot and label appear
    // Brightness: on the current line (being sung / sung), on an earlier line (being sung / sung)
    static let alphaSinging = 1.0, alphaSung = 0.5, alphaOldSinging = 0.26, alphaOld = 0.13
    // Labels
    static let fontSize = 0.032                 // of the band
    static let singingScale = 1.8, longScale = 2.4, oldScale = 0.75
    static let longThreshold = 1.6, minMeanDuration = 0.01
    static let labelFade = 0.1, labelPop = 0.3, glowScale = 0.4
    static let labelRise = 0.95, labelGap = 11.9
    static let labelSideGap = 9.0, labelPadding = 2.0, referenceSize = 100.0, outsideWeight = 4.0
    // Dots
    static let dotDiameter = 7.0, dotGlow = 8.0
    static let pulseSpeed = 1.2, pulseGrowth = 5.0, pulseWidth = 2.0, pulseOpacity = 0.8
    // Whole scene
    static let kick = 0.014 * 0.6               // of the band
    static let shadowOpacity = 0.5, shadowRadius = 8.0, shadowY = 2.0
    static let canvasMargin = 0.08              // of the band, room for glows around the edge
}

private enum WebSalt {
    static let rotation: UInt64 = 0x0B0B, spoke: UInt64 = 0x5B0C, kick: UInt64 = 0x71CC
}

// MARK: Geometry

private struct WebGeometry {
    let hub: CGPoint
    let radius: Double
    let angles: [Double]
    /// The node each word of the page takes, in sung order: nodes fill from the left of the web to the right.
    let order: [(spoke: Int, ring: Int)]
    /// Inverse of `order`, indexed by `spoke * rings + ring`.
    private let slots: [Int]

    private static let rings = WebMetrics.ringFractions.count

    /// `seed` is the start of the page's first word, so every page gets its own orientation.
    init(seed: Double, size: CGSize) {
        let rings = WebGeometry.rings, turn = 2 * Double.pi
        let rotation = turn * seededUnit(seed, salt: WebSalt.rotation)
        let angles = (0..<WebMetrics.spokes).map { spoke -> Double in
            let jitter = (seededUnit(seed, salt: WebSalt.spoke + UInt64(spoke)) - 0.5) * WebMetrics.spokeJitter
            return rotation + turn * Double(spoke) / Double(WebMetrics.spokes) + jitter
        }
        let offsets = (0..<WebMetrics.spokes * rings).map { cos(angles[$0 / rings]) * WebMetrics.ringFractions[$0 % rings] }
        // The index breaks ties, so the order never depends on whether the sort is stable.
        let nodes = offsets.indices.sorted { (offsets[$0], $0) < (offsets[$1], $1) }
        hub = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = min(WebMetrics.radius * size.height, WebMetrics.maxHalfWidth * size.width / WebMetrics.widening)
        self.angles = angles
        order = nodes.map { (spoke: $0 / rings, ring: $0 % rings) }
        slots = nodes.enumerated().reduce(into: Array(repeating: 0, count: nodes.count)) { $0[$1.element] = $1.offset }
    }

    func slot(spoke: Int, ring: Int) -> Int { slots[spoke * WebGeometry.rings + ring] }

    /// `stretch` scales the distance from the hub; a word's node springs out past its resting place and back.
    func node(spoke: Int, ring: Int, stretch: Double = 1) -> CGPoint {
        let reach = radius * WebMetrics.ringFractions[ring] * stretch
        return CGPoint(x: hub.x + cos(angles[spoke]) * reach * WebMetrics.widening, y: hub.y + sin(angles[spoke]) * reach)
    }

    /// The thread from the hub to a node. It bows slightly sideways, alternate spokes in opposite directions.
    func spokePoints(spoke: Int, ring: Int, stretch: Double) -> [CGPoint] {
        let across = cos(angles[spoke]), down = sin(angles[spoke])
        let side: Double = spoke.isMultiple(of: 2) ? 1 : -1
        return (0..<WebMetrics.spokeSamples).map { sample in
            let along = Double(sample) / Double(WebMetrics.spokeSamples - 1)
            let reach = radius * WebMetrics.ringFractions[ring] * stretch * along
            let bow = radius * sin(.pi * along) * WebMetrics.spokeBow * side
            return CGPoint(x: hub.x + across * reach * WebMetrics.widening - down * bow, y: hub.y + down * reach + across * bow)
        }
    }

    /// The tie between two nodes of one ring: a curve that sags toward the hub, as a real web's rings do.
    func arcPoints(from spoke: Int, to neighbour: Int, ring: Int) -> [CGPoint] {
        let start = node(spoke: spoke, ring: ring), end = node(spoke: neighbour, ring: ring)
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let pull = hypot(end.x - start.x, end.y - start.y) * WebMetrics.arcSag / max(1, hypot(hub.x - middle.x, hub.y - middle.y))
        let control = CGPoint(x: middle.x + (hub.x - middle.x) * pull, y: middle.y + (hub.y - middle.y) * pull)
        return (0..<WebMetrics.arcSamples).map { sample in
            let far = Double(sample) / Double(WebMetrics.arcSamples - 1), near = 1 - far
            return CGPoint(x: near * near * start.x + 2 * near * far * control.x + far * far * end.x,
                           y: near * near * start.y + 2 * near * far * control.y + far * far * end.y)
        }
    }
}

// MARK: Silk

private enum WebSilk {
    /// The first `fraction` of a polyline, ending on an interpolated point.
    static func trimmed(_ points: [CGPoint], to fraction: Double) -> [CGPoint] {
        guard fraction > WebMetrics.trimCutoff, points.count > 1 else { return [] }
        let length = min(1, fraction) * Double(points.count - 1)
        let whole = Int(length), rest = length - Double(Int(length))
        let kept = Array(points.prefix(whole + 1))
        guard rest > 0, whole + 1 < points.count else { return kept }
        let from = points[whole], to = points[whole + 1]
        return kept + [CGPoint(x: from.x + (to.x - from.x) * rest, y: from.y + (to.y - from.y) * rest)]
    }

    /// A filled strip along a polyline. `width` gets the distance along it (0…1), so a thread can taper.
    static func ribbon(_ points: [CGPoint], width: (Double) -> Double) -> Path {
        guard points.count > 1 else { return Path() }
        let last = points.count - 1
        let edges = points.indices.map { index -> (left: CGPoint, right: CGPoint) in
            let ahead = points[min(index + 1, last)], behind = points[max(index, 1) - 1]
            let length = max(WebMetrics.minTangent, hypot(ahead.x - behind.x, ahead.y - behind.y))
            let full = width(Double(index) / Double(last))
            let half = (full > WebMetrics.hairline ? full / 2 : WebMetrics.hairlineHalfWidth) / length
            let offset = CGVector(dx: -(ahead.y - behind.y) * half, dy: (ahead.x - behind.x) * half)
            return (CGPoint(x: points[index].x + offset.dx, y: points[index].y + offset.dy),
                    CGPoint(x: points[index].x - offset.dx, y: points[index].y - offset.dy))
        }
        return Path { path in
            path.addLines(edges.map(\.left) + edges.reversed().map(\.right))
            path.closeSubpath()
        }
    }
}

// MARK: Words

/// One sung word of the page: which node it hangs from and how far its entrance has got.
private struct WebStrand {
    let word: TimedWord
    /// Position in the page, which is also the order nodes are taken in.
    let slot: Int
    let spoke: Int, ring: Int
    let isCurrentLine: Bool, isLong: Bool
    /// Seconds since the word started.
    let age: Double
    /// 0…1, how much of its thread has shot out (ease-out over the word's own length).
    let growth: Double
    /// A damped wobble, -1 at the start settling to 0, shared by the node, the dot and the label.
    let twang: Double
    let isActive: Bool

    init(word: TimedWord, slot: Int, node: (spoke: Int, ring: Int), isCurrentLine: Bool, isLong: Bool, position: Double) {
        self.word = word
        self.slot = slot
        (spoke, ring) = node
        self.isCurrentLine = isCurrentLine
        self.isLong = isLong
        age = max(0, position - word.start)
        let elapsed = min(1, max(0, (position - word.start) / max(word.end - word.start, WebMetrics.minWordDuration)))
        growth = 1 - pow(1 - elapsed, 3)
        twang = -exp(-age / WebMetrics.twangDecay) * cos(WebMetrics.twangFrequency * age)
        isActive = word.start <= position && position < word.end + WebMetrics.activeTail
    }

    var alpha: Double {
        if isCurrentLine { return isActive ? WebMetrics.alphaSinging : WebMetrics.alphaSung }
        return isActive ? WebMetrics.alphaOldSinging : WebMetrics.alphaOld
    }
    var silkAlpha: Double { max(WebMetrics.minSilkAlpha, alpha) }
    var stretch: Double { 1 + WebMetrics.stretchGain * twang }
    var hasNode: Bool { growth > WebMetrics.nodeGate }

    func fontSize(base: Double) -> Double {
        let emphasis = isCurrentLine ? (isLong ? WebMetrics.longScale : 1) : WebMetrics.oldScale
        return base * emphasis * (isActive ? WebMetrics.singingScale : 1)
    }
    /// The size the label settles at while its line is current; label placement is planned around this.
    func restingFontSize(base: Double) -> Double { base * (isLong ? WebMetrics.longScale : 1) }
}

// MARK: Label placement

private enum WebLabels {
    struct Spot {
        /// Which way the label sits from its node: dy picks above or below, dx left or right.
        let side: CGVector
        /// Text size per point of font size.
        let unitSize: CGSize
    }

    static func center(node: CGPoint, side: CGVector, fontSize: Double, width: Double) -> CGPoint {
        let beside = side.dy == 0 ? width / 2 + WebMetrics.labelSideGap : width / 2
        return CGPoint(x: node.x + side.dx * beside,
                       y: node.y + side.dy * (WebMetrics.labelRise * fontSize + WebMetrics.labelGap))
    }

    /// Sides to try, best first: away from the hub's level (above in the top half, below in the bottom half),
    /// then the other way, then beside the node and the diagonals, outward before inward.
    private static func sides(node: CGPoint, hub: CGPoint) -> [CGVector] {
        let away: Double = node.y <= hub.y ? -1 : 1, out: Double = node.x >= hub.x ? 1 : -1
        return [(0, away), (0, -away), (out, 0), (out, away), (out, -away), (-out, 0), (-out, away), (-out, -away)]
            .map { CGVector(dx: $0.0, dy: $0.1) }
    }

    private static func area(_ rect: CGRect) -> Double { rect.isNull ? 0 : rect.width * rect.height }

    /// Greedy and in sung order, so a label never moves once it is placed: each takes the first side of its
    /// node where its resting box is clear of the spider, of earlier labels and of the band's edge, or else
    /// the side that is covered least.
    static func spots(for strands: [WebStrand], geometry: WebGeometry, bounds: CGRect, keepOut: CGRect,
                      baseSize: Double, font: LyricFont) -> [Spot] {
        let reference = font.font(size: WebMetrics.referenceSize)
        var taken = [keepOut]
        return strands.map { strand in
            let measured = (strand.word.text.lowercased() as NSString).size(withAttributes: [.font: reference])
            let unit = CGSize(width: measured.width / WebMetrics.referenceSize, height: measured.height / WebMetrics.referenceSize)
            let fontSize = strand.restingFontSize(base: baseSize)
            let node = geometry.node(spoke: strand.spoke, ring: strand.ring)
            let options = sides(node: node, hub: geometry.hub).map { side -> (side: CGVector, box: CGRect, cost: Double) in
                let middle = center(node: node, side: side, fontSize: fontSize, width: unit.width * fontSize)
                let box = CGRect(x: middle.x - unit.width * fontSize / 2, y: middle.y - unit.height * fontSize / 2,
                                 width: unit.width * fontSize, height: unit.height * fontSize)
                    .insetBy(dx: -WebMetrics.labelPadding, dy: -WebMetrics.labelPadding)
                let outside = (area(box) - area(box.intersection(bounds))) * WebMetrics.outsideWeight
                return (side, box, taken.reduce(outside) { $0 + area(box.intersection($1)) })
            }
            // `min` keeps the earliest of equals, which is the preferred side.
            let best = options.min { $0.cost < $1.cost } ?? options[0]
            taken.append(best.box)
            return Spot(side: best.side, unitSize: unit)
        }
    }
}

// MARK: Spider

private enum WebSpider {
    // Drawn in hub units (the radius of the innermost ring), x to the right, y down; the spider faces up.
    static let abdomen = CGRect(x: -0.2, y: -0.07, width: 0.4, height: 0.54)
    static let head = CGRect(x: -0.13, y: -0.31, width: 0.26, height: 0.28)
    /// Right-hand legs from front to back, each as hip, knee, foot. The left-hand ones are mirror images.
    static let legs: [[CGPoint]] = [
        [CGPoint(x: 0.09, y: -0.26), CGPoint(x: 0.34, y: -0.62), CGPoint(x: 0.24, y: -0.86)],
        [CGPoint(x: 0.12, y: -0.20), CGPoint(x: 0.62, y: -0.44), CGPoint(x: 0.80, y: -0.16)],
        [CGPoint(x: 0.12, y: -0.13), CGPoint(x: 0.66, y: -0.02), CGPoint(x: 0.82, y: 0.34)],
        [CGPoint(x: 0.09, y: -0.07), CGPoint(x: 0.46, y: 0.36), CGPoint(x: 0.52, y: 0.80)],
    ]
    static let legWidth = 0.05
    /// How far the feet reach, in hub units; labels keep out of this square.
    static let reach = 0.9
    static let outlineWidth = 3.2, outlineOpacity = 0.85, fillOpacity = 0.95
    static let entryScale = 0.7
    // When each part appears, as fractions of the page: the last leg is finished as the 48th word lands.
    static let bodySpan = 0.08, headDelay = 0.05, headSpan = 0.08
    static let legDelay = 0.08, legStagger = 0.1, legSpan = 0.2
    static let rockSpeed = 0.9, rockDegrees = 1.6

    /// A filled shape, or (with a line width) a stroked limb.
    private struct Part {
        let path: Path
        let opacity: Double
        let lineWidth: Double?
    }

    static func draw(in graphics: GraphicsContext, at hub: CGPoint, unit: Double, progress: Double, clock: Double, color: Color) {
        var canvas = graphics
        canvas.translateBy(x: hub.x, y: hub.y)
        canvas.rotate(by: .degrees(sin(clock * rockSpeed) * rockDegrees))
        let parts = bodyParts(unit: unit, progress: progress) + legParts(unit: unit, progress: progress)
        // Every dark outline goes down before any fill, so no outline cuts across a neighbouring part.
        for part in parts {
            canvas.stroke(part.path, with: .color(.black.opacity(outlineOpacity * part.opacity)),
                          style: StrokeStyle(lineWidth: (part.lineWidth ?? 0) + outlineWidth, lineCap: .round, lineJoin: .round))
        }
        for part in parts {
            let shading = GraphicsContext.Shading.color(color.opacity(fillOpacity * part.opacity))
            if let lineWidth = part.lineWidth {
                canvas.stroke(part.path, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                canvas.fill(part.path, with: shading)
            }
        }
    }

    /// Abdomen, then head: each fades in while swelling from 70 % to full size about its own centre.
    private static func bodyParts(unit: Double, progress: Double) -> [Part] {
        let amounts = [(abdomen, min(1, progress / bodySpan)), (head, min(1, max(0, (progress - headDelay) / headSpan)))]
        return amounts.filter { $0.1 > 0 }.map { shape, amount in
            let scale = unit * (entryScale + (1 - entryScale) * amount)
            let grown = CGRect(x: shape.midX * unit - shape.width * scale / 2, y: shape.midY * unit - shape.height * scale / 2,
                               width: shape.width * scale, height: shape.height * scale)
            return Part(path: Path(ellipseIn: grown), opacity: amount, lineWidth: nil)
        }
    }

    /// Legs draw themselves from the hip outward, one after another, alternating right and left.
    private static func legParts(unit: Double, progress: Double) -> [Part] {
        (0..<legs.count * 2).compactMap { index in
            let elapsed = (progress - (legDelay + legStagger * Double(index))) / legSpan
            let growth = elapsed <= 0 ? 0 : 1 - pow(1 - min(1, elapsed), 3)
            guard growth > WebMetrics.trimCutoff else { return nil }
            let mirror: Double = index.isMultiple(of: 2) ? 1 : -1
            let joints = legs[index / 2].map { CGPoint(x: $0.x * mirror * unit, y: $0.y * unit) }
            let leg = Path { path in
                path.move(to: joints[0])
                path.addCurve(to: joints[2], control1: joints[1], control2: joints[1])
            }
            return Part(path: leg.trimmedPath(from: 0, to: growth), opacity: 1, lineWidth: legWidth * unit)
        }
    }
}

// MARK: Scene

/// Everything one frame needs, worked out once so the canvas only has to draw.
private struct WebScene {
    let size: CGSize
    let geometry: WebGeometry
    let strands: [WebStrand]
    let spots: [WebLabels.Spot]
    /// How full the page is, 0…1, counting the part of the newest word that has been sung.
    let progress: Double
    let clock: Double
    let kick: CGSize
    let baseFontSize: Double
    let font: LyricFont
    let text: Color, highlight: Color, secondary: Color

    init?(context: StyleContext) {
        let line = context.line, settings = context.settings
        let all = context.lyrics.words, index = context.newestWordIndex
        guard all.indices.contains(index) else { return nil }
        let pageStart = index / WebMetrics.pageSize * WebMetrics.pageSize
        let page = all[pageStart..<min(pageStart + WebMetrics.pageSize, all.count)]
        // Laid out narrower when text is enlarged, so the scaled-up web still fits the screen width.
        let sceneSize = CGSize(width: context.canvas.width / max(1, settings.textScale), height: context.band)
        let geometry = WebGeometry(seed: all[pageStart].start, size: sceneSize)
        // Judged against the whole page rather than the words sung so far, so a word never changes size later.
        let meanDuration = page.reduce(0) { $0 + max($1.end - $1.start, WebMetrics.minMeanDuration) } / Double(page.count)
        let strands = page.prefix(index - pageStart + 1).enumerated().map { slot, word in
            WebStrand(word: word, slot: slot, node: geometry.order[slot], isCurrentLine: word.line == line.words[0].line,
                      isLong: word.end - word.start >= WebMetrics.longThreshold * meanDuration, position: context.position)
        }
        let hubUnit = geometry.radius * WebMetrics.ringFractions[0]
        size = sceneSize
        baseFontSize = WebMetrics.fontSize * context.band
        spots = WebLabels.spots(for: strands, geometry: geometry, bounds: CGRect(origin: .zero, size: size),
                                keepOut: CGRect(x: geometry.hub.x, y: geometry.hub.y, width: 0, height: 0)
                                    .insetBy(dx: -WebSpider.reach * hubUnit, dy: -WebSpider.reach * hubUnit),
                                baseSize: baseFontSize, font: settings.font)
        progress = (Double(strands.count - 1) + (strands.last?.growth ?? 0)) / Double(WebMetrics.pageSize)
        kick = WebScene.kick(after: strands.last, band: context.band)
        self.geometry = geometry
        self.strands = strands
        clock = context.clock
        font = settings.font
        text = Color(nsColor: settings.textColor)
        highlight = Color(nsColor: settings.highlightColor)
        secondary = Color(nsColor: settings.secondaryColor)
    }

    /// The whole web jolts in a random direction when a word lands, then rings down.
    private static func kick(after newest: WebStrand?, band: Double) -> CGSize {
        guard let newest else { return .zero }
        let direction = 2 * Double.pi * seededUnit(newest.word.start, salt: WebSalt.kick)
        // The twang is that same damped wobble with the opposite sign.
        let distance = band * WebMetrics.kick * -newest.twang
        return CGSize(width: cos(direction) * distance, height: sin(direction) * distance)
    }

    func draw(in graphics: GraphicsContext) {
        strands.forEach { drawSilk($0, in: graphics) }
        WebSpider.draw(in: graphics, at: geometry.hub, unit: geometry.radius * WebMetrics.ringFractions[0],
                       progress: progress, clock: clock, color: text)
        let hung = strands.indices.filter { strands[$0].hasNode }
        hung.forEach { drawDot(strands[$0], in: graphics) }
        // Words being sung go last: their enlarged labels belong on top of the resting ones.
        (hung.filter { !strands[$0].isActive } + hung.filter { strands[$0].isActive })
            .forEach { drawLabel(strands[$0], spot: spots[$0], in: graphics) }
    }

    private func drawSilk(_ strand: WebStrand, in graphics: GraphicsContext) {
        let spoke = geometry.spokePoints(spoke: strand.spoke, ring: strand.ring, stretch: strand.stretch)
        let thread = WebSilk.ribbon(WebSilk.trimmed(spoke, to: strand.growth)) { along in
            WebMetrics.spokeWidth.hub + (WebMetrics.spokeWidth.node - WebMetrics.spokeWidth.hub) * along
        }
        graphics.fill(thread, with: .color(text.opacity(strand.silkAlpha * WebMetrics.spokeOpacity)))
        for step in [-1, 1] {
            let neighbour = (strand.spoke + step + WebMetrics.spokes) % WebMetrics.spokes
            // A word only ties on to a neighbour that already holds an earlier word.
            guard geometry.slot(spoke: neighbour, ring: strand.ring) < strand.slot else { continue }
            let arc = geometry.arcPoints(from: strand.spoke, to: neighbour, ring: strand.ring)
            let tie = WebSilk.ribbon(WebSilk.trimmed(arc, to: strand.growth)) { along in
                WebMetrics.arcWidth.ends + WebMetrics.arcWidth.swell * sin(.pi * along)
            }
            graphics.fill(tie, with: .color(text.opacity(strand.silkAlpha * WebMetrics.arcOpacity)))
        }
    }

    private func drawDot(_ strand: WebStrand, in graphics: GraphicsContext) {
        let node = geometry.node(spoke: strand.spoke, ring: strand.ring, stretch: strand.stretch)
        var dot = graphics
        dot.opacity = strand.alpha
        if strand.isActive { dot.addFilter(.shadow(color: highlight, radius: WebMetrics.dotGlow)) }
        dot.fill(WebScene.circle(at: node, diameter: WebMetrics.dotDiameter * (1 + WebMetrics.popGain * strand.twang)),
                 with: .color(strand.isActive ? highlight : text))
        guard strand.isActive else { return }
        // A ring keeps spreading from the dot for as long as the word is being sung.
        let phase = (strand.age * WebMetrics.pulseSpeed).truncatingRemainder(dividingBy: 1)
        graphics.stroke(WebScene.circle(at: node, diameter: WebMetrics.dotDiameter * (1 + WebMetrics.pulseGrowth * phase)),
                        with: .color(highlight.opacity((1 - phase) * WebMetrics.pulseOpacity)), lineWidth: WebMetrics.pulseWidth)
    }

    private func drawLabel(_ strand: WebStrand, spot: WebLabels.Spot, in graphics: GraphicsContext) {
        let fontSize = strand.fontSize(base: baseFontSize)
        let width = spot.unitSize.width * fontSize, height = spot.unitSize.height * fontSize
        let node = geometry.node(spoke: strand.spoke, ring: strand.ring, stretch: strand.stretch)
        let free = WebLabels.center(node: node, side: spot.side, fontSize: fontSize, width: width)
        var label = graphics
        label.opacity = min(1, strand.age / WebMetrics.labelFade) * strand.alpha
        // Whatever its size at this moment, the whole label stays inside the band.
        label.translateBy(x: min(max(free.x, width / 2), max(width / 2, size.width - width / 2)),
                          y: min(max(free.y, height / 2), max(height / 2, size.height - height / 2)))
        label.rotate(by: .degrees(WebMetrics.tiltDegrees * strand.twang))
        let pop = 1 + WebMetrics.labelPop * exp(-strand.age / WebMetrics.labelFade)
        label.scaleBy(x: pop, y: pop)
        if strand.isLong && strand.isCurrentLine && strand.isActive {
            label.addFilter(.shadow(color: highlight, radius: fontSize * WebMetrics.glowScale))
        }
        label.draw(Text(strand.word.text.lowercased()).font(Font(font.font(size: fontSize) as CTFont))
            .foregroundStyle(strand.isActive ? text : secondary), at: .zero, anchor: .center)
    }

    private static func circle(at center: CGPoint, diameter: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter))
    }
}

// MARK: Self-check

/// Assert-style checks of this style's pure logic; returns a description of each failure.
func webStyleSelfCheck() -> [String] {
    func word(_ start: Double) -> TimedWord { TimedWord(text: "la", start: start, end: start + 0.3, line: 0) }
    let line = (0..<5).map { CGPoint(x: Double($0), y: 0) }
    let half = WebSilk.trimmed(line, to: 0.375)
    let geometry = WebGeometry(seed: 12.5, size: CGSize(width: 1440, height: 504))
    let columns = geometry.order.map { geometry.node(spoke: $0.spoke, ring: $0.ring).x }
    let checks: [(Bool, String)] = [
        (half.count == 3 && abs((half.last?.x ?? 0) - 1.5) < 0.0001, "web: a trimmed thread ends on an interpolated point"),
        (WebSilk.trimmed(line, to: 0.004).isEmpty && WebSilk.trimmed(line, to: 2).count == line.count, "web: trim is clamped"),
        (geometry.order.count == WebMetrics.pageSize && zip(columns, columns.dropFirst()).allSatisfy { $0 <= $1 },
         "web: 48 nodes, taken from left to right"),
        (geometry.order.indices.allSatisfy { geometry.slot(spoke: geometry.order[$0].spoke, ring: geometry.order[$0].ring) == $0 },
         "web: every node knows its own slot"),
    ]
    return checks.filter { !$0.0 }.map(\.1)
}
