import SwiftUI

/// Branches: a wavy stem grows across the band as the line is sung, led by a glowing head. Each word sprouts
/// a springy branch above or below the stem that ends in a dot and the word itself. Nothing is animated by
/// SwiftUI: every value is a closed-form function of the song position and the wall clock.
struct BranchesStyle: View {
    let context: StyleContext

    var body: some View {
        let scale = context.scale
        // Laid out narrower and then scaled up, so a large text size cannot push the stem's ends off screen.
        let size = CGSize(width: context.canvas.width / max(1, scale), height: context.band)
        let scene = BranchScene(context: context, size: size)
        ZStack {
            Canvas { graphics, _ in scene.draw(in: &graphics) }
            ForEach(scene.sprouts.filter(\.showsLeaf), id: \.twig.bud.index) { label($0, in: scene) }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale)
        .offset(scene.kick)
        .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
        // A new line starts a fresh plant instead of morphing the old one.
        .id(context.line.index)
    }

    private func label(_ sprout: Sprout, in scene: BranchScene) -> some View {
        let twig = sprout.twig, bud = twig.bud, size = sprout.fontSize, palette = scene.palette
        let glow = bud.isLong ? palette.highlight.opacity(1 - sprout.calm) : .clear
        return HStack(spacing: size * Metrics.iconSpacing) {
            if let visual = bud.visual {
                WordIcon(visual: visual, size: size * Metrics.iconScale,
                         color: palette.highlight.mix(with: palette.text, by: sprout.calm), age: sprout.age)
            }
            Text(bud.word.text.lowercased())
                .font(context.font(size))
                .foregroundStyle(palette.text.mix(with: palette.secondary, by: sprout.calm))
                .shadow(color: glow, radius: size * Metrics.glowRadius)
                .shadow(color: glow.opacity(Metrics.haloOpacity), radius: size * Metrics.haloRadius)
        }
        .lineLimit(1)
        .fixedSize()
        .rotationEffect(.degrees(-twig.side * Metrics.labelTiltDegrees * ringing(sprout.age)))
        .scaleEffect(1 + Metrics.labelPop * exp(-sprout.age / Metrics.labelPopDecay))
        .position(sprout.labelCentre)
        .opacity(sprout.leafOpacity * sprout.dim * min(1, sprout.age / Metrics.labelFadeIn))
    }
}

private enum Metrics {
    // Timing
    static let minLineDuration = 0.1, minWordDuration = 0.01, minGrowTime = 0.08
    static let activeTail = 0.2                 // a word stays lit this long after it ends…
    static let calmDuration = 0.2               // …then eases into the background over this long
    static let ringDecay = 0.16, ringRate = 15.0

    // Stem (fractions of the scene's width and of the band)
    static let stemInset = 0.11, stemSpan = 0.78, stemAmplitude = 0.06
    static let stemSegments = 72.0, minStemSpan = 0.01 / 72
    static let stemWaves = 2.6, stemWaveFloor = 0.8, stemWaveSpread = 0.4
    static let ripplePhase = 1.9, rippleWaves = 2.35, rippleSpeed = 1.84, rippleWeight = 0.45
    static let shimmerWaves = 3.65, shimmerSpeed = 2.48, shimmerWeight = 0.2
    static let stemWidth = 2.0, stemOpacity = 0.85

    // Head, trail and exit ring
    static let headDiameter = 9.0, headPulse = 0.2, headPulseSpeed = 3.4, headFadeInRate = 8.0
    static let headGlowRadius = 8.0, headGlowOpacity = 0.9, headHaloRadius = 18.0, headHaloOpacity = 0.5
    static let trailCount = 4, trailSpacing = 0.016, trailDiameter = 4.05, trailOpacity = 0.5
    static let exitRingGrowth = 63.0, exitRingWidth = 2.5

    // Branches
    static let stationRange = 0.04...0.96
    static let sideFlipThreshold = 0.7
    static let branchLength = 0.26, branchLengthFloor = 0.75, branchLengthSpread = 0.5     // of the band
    static let branchLean = 0.1                                                            // of the width
    static let springAmount = 0.35, bendLean = 0.4, bendSag = 0.15
    static let branchWidth = 1.6, branchOpacity = 0.7
    static let leafThreshold = 0.95, leafExitCutoff = 0.5
    static let restingOpacity = 0.38
    static let tipDiameter = 6.0, tipPop = 0.35, tipPopDecay = 0.12, tipGlow = 7.0
    static let pulseRate = 1.2, pulseGrowth = 4.5, pulseWidth = 1.8, pulseOpacity = 0.8

    // Labels
    static let fontSize = 0.034, activeScale = 1.75                                        // of the band
    static let widestBand = 0.45                                                           // of the width: keeps labels sane on a portrait screen
    static let longScale = 2.9, longHold = 1.6                                             // "long" = held 1.6× the line's average
    static let labelOffset = 0.9, labelGap = 9.6                                           // font sizes + points beyond the tip
    static let labelTiltDegrees = 8.0, labelPop = 0.3, labelPopDecay = 0.1, labelFadeIn = 0.1
    static let iconScale = 1.1, iconSpacing = 0.35
    static let glowRadius = 0.35, haloRadius = 0.8, haloOpacity = 0.5
    static let measuringSize = 100.0, lineHeight = 1.2
    static let edgeMargin = 0.02, labelPadding = 0.012                                     // of the band
    static let minFit = 0.25
    // Keeping labels apart: places tried on a word's own side of the stem, then as many again on the other side.
    static let triesPerSide = 12
    static let branchProbes = [0.2, 0.4, 0.6, 0.8]                                         // where a branch is tested against labels
    static let crossingPenalty = 0.0025                                                    // of the band's area, per probe inside a label

    // Scene
    static let kickStrength = 0.014
    static let shadowOpacity = 0.45, shadowRadius = 10.0, shadowY = 2.0
    static let glyphs = ["/", "<", ">", "·", "+", "—"]
    static let glyphCount = 8, glyphSize = 0.03, glyphOpacity = 0.14
    static let glyphDriftX = 0.015, glyphDriftXSpeed = 0.11
    static let glyphDriftY = 0.02, glyphDriftYSpeed = 0.09, glyphDriftYPhase = 1.7
}

private enum Salt {
    static let stemPhase: UInt64 = 0xB0A1, stemWaves: UInt64 = 0xB0A2, kick: UInt64 = 0xB0A3, side: UInt64 = 0xB0A4
    static let length: UInt64 = 0xB0A5, lean: UInt64 = 0xB0A6
    static let glyph: UInt64 = 0xB100, glyphStride: UInt64 = 3
    static let retryStride: UInt64 = 0x1_0000
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
private func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }

/// A decaying oscillation that starts at 1: the spring behind branch length, label tilt and the scene kick.
private func ringing(_ age: Double) -> Double { exp(-age / Metrics.ringDecay) * cos(Metrics.ringRate * age) }

/// A branch is a quadratic curve that leans further out than its tip and sags along its length.
private func branchBend(from root: CGPoint, to tip: CGPoint, lean: Double, rise: Double) -> CGPoint {
    CGPoint(x: (root.x + tip.x) / 2 + Metrics.bendLean * lean, y: (root.y + tip.y) / 2 + Metrics.bendSag * rise)
}

private func disc(at centre: CGPoint, diameter: Double) -> Path {
    Path(ellipseIn: CGRect(x: Double(centre.x) - diameter / 2, y: Double(centre.y) - diameter / 2, width: diameter, height: diameter))
}

private struct Palette {
    let text: Color, highlight: Color, secondary: Color

    init(_ settings: AppSettings) {
        text = Color(nsColor: settings.textColor)
        highlight = Color(nsColor: settings.highlightColor)
        secondary = Color(nsColor: settings.secondaryColor)
    }
}

/// The curve the line grows along: a fixed swell per line, plus two ripples that keep it alive.
private struct Stem {
    let width: Double, band: Double, clock: Double
    let phase: Double, waves: Double

    init(seed: Double, clock: Double, size: CGSize) {
        width = size.width
        band = size.height
        self.clock = clock
        phase = 2 * .pi * seededUnit(seed, salt: Salt.stemPhase)
        waves = Metrics.stemWaves * (Metrics.stemWaveFloor + Metrics.stemWaveSpread * seededUnit(seed, salt: Salt.stemWaves))
    }

    func point(_ t: Double) -> CGPoint {
        let ripple = sin(Metrics.ripplePhase * phase + 2 * .pi * Metrics.rippleWaves * t - clock * Metrics.rippleSpeed)
        let shimmer = sin(clock * Metrics.shimmerSpeed + 2 * .pi * Metrics.shimmerWaves * t)
        return point(t, wave: swell(t) + Metrics.rippleWeight * ripple + Metrics.shimmerWeight * shimmer)
    }

    /// The stem without its ripples. Branches are planned against this so that labels do not reflow every frame.
    func restPoint(_ t: Double) -> CGPoint { point(t, wave: swell(t)) }

    /// The furthest the rippling stem strays from its resting shape.
    func sway(_ t: Double) -> Double { envelope(t) * (Metrics.rippleWeight + Metrics.shimmerWeight) }

    func path(from start: Double, to end: Double) -> Path {
        guard end - start > Metrics.minStemSpan else { return Path() }
        let steps = max(1, Int(((end - start) * Metrics.stemSegments).rounded(.up)))
        let points = (0...steps).map { point(start + (end - start) * Double($0) / Double(steps)) }
        return Path { $0.addLines(points) }
    }

    private func swell(_ t: Double) -> Double { sin(phase + 2 * .pi * waves * t) }
    private func envelope(_ t: Double) -> Double { band * Metrics.stemAmplitude * sin(.pi * t) }
    private func point(_ t: Double, wave: Double) -> CGPoint {
        CGPoint(x: width * (Metrics.stemInset + Metrics.stemSpan * t), y: band / 2 + envelope(t) * wave)
    }
}

/// What is settled about a word's branch before a place is found for its label.
private struct Bud {
    let index: Int
    let word: TimedWord
    let visual: WordVisual?
    let isLong: Bool
    let station: Double     // where along the stem it is rooted, 0...1
    let root: CGPoint       // on the resting stem
    let sproutsAt: Double   // song position
    let homeSide: Double    // -1 grows up, +1 grows down
    let wishFont: Double
    let labelAspect: Double // label width per point of font size
}

/// A word's branch as planned for the whole line. It depends on neither the song position nor the clock,
/// so a label keeps its place for as long as the line is on screen.
private struct Twig {
    let bud: Bud
    let side: Double
    let length: Double
    let lean: Double        // how far the tip sits to the side of the root
    let fontSize: Double    // while the word is sung; it shrinks once the word is over
    let labelBox: CGRect    // where the tip and label rest; with `probes`, only used to keep words apart
    let probes: [CGPoint]   // points along the resting branch
}

private struct Planner {
    let context: StyleContext
    let stem: Stem
    let first: Double, duration: Double

    /// Every word of the line gets its branch up front, sung or not, each steering clear of the labels before it.
    func twigs() -> [Twig] {
        let words = context.line.words
        let meanHold = words.reduce(0) { $0 + max(Metrics.minWordDuration, $1.end - $1.start) } / Double(max(1, words.count))
        let reference = context.settings.font.font(size: Metrics.measuringSize)
        return words.indices.reduce(into: [Twig]()) { placed, index in
            let bud = bud(index, meanHold: meanHold, reference: reference)
            var best: (twig: Twig, clash: Double)?
            for attempt in 0..<(2 * Metrics.triesPerSide) where (best?.clash ?? 1) > 0 {
                let twig = shape(bud, attempt: attempt)
                let clash = placed.reduce(0) { $0 + self.clash($1, twig) }
                if clash < (best?.clash ?? .infinity) { best = (twig, clash) }
            }
            if let best { placed.append(best.twig) }
        }
    }

    private func bud(_ index: Int, meanHold: Double, reference: NSFont) -> Bud {
        let word = context.line.words[index]
        let isLong = word.end - word.start >= Metrics.longHold * meanHold
        let middle = ((word.start + word.end) / 2 - first) / duration
        let station = min(max(middle, Metrics.stationRange.lowerBound), Metrics.stationRange.upperBound)
        let flipped = seededUnit(word.start, salt: Salt.side) >= Metrics.sideFlipThreshold
        let side: Double = index.isMultiple(of: 2) != flipped ? -1 : 1
        let visual = WordVisuals.shared.visual(for: word.text)
        let textWidth = (word.text.lowercased() as NSString).size(withAttributes: [.font: reference]).width
        // A line's first word would otherwise sprout ahead of the stem: wait until the head (eased 1-(1-p)²) has passed the root.
        let headArrives = first + duration * (1 - (1 - station).squareRoot())
        let activeFont = min(stem.band, stem.width * Metrics.widestBand) * Metrics.fontSize * Metrics.activeScale
        return Bud(index: index, word: word, visual: visual, isLong: isLong, station: station, root: stem.restPoint(station),
                   sproutsAt: max(word.start, headArrives), homeSide: side, wishFont: activeFont * (isLong ? Metrics.longScale : 1),
                   labelAspect: textWidth / Metrics.measuringSize + (visual == nil ? 0 : Metrics.iconScale + Metrics.iconSpacing))
    }

    private func shape(_ bud: Bud, attempt: Int) -> Twig {
        let seed = bud.word.start, root = bud.root, retry = UInt64(attempt) &* Salt.retryStride
        let side = attempt < Metrics.triesPerSide ? bud.homeSide : -bud.homeSide
        let room = (side < 0 ? root.y : stem.band - root.y) - stem.sway(bud.station) - stem.band * Metrics.edgeMargin
        let reach = Metrics.branchLengthFloor + Metrics.branchLengthSpread * seededUnit(seed, salt: Salt.length &+ retry)
        let wishLength = stem.band * Metrics.branchLength * reach
        // Branch and label share the room on their side of the stem, and shrink together when a big label would leave the band.
        let wishReach = wishLength + bud.wishFont * (Metrics.labelOffset + Metrics.lineHeight / 2)
        let widthFit = stem.width * (1 - 2 * Metrics.edgeMargin) / max(1, bud.labelAspect * bud.wishFont)
        let fit = min(1, widthFit, max(Metrics.minFit, (room - Metrics.labelGap) / wishReach))
        let fontSize = bud.wishFont * fit, length = wishLength * fit
        let labelWidth = bud.labelAspect * fontSize, labelHeight = Metrics.lineHeight * fontSize
        let margin = labelWidth / 2 + stem.band * Metrics.edgeMargin
        let wishX = root.x + stem.width * Metrics.branchLean * (2 * seededUnit(seed, salt: Salt.lean &+ retry) - 1)
        let tipX = min(max(wishX, margin), max(margin, stem.width - margin))
        let tip = CGPoint(x: tipX, y: root.y + side * length)
        let labelY = tip.y + side * (fontSize * Metrics.labelOffset + Metrics.labelGap)
        let padding = stem.band * Metrics.labelPadding
        let box = CGRect(x: tipX - labelWidth / 2, y: labelY - labelHeight / 2, width: labelWidth, height: labelHeight)
            .union(CGRect(origin: tip, size: .zero))
        let bend = branchBend(from: root, to: tip, lean: tipX - root.x, rise: side * length)
        let probes = Metrics.branchProbes.map { t in
            CGPoint(x: (1 - t) * (1 - t) * root.x + 2 * t * (1 - t) * bend.x + t * t * tip.x,
                    y: (1 - t) * (1 - t) * root.y + 2 * t * (1 - t) * bend.y + t * t * tip.y)
        }
        return Twig(bud: bud, side: side, length: length, lean: tipX - root.x, fontSize: fontSize,
                    labelBox: box.insetBy(dx: -padding, dy: -padding), probes: probes)
    }

    /// How badly two words get in each other's way: label area shared, plus branches running through labels.
    private func clash(_ a: Twig, _ b: Twig) -> Double {
        let shared = a.labelBox.intersection(b.labelBox)
        let crossings = a.probes.filter(b.labelBox.contains).count + b.probes.filter(a.labelBox.contains).count
        return (shared.isNull ? 0 : shared.width * shared.height) + Double(crossings) * Metrics.crossingPenalty * stem.band * stem.band
    }
}

/// A twig at this instant.
private struct Sprout {
    let twig: Twig
    let age: Double         // seconds since it sprouted
    let root: CGPoint, tip: CGPoint, bend: CGPoint
    let drawn: Double       // how much of the branch is out, 0...1
    let calm: Double        // 0 while the word is sung, 1 once it has settled into the background
    let showsLeaf: Bool
    let leafOpacity: Double

    var dim: Double { 1 + (Metrics.restingOpacity - 1) * calm }
    var fontSize: Double { twig.fontSize * (1 + (1 / Metrics.activeScale - 1) * calm) }
    var labelCentre: CGPoint {
        CGPoint(x: tip.x, y: tip.y + twig.side * (fontSize * Metrics.labelOffset + Metrics.labelGap))
    }

    init(twig: Twig, stem: Stem, position: Double, retract: Double) {
        let word = twig.bud.word, age = position - twig.bud.sproutsAt
        let grow = unit(age / max(Metrics.minGrowTime, word.end - word.start))
        let length = twig.length * (1 - Metrics.springAmount * ringing(age))
        let root = stem.point(twig.bud.station)
        let tip = CGPoint(x: root.x + twig.lean, y: root.y + twig.side * length)
        self.twig = twig
        self.age = age
        self.root = root
        self.tip = tip
        bend = branchBend(from: root, to: tip, lean: twig.lean, rise: twig.side * length)
        drawn = (1 - retract) * (1 - pow(1 - grow, 3))
        calm = smooth(unit((position - word.end - Metrics.activeTail) / Metrics.calmDuration))
        showsLeaf = drawn > Metrics.leafThreshold || (grow >= 1 && retract < Metrics.leafExitCutoff)
        // Leaves are gone halfway through the retract; fading them to nothing by then avoids a pop.
        leafOpacity = unit(1 - retract / Metrics.leafExitCutoff)
    }
}

/// Everything about one frame, worked out once and then drawn.
private struct BranchScene {
    let clock: Double
    let palette: Palette
    let stem: Stem
    let seed: Double        // the line's first word: one stem shape and glyph scatter per line
    let progress: Double    // through the line, 0...1
    let reach: Double       // eased progress: how far along the stem the head has travelled
    let exit: Double        // through the linger after the last word, 0...1
    let retract: Double     // eased exit
    let sprouts: [Sprout]
    let kick: CGSize

    init(context: StyleContext, size: CGSize) {
        let words = context.line.words, position = context.position
        let first = words.first?.start ?? position, lastEnd = words.last?.end ?? position
        let duration = max(Metrics.minLineDuration, lastEnd - first)
        let stem = Stem(seed: first, clock: context.clock, size: size)
        let progress = unit((position - first) / duration)
        // The retract fills exactly the time a finished line stays on screen.
        let exit = unit((position - lastEnd) / Timing.lineLinger)
        let retract = smooth(exit)
        self.stem = stem
        self.progress = progress
        self.exit = exit
        self.retract = retract
        clock = context.clock
        palette = Palette(context.settings)
        seed = first
        reach = 1 - (1 - progress) * (1 - progress)
        sprouts = Planner(context: context, stem: stem, first: first, duration: duration).twigs()
            .filter { position > $0.bud.sproutsAt }
            .map { Sprout(twig: $0, stem: stem, position: position, retract: retract) }
        kick = Self.kick(context)
    }

    /// The whole scene jolts a little, in a direction of its own, each time a word lands.
    private static func kick(_ context: StyleContext) -> CGSize {
        let words = context.line.words
        guard !words.isEmpty else { return .zero }
        let landed = words[min(words.count, max(1, context.line.shown)) - 1].start
        let angle = 2 * .pi * seededUnit(landed, salt: Salt.kick)
        let strength = context.band * Metrics.kickStrength * ringing(max(0, context.position - landed))
        return CGSize(width: strength * cos(angle), height: strength * sin(angle))
    }

    func draw(in graphics: inout GraphicsContext) {
        drawGlyphs(in: &graphics)
        graphics.stroke(stem.path(from: retract * reach, to: reach), with: .color(palette.text.opacity(Metrics.stemOpacity)),
                        style: StrokeStyle(lineWidth: Metrics.stemWidth, lineCap: .round, lineJoin: .round))
        for sprout in sprouts { draw(sprout, in: &graphics) }
        drawHead(in: &graphics)
    }

    private func drawGlyphs(in graphics: inout GraphicsContext) {
        let font = Font.system(size: stem.band * Metrics.glyphSize, weight: .light, design: .monospaced)
        for index in 0..<Metrics.glyphCount {
            let salt = Salt.glyph &+ UInt64(index) &* Salt.glyphStride
            let glyph = Metrics.glyphs[Int(seededUnit(seed, salt: salt) * Double(Metrics.glyphs.count)) % Metrics.glyphs.count]
            let across = seededUnit(seed, salt: salt &+ 1), down = seededUnit(seed, salt: salt &+ 2)
            let x = across + Metrics.glyphDriftX * sin(2 * .pi * across + clock * Metrics.glyphDriftXSpeed)
            let y = down + Metrics.glyphDriftY * sin(Metrics.glyphDriftYPhase * 2 * .pi * across + clock * Metrics.glyphDriftYSpeed)
            graphics.draw(Text(glyph).font(font).foregroundStyle(palette.text.opacity(Metrics.glyphOpacity)),
                          at: CGPoint(x: stem.width * x, y: stem.band * y))
        }
    }

    private func draw(_ sprout: Sprout, in graphics: inout GraphicsContext) {
        let branch = Path { $0.move(to: sprout.root); $0.addQuadCurve(to: sprout.tip, control: sprout.bend) }
        graphics.stroke(branch.trimmedPath(from: 0, to: sprout.drawn), with: .color(palette.text.opacity(Metrics.branchOpacity * sprout.dim)),
                        style: StrokeStyle(lineWidth: Metrics.branchWidth, lineCap: .round))
        guard sprout.showsLeaf else { return }
        let lit = 1 - sprout.calm
        let diameter = Metrics.tipDiameter * (1 + Metrics.tipPop * exp(-sprout.age / Metrics.tipPopDecay))
        graphics.drawLayer { layer in
            layer.opacity = sprout.leafOpacity * sprout.dim
            // A settled leaf has no glow, and a blur pass per leaf per frame is not free.
            if lit > 0 { layer.addFilter(.shadow(color: palette.highlight.opacity(lit), radius: Metrics.tipGlow)) }
            layer.fill(disc(at: sprout.tip, diameter: diameter), with: .color(palette.highlight.mix(with: palette.text, by: sprout.calm)))
        }
        guard lit > 0 else { return }
        let beat = (sprout.age * Metrics.pulseRate).truncatingRemainder(dividingBy: 1)
        let ring = palette.highlight.opacity(Metrics.pulseOpacity * (1 - beat) * lit * sprout.leafOpacity)
        graphics.stroke(disc(at: sprout.tip, diameter: Metrics.tipDiameter * (1 + Metrics.pulseGrowth * beat)), with: .color(ring),
                        lineWidth: Metrics.pulseWidth)
    }

    private func drawHead(in graphics: inout GraphicsContext) {
        let arrival = min(1, Metrics.headFadeInRate * progress)
        for step in 1...Metrics.trailCount {
            let behind = reach - Metrics.trailSpacing * Double(step)
            guard behind > retract * reach else { continue }
            graphics.fill(disc(at: stem.point(behind), diameter: Metrics.trailDiameter / Double(step).squareRoot()),
                          with: .color(palette.highlight.opacity(arrival * Metrics.trailOpacity / Double(step))))
        }
        let head = stem.point(reach)
        let pulse = 1 + Metrics.headPulse * (0.5 + 0.5 * sin(clock * Metrics.headPulseSpeed))
        graphics.drawLayer { layer in
            // The head dims as the line retracts, so it does not blink out when the overlay goes blank.
            layer.opacity = arrival * (1 - retract * retract)
            layer.addFilter(.shadow(color: palette.highlight.opacity(Metrics.headGlowOpacity), radius: Metrics.headGlowRadius * pulse))
            layer.addFilter(.shadow(color: palette.highlight.opacity(Metrics.headHaloOpacity), radius: Metrics.headHaloRadius * pulse))
            layer.fill(disc(at: head, diameter: Metrics.headDiameter * pulse), with: .color(palette.highlight))
        }
        guard exit > 0 else { return }
        let spread = 1 - (1 - retract) * (1 - retract)
        graphics.stroke(disc(at: head, diameter: Metrics.headDiameter + Metrics.exitRingGrowth * spread),
                        with: .color(palette.highlight.opacity(1 - exit)), lineWidth: Metrics.exitRingWidth)
    }
}
