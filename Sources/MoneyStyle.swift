import SwiftUI

/// Money: the song as a payment feed. Every lyric line is cut into short chunks and each chunk arrives at the
/// bottom of a 402-point-wide feed as a cash bubble, a black island platter, a wallet card, a pay row, a map
/// row or a plain message bubble, pushing the older ones up under a top fade. Words spring up one by one as
/// they are sung. `MoneyPlan.swift` decides what the feed contains, `MoneyFeed.swift` where everything is this
/// instant, `MoneyMapPictures.swift` fetches the map stills; this file draws it.
/// Nothing is animated by SwiftUI: each frame is a closed-form function of the playback position and the clock.
struct MoneyStyle: View {
    let context: StyleContext
    /// Watched so that a paused frame is drawn again when a map picture arrives.
    @ObservedObject var pictures = MoneyMapPictures.shared

    var body: some View {
        let scene = MoneyScene(context: context, pictures: pictures)
        Canvas { graphics, _ in scene?.draw(in: graphics) }
            .frame(width: context.canvas.width, height: context.band)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: Look.topFade)],
                                 startPoint: .top, endPoint: .bottom))
            .opacity(scene?.feed.presence ?? 0)
            .shadow(color: .black.opacity(Look.shadowOpacity), radius: Look.shadowRadius, y: Look.shadowY)
            .modifier(Streak(blur: scene?.motionBlur ?? 0))
    }
}

/// The blur of a fast scroll. Left out altogether while the feed is still: a blur of no radius would still
/// send the whole band through an offscreen pass on every frame.
private struct Streak: ViewModifier {
    let blur: CGFloat

    func body(content: Content) -> some View {
        if blur > 0 {
            content.blur(radius: blur)
        } else {
            content
        }
    }
}

// MARK: - Constants (feed points unless noted)

private enum Look {
    static let topFade = 0.12                   // of the band
    static let shadowOpacity = 0.32, shadowRadius: CGFloat = 14, shadowY: CGFloat = 5
    // Stands in for a vertical motion blur, which needs a Metal shader this project cannot compile:
    // a faint ordinary blur while the feed scrolls fast.
    static let maxStreak = 26.0, streakPerTravel = 0.9, minStreak = 0.75, blurPerStreak = 0.04
    static let squashY = 0.7, minSoft = 0.05, growingTolerance: CGFloat = 0.01
    static let cashFill = Color.white.opacity(0.07)
    static let messageBlue = Color(red: 0, green: 0.533, blue: 1), messageGrey = Color(red: 0.149, green: 0.149, blue: 0.161)
    static let sheet = Color(red: 0.110, green: 0.110, blue: 0.118), secondary = Color(white: 0.6)
    static let bubbleRadius: CGFloat = 20, islandRadius: CGFloat = 48, cardRadius: CGFloat = 12, mapRadius: CGFloat = 22
    static let payRadiusShare: CGFloat = 0.3
    static let rim = Gradient(stops: [.init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0.07), location: 0.5),
                                      .init(color: .white.opacity(0.14), location: 1)])
    static let echoReach = 16.0, echoMinWidth = 0.6, echoWidth = 1.6, echoFadePower = 1.5, echoWhiteShare = 0.55
    static let messageInset = CGPoint(x: 14, y: 10)
    static let receipt = "Delivered", receiptSize: CGFloat = 11, receiptOpacity = 0.62
    static let rowHeight: CGFloat = 20          // header and caption rows are one line, clipped
}

private enum Reveal {
    static let response = 0.30, damping = 0.46
    static let wobbleDecay = 0.11, wobbleSpeed = 22.0
    static let releaseRate = 4.0, holdRamp = 0.08
    static let longGain = 1.7, longLean = 1.3
    static let swell = 0.07, dip = 0.5, minScale = 0.05
    static let rise = 0.7                       // of the line height
    static let lift = 1.2, leanDegrees = 10.0, leanWidth: CGFloat = 44
    static let fadeSpan = 0.1, fadeIn = 0.06, blur = 2.5
}

private enum Pop {
    static let dip = 0.45, fade = 0.08
    static let settledAge = 1_000.0             // "long ago": far past every decay, yet finite
}

private enum Tail {
    // Drawn for an incoming bubble around its bottom-left corner (y grows downwards), mirrored for outgoing.
    static let root = CGPoint(x: 17, y: -1.5), tip = CGPoint(x: -6.5, y: 0.6), shoulder = CGPoint(x: 4.5, y: -12)
    static let belly = CGPoint(x: 6, y: 2.6), hollow = CGPoint(x: 2.8, y: -2.2)
    static let anchor = CGPoint(x: 10, y: -5)
    static let minScale = 0.01
}

private enum Cash {
    static let header = CGPoint(x: 16, y: 25), headerSize: CGFloat = 17
    static let status = CGPoint(x: 26, y: 25)   // from the top-right corner
    static let iconSize: CGFloat = 17, iconOpacity = 0.85, checkSize: CGFloat = 20
    static let checkDegrees = 16.0, checkDip = 0.55
    static let textTop: CGFloat = 46
}

private enum Island {
    static let icon = CGPoint(x: 47, y: 40), iconSize: CGFloat = 28
    static let textX: CGFloat = 79, textTop: CGFloat = 18, minText: CGFloat = 44
    static let inset: CGFloat = 18, barHeight: CGFloat = 44
    static let baseOpacity = 0.18, fillOpacity = 0.26, minDuration = 0.01
    static let labelSize: CGFloat = 15, labelKerning: CGFloat = -0.3, labelWhite = 0.3, doneDip = 0.3
}

private enum Card {
    static let paper = Gradient(colors: [Color(white: 0.995), Color(white: 0.94)])
    /// Centre and radius of each colour bloom, as fractions of the card's width (x, r) and height (y).
    static let blooms: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [(0.48, 0.36, 0.44), (0.88, 0.66, 0.42), (0.20, 0.90, 0.40),
                                                                 (0.06, 0.42, 0.28), (0.62, 1.04, 0.27)]
    static let bloomStops: [(opacity: Double, location: CGFloat)] = [(0.9, 0), (0.68, 0.36), (0.25, 0.7), (0, 1)]
    static let bloomDelay = 0.06, bloomSpread = 0.6, bloomRise = 0.5, minDuration = 0.3, bloomStartRadius = 0.55
    static let fallbackCount = 4, fallbackStride = 2, fallbackWhite = 0.28
    static let highlight = Gradient(colors: [.white.opacity(0.92), .white.opacity(0)])
    static let highlightRight: CGFloat = 133.2, highlightLeft: CGFloat = 88.8
    static let mark = "music.note", markAt = CGPoint(x: 39, y: 43), markSize: CGFloat = 35
    static let iconAt = CGPoint(x: 320, y: 179), iconSize: CGFloat = 33
    // An engraved glyph is a thin contour: the glyph minus itself shrunk by these shifts.
    static let erosion: [CGSize] = [CGSize(width: 0.8, height: 0), CGSize(width: -0.8, height: 0),
                                    CGSize(width: 0, height: 0.8), CGSize(width: 0, height: -0.8)]
    static let litOffset = CGSize(width: -0.4, height: -0.5), litOpacity = 0.95
    static let shadeOffset = CGSize(width: 0.95, height: 1.15), shadeOpacity = 0.34, shadeBlur: CGFloat = 0.25
    static let metal = Gradient(colors: [Color(white: 0.98), Color(white: 0.66), Color(white: 0.9)]), metalOpacity = 0.85
    static let textX: CGFloat = 26, textMidY: CGFloat = 136.03
    static let ink = Color(white: 0.13).opacity(0.82), inkGlow = Color.white.opacity(0.6)
    static let inkGlowRadius: CGFloat = 0.2, inkGlowY: CGFloat = 0.7
    static let edge = Gradient(colors: [0.97, 0.7, 1, 0.62, 0.9, 0.72, 0.97].map { Color(white: $0) })
    static let edgeDegrees = -58.0, edgeWidth: CGFloat = 0.6
    static let innerEdgeInset: CGFloat = 0.95, innerEdgeWidth: CGFloat = 0.35, innerEdgeOpacity = 0.32
}

private enum Pay {
    static let header = CGPoint(x: 16, y: 28), headerSize: CGFloat = 15, headerTrailingRoom: CGFloat = 94
    static let text = CGPoint(x: 16, y: 40)
    static let disc = CGPoint(x: 37, y: -7)     // left of the right edge, above the middle
    static let radius: CGFloat = 15, ringWidth: CGFloat = 2, arrowSize: CGFloat = 13
    static let pulseEvery = 1.6, pulseLength = 0.25, pulseGrowth = 0.1
    static let fillResponse = 0.34, fillDamping = 0.42, checkSize: CGFloat = 15
    static let done = "Done", doneSize: CGFloat = 14, doneBelow: CGFloat = 26, doneFadeFrom = 0.08, doneFadeSpan = 0.2
}

private enum MapRow {
    static let zoom = 1.7, zoomSettle = 0.32, zoomDelay = 0.05, zoomResponse = 0.7, zoomDamping = 0.6
    static let drift = 0.06, driftSpan = 10.0
    static let panX = 0.10, panY = 0.08         // of the picture's width and height, either way
    static let blur = 9.0, blurSpan = 0.4
    static let showFrom = 0.5, showSpan = 0.35  // of the item's growth in width
    static let rim = Gradient(colors: [.white.opacity(0.34), .white.opacity(0.07)])
    static let caption = "Maps", captionSize: CGFloat = 9.5, captionOpacity = 0.72, captionInset = CGPoint(x: 10, y: 7)
    static let pinDelay = 0.25, pinResponse = 0.42, pinDamping = 0.45, pinDrop: CGFloat = 46, pinFade = 0.08
    static let pinTipBelowCentre: CGFloat = 22, pinHeadRadius: CGFloat = 15, pinHeadAboveTip: CGFloat = 30
    static let pinNeck = CGSize(width: 8, height: 17.5)
    static let pinShadow = 0.4, pinShadowRadius: CGFloat = 3, pinShadowY: CGFloat = 2, pinIconSize: CGFloat = 14
    static let rippleLife = 0.6, rippleFrom: CGFloat = 6, rippleGrowth: CGFloat = 20, rippleFlatness: CGFloat = 0.45
    static let rippleOpacity = 0.7, rippleWidth: CGFloat = 1.5
    static let textInset = CGPoint(x: 14, y: 10), footerAboveBottom: CGFloat = 16
    static let placeSize: CGFloat = 12, placeFadeFrom = 0.3, placeFadeSpan = 0.3, payRoom: CGFloat = 60
    static let paySize: CGFloat = 15
}

private enum Pill {
    static let response = 0.36, damping = 0.5, breath = 0.025, breathSpeed = 3.1
    static let bubbleDegrees = 9.0, platterDegrees = 3.15, fade = 0.08
    // Typing bubble: two small circles trail off its own bottom corner.
    static let knuckle = CGPoint(x: 4, y: -5), knuckleRadius: CGFloat = 6
    static let fingertip = CGPoint(x: -3.5, y: 2.5), fingertipRadius: CGFloat = 2.75
    static let dots = 3, dotSize: CGFloat = 8.5, dotSpacing: CGFloat = 13, dotBob: CGFloat = 2.4
    static let dotSpeed = 5 * Double.pi / 3, dotPhase = 0.85, dotDim = 0.42, dotGlow = 0.5
    static let iconX: CGFloat = 22, iconSize: CGFloat = 15
    static let bars = 5, barWidth: CGFloat = 3, barSpacing: CGFloat = 5.5, barInset: CGFloat = 18
    static let barMin: CGFloat = 5, barSwing: CGFloat = 9, barSpeed = 5.2, barPhase = 1.1
    static let label = "Pay", labelSize: CGFloat = 17
}

private enum Salt {
    static let bloomStart: UInt64 = 0xD021, bloomTurn: UInt64 = 0xD022, panX: UInt64 = 0xD023, panY: UInt64 = 0xD024
}

// MARK: - Small helpers

private extension GraphicsContext {
    /// A copy rotated and scaled about `pivot`.
    func posed(about pivot: CGPoint, degrees: Double = 0, scaleX: CGFloat = 1, scaleY: CGFloat = 1) -> GraphicsContext {
        var copy = self
        copy.translateBy(x: pivot.x, y: pivot.y)
        copy.rotate(by: .degrees(degrees))
        copy.scaleBy(x: scaleX, y: scaleY)
        copy.translateBy(x: -pivot.x, y: -pivot.y)
        return copy
    }

    func faded(_ amount: Double) -> GraphicsContext {
        var copy = self
        copy.opacity = opacity * amount
        return copy
    }

    func label(_ text: Text, size: CGFloat, weight: Font.Weight, color: Color) -> ResolvedText {
        resolve(text.font(.system(size: size, weight: weight)).foregroundStyle(color))
    }

    func symbol(_ name: String, size: CGFloat, weight: Font.Weight, color: Color) -> ResolvedText {
        label(Text(Image(systemName: name)), size: size, weight: weight, color: color)
    }
}

private extension MoneySlot {
    var isGrowing: Bool {
        abs(rect.width - rest.width) > Look.growingTolerance || abs(rect.height - rest.height) > Look.growingTolerance
    }

    /// The pill the item grew out of, pinned to the top of its frame.
    var pillRect: CGRect {
        let size = MoneyPill.size(for: item.kind)
        let x = item.kind.isBubble ? (item.outgoing ? rect.maxX - size.width : rect.minX) : rect.midX - size.width / 2
        return CGRect(x: x, y: rect.minY, width: size.width, height: size.height)
    }
}

private func disc(at centre: CGPoint, radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
}

/// A word's picture, and how long ago it turned up.
private struct Glyph {
    let name: String
    let age: Double
}

// MARK: - The scene

private struct MoneyScene {
    let context: StyleContext
    let geometry: MoneyGeometry
    let feed: MoneyFeed
    let energy: Double

    private var position: Double { context.position }
    private var clock: Double { context.clock }

    @MainActor
    init?(context: StyleContext, pictures: MoneyMapPictures) {
        guard !context.lyrics.words.isEmpty,
              let geometry = MoneyGeometry(canvas: context.canvas, band: context.band, textScale: context.settings.textScale) else { return nil }
        let song = MoneyPlan.cached(for: context.lyrics), plan = song.plan
        pictures.prepare(mapStarts: plan.mapStarts, position: context.position)
        let energy: Double = context.settings.reduceMotion ? 0 : 1
        self.context = context
        self.geometry = geometry
        self.energy = energy
        feed = MoneyFeed(plan: plan, geometry: geometry, position: context.position, energy: energy) { item, hasComeUp in
            let picture = pictures.picture(for: item.seed)
            let row = MoneyPictureLatch.Row(start: item.start, canvas: context.canvas)
            return song.pictured.holds(row, isOnScreen: hasComeUp, isReady: picture != nil) ? .pictured(picture) : .island
        }
    }

    /// Screen points of blur while the feed scrolls fast.
    var motionBlur: CGFloat {
        let streak = min(Look.maxStreak, geometry.scale * abs(feed.travel) * Look.streakPerTravel)
        return streak > Look.minStreak ? streak * Look.blurPerStreak : 0
    }

    func draw(in graphics: GraphicsContext) {
        let unit = geometry.scale * feed.zoom
        var canvas = graphics
        canvas.translateBy(x: context.canvas.width / 2 - MoneyGeometry.feedWidth / 2 * unit + geometry.scale * feed.nudge.width,
                           y: geometry.scale * feed.nudge.height + (1 - feed.zoom) * geometry.scale * geometry.bottomY)
        canvas.scaleBy(x: unit, y: unit)
        feed.slots.forEach { draw($0, in: canvas) }
        if let lead = feed.lead { drawLead(lead, in: canvas) }
        if let receipt = feed.receipt { drawReceipt(receipt, in: canvas) }
    }

    // MARK: Slots

    private func draw(_ slot: MoneySlot, in graphics: GraphicsContext) {
        let item = slot.item, rect = slot.rect
        let pivot = CGPoint(x: item.kind.isBubble ? (item.outgoing ? rect.maxX : rect.minX) : rect.midX, y: rect.maxY)
        var posed = graphics.posed(about: pivot, degrees: slot.tiltDegrees, scaleX: 1 + slot.squash, scaleY: 1 - Look.squashY * slot.squash)
        drawEcho(slot, in: posed)
        guard slot.soft > Look.minSoft || slot.alpha < 1 else { return drawBody(slot, in: posed) }
        posed.opacity = slot.alpha
        if slot.soft > Look.minSoft { posed.addFilter(.blur(radius: slot.soft)) }
        posed.drawLayer { drawBody(slot, in: $0) }
    }

    private func drawEcho(_ slot: MoneySlot, in graphics: GraphicsContext) {
        guard let echo = slot.echo else { return }
        let item = slot.item, fade = 1 - echo.progress
        let grow = Look.echoReach * (1 - fade * fade * fade)
        let isTinted = item.kind == .island || item.kind == .pay || item.kind == .map
        let isBlue = item.kind == .message && item.outgoing
        let colour = isTinted ? item.tint : isBlue ? Look.messageBlue : .white
        let opacity = echo.strength * pow(fade, Look.echoFadePower) * (isTinted || isBlue ? 1 : Look.echoWhiteShare)
        let ring = RoundedRectangle(cornerRadius: radius(of: slot) + grow, style: .continuous)
            .path(in: slot.rect.insetBy(dx: -grow, dy: -grow))
        graphics.stroke(ring, with: .color(colour.opacity(opacity)), lineWidth: Look.echoMinWidth + Look.echoWidth * fade)
    }

    private func radius(of slot: MoneySlot) -> CGFloat {
        let height = slot.rect.height
        switch slot.item.kind {
        case .cash, .message: return min(height / 2, Look.bubbleRadius)
        case .island: return min(height / 2, Look.islandRadius)
        case .card: return min(height / 2, Look.cardRadius * geometry.cardScale)
        case .pay: return min(height / 2, Look.payRadiusShare * height, Look.islandRadius)
        case .map: return min(height / 2, Look.mapRadius)
        }
    }

    private func drawBody(_ slot: MoneySlot, in graphics: GraphicsContext) {
        let item = slot.item
        let outline = RoundedRectangle(cornerRadius: radius(of: slot), style: item.kind.isBubble ? .circular : .continuous).path(in: slot.rect)
        drawBackground(slot, outline: outline, in: graphics)
        // The content sits where it will rest; the growing frame uncovers it.
        var content = graphics
        if slot.isGrowing { content.clip(to: outline) }
        let frame = CGRect(x: item.kind.isBubble ? slot.rect.minX : slot.rest.minX, y: slot.rest.minY,
                           width: slot.rest.width, height: slot.rest.height)
        switch item.kind {
        case .cash: drawCash(item, frame: frame, in: content)
        case .island: drawIsland(item, frame: frame, in: content)
        case .card: drawCard(slot, outline: outline, in: graphics)
        case .pay: drawPay(item, frame: frame, in: content)
        case .map: drawMap(slot, frame: frame, in: content)
        case .message:
            drawWords(of: item, at: CGPoint(x: frame.minX + Look.messageInset.x, y: frame.minY + Look.messageInset.y), color: .white, in: content)
        }
        drawHandoff(slot, outline: outline, in: graphics)
    }

    private func drawBackground(_ slot: MoneySlot, outline: Path, in graphics: GraphicsContext) {
        let item = slot.item
        switch item.kind {
        case .cash:
            // One shape, so the translucent fill does not double up where the tail meets the bubble.
            graphics.fill(outline.union(tail(of: slot)), with: .color(Look.cashFill))
            drawRim(around: slot.rect, radius: radius(of: slot), in: graphics)
        case .message:
            graphics.fill(outline.union(tail(of: slot)), with: .color(item.outgoing ? Look.messageBlue : Look.messageGrey))
        case .island:
            graphics.fill(outline, with: .color(.black))
        case .pay, .map:
            graphics.fill(outline, with: .color(Look.sheet))
            drawRim(around: slot.rect, radius: radius(of: slot), in: graphics)
        case .card:
            break
        }
    }

    private func drawRim(around rect: CGRect, radius: CGFloat, in graphics: GraphicsContext) {
        let inset = rect.insetBy(dx: 0.5, dy: 0.5)
        guard inset.width > 0, inset.height > 0 else { return }
        graphics.stroke(RoundedRectangle(cornerRadius: max(radius - 0.5, 0), style: .continuous).path(in: inset),
                        with: .linearGradient(Look.rim, startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
    }

    /// The little hook under a bubble's own bottom corner.
    private func tail(of slot: MoneySlot) -> Path {
        guard slot.tail > Tail.minScale else { return Path() }
        let hook = Path { path in
            path.move(to: Tail.root)
            path.addQuadCurve(to: Tail.tip, control: Tail.belly)
            path.addQuadCurve(to: Tail.shoulder, control: Tail.hollow)
            path.closeSubpath()
        }
        let outgoing = slot.item.outgoing
        let grow = CGAffineTransform(translationX: Tail.anchor.x, y: Tail.anchor.y).scaledBy(x: slot.tail, y: slot.tail)
            .translatedBy(x: -Tail.anchor.x, y: -Tail.anchor.y)
        let place = CGAffineTransform(translationX: outgoing ? slot.rect.maxX : slot.rect.minX, y: slot.rect.maxY)
            .scaledBy(x: outgoing ? -1 : 1, y: 1)
        return hook.applying(grow.concatenating(place))
    }

    /// For a moment after birth the lead pill's contents fade out over the item (on black, for platters).
    private func drawHandoff(_ slot: MoneySlot, outline: Path, in graphics: GraphicsContext) {
        guard slot.handoff > 0 else { return }
        let layer = graphics.faded(slot.handoff)
        if !slot.item.kind.isBubble { layer.fill(outline, with: .color(.black)) }
        drawPillContents(of: slot.item, in: slot.pillRect, graphics: layer)
    }

    // MARK: Words

    /// Sung words spring up one by one; a word that has not started is not drawn at all.
    private func drawWords(of item: MoneyItem, at origin: CGPoint, color: Color, in graphics: GraphicsContext) {
        let text = item.text, type = text.type
        func resolved(_ string: String) -> GraphicsContext.ResolvedText {
            graphics.resolve(Text(string).font(type.font).kerning(type.kerning).foregroundStyle(color))
        }
        guard position < text.settledAt else {
            for line in text.lines {
                graphics.draw(resolved(line.text), at: CGPoint(x: origin.x + line.x, y: origin.y + line.y + type.lineHeight / 2), anchor: .leading)
            }
            return
        }
        for word in text.words {
            guard position >= word.start else { break }
            let centre = CGPoint(x: origin.x + word.x + word.width / 2, y: origin.y + word.y + type.lineHeight / 2)
            if position >= word.lingerEnd {
                graphics.draw(resolved(word.text), at: centre)
            } else {
                drawLanding(word, resolved(word.text), at: centre, lineHeight: type.lineHeight, in: graphics)
            }
        }
    }

    private func drawLanding(_ word: MoneyWord, _ text: GraphicsContext.ResolvedText, at centre: CGPoint, lineHeight: CGFloat,
                             in graphics: GraphicsContext) {
        let age = position - word.start
        let risen = MoneyMath.spring(age, response: Reveal.response, damping: Reveal.damping)
        let wobble = exp(-age / Reveal.wobbleDecay) * cos(Reveal.wobbleSpeed * age)
        let released = MoneyMath.smoothstep((position - word.end) * Reveal.releaseRate)
        let hold = (1 - released) * min(age / Reveal.holdRamp, 1)
        let gain = word.isLong ? Reveal.longGain : 1, lean = word.isLong ? Reveal.longLean : 1
        let scale = (1 + Reveal.swell * gain * hold * energy) * max(Reveal.minScale, 1 - Reveal.dip * gain * wobble * energy)
        let rise = Reveal.rise * lineHeight * (1 - risen) - Reveal.lift * hold * energy
        let degrees = Reveal.leanDegrees * word.sign * energy * wobble * min(Reveal.leanWidth / max(word.width, 1), 1) * lean
        var layer = graphics
        if age < Reveal.fadeSpan {
            let blur = Reveal.blur * (1 - age / Reveal.fadeSpan)
            layer.opacity = graphics.opacity * min(age / Reveal.fadeIn, 1)
            if blur > Look.minSoft { layer.addFilter(.blur(radius: blur)) }
        }
        layer.translateBy(x: centre.x, y: centre.y + rise)
        layer.rotate(by: .degrees(degrees))
        layer.scaleBy(x: scale, y: scale)
        layer.draw(text, at: .zero)
    }

    /// The picture of the latest sung word that has one (SF Symbols only).
    private func wordGlyph(of item: MoneyItem) -> Glyph? {
        for word in item.text.words.reversed() where word.start <= position {
            if case .symbol(let name) = WordVisuals.shared.visual(for: word.text) { return Glyph(name: name, age: position - word.start) }
        }
        return nil
    }

    private func glyph(of item: MoneyItem) -> Glyph { wordGlyph(of: item) ?? Glyph(name: item.icon, age: Pop.settledAge) }

    private func drawPopping(_ text: GraphicsContext.ResolvedText, at centre: CGPoint, age: Double, in graphics: GraphicsContext) {
        let scale = 1 - Pop.dip * energy * MoneyMath.ring(age)
        graphics.posed(about: centre, scaleX: scale, scaleY: scale).faded(MoneyMath.clamp(age / Pop.fade)).draw(text, at: centre)
    }

    // MARK: Cash

    private func drawCash(_ item: MoneyItem, frame: CGRect, in graphics: GraphicsContext) {
        let header = graphics.label(Text("\(Image(systemName: "dollarsign.circle.fill")) Cash"), size: Cash.headerSize, weight: .semibold, color: .white)
        graphics.draw(header, at: CGPoint(x: frame.minX + Cash.header.x, y: frame.minY + Cash.header.y), anchor: .leading)
        let status = CGPoint(x: frame.maxX - Cash.status.x, y: frame.minY + Cash.status.y)
        let sinceEnd = position - item.end
        if sinceEnd >= 0 {
            let wobble = energy * MoneyMath.ring(sinceEnd)
            let check = graphics.symbol("checkmark.circle.fill", size: Cash.checkSize, weight: .semibold, color: MoneyPalette.green)
            graphics.posed(about: status, degrees: Cash.checkDegrees * wobble, scaleX: 1 - Cash.checkDip * wobble, scaleY: 1 - Cash.checkDip * wobble)
                .draw(check, at: status)
        } else if let glyph = wordGlyph(of: item) {
            drawPopping(graphics.symbol(glyph.name, size: Cash.iconSize, weight: .semibold, color: .white.opacity(Cash.iconOpacity)),
                        at: status, age: glyph.age, in: graphics)
        }
        drawWords(of: item, at: CGPoint(x: frame.midX - item.text.size.width / 2, y: frame.minY + Cash.textTop), color: .white, in: graphics)
    }

    // MARK: Island

    private func drawIsland(_ item: MoneyItem, frame: CGRect, in graphics: GraphicsContext) {
        let glyph = glyph(of: item)
        drawPopping(graphics.symbol(glyph.name, size: Island.iconSize, weight: .medium, color: item.tint),
                    at: CGPoint(x: frame.minX + Island.icon.x, y: frame.minY + Island.icon.y), age: glyph.age, in: graphics)
        let slack = max(item.text.size.height, Island.minText) - item.text.size.height
        drawWords(of: item, at: CGPoint(x: frame.minX + Island.textX, y: frame.minY + Island.textTop + slack / 2), color: .white, in: graphics)

        let bar = CGRect(x: frame.minX + Island.inset, y: frame.maxY - Island.inset - Island.barHeight,
                         width: frame.width - 2 * Island.inset, height: Island.barHeight)
        let capsule = Capsule().path(in: bar)
        let progress = MoneyMath.clamp((position - item.start) / max(item.end - item.start, Island.minDuration))
        graphics.fill(capsule, with: .color(item.tint.opacity(Island.baseOpacity)))
        var filling = graphics
        filling.clip(to: capsule)
        filling.fill(Path(CGRect(x: bar.minX, y: bar.minY, width: bar.width * progress, height: bar.height)),
                     with: .color(item.tint.opacity(Island.fillOpacity)))
        drawIslandLabel(item, at: CGPoint(x: bar.midX, y: bar.midY), in: graphics)
    }

    /// The song clock while the chunk is sung, then "Done".
    private func drawIslandLabel(_ item: MoneyItem, at centre: CGPoint, in graphics: GraphicsContext) {
        let sinceEnd = position - item.end
        // A player gone wrong can report a position that is no number, or an infinite one; a plain conversion would trap.
        let seconds = max(0, Int(exactly: position.rounded(.down)) ?? 0)
        let counter = "\(seconds / 60):" + String(format: "%02d", seconds % 60)
        let text = sinceEnd >= 0 ? Text("\(Image(systemName: "checkmark")) Done") : Text("\(Image(systemName: "waveform")) \(counter)")
        let label = graphics.resolve(text.font(.system(size: Island.labelSize, weight: .medium)).monospacedDigit()
            .kerning(Island.labelKerning).foregroundStyle(item.tint.mix(with: .white, by: Island.labelWhite)))
        let scale = sinceEnd >= 0 ? 1 - Island.doneDip * energy * MoneyMath.ring(sinceEnd) : 1
        graphics.posed(about: centre, scaleX: scale, scaleY: scale).draw(label, at: centre)
    }

    // MARK: Card

    /// Drawn in the card's own 370 × 223 space, stretched onto the frame while it grows.
    private func drawCard(_ slot: MoneySlot, outline: Path, in graphics: GraphicsContext) {
        let item = slot.item, size = MoneyGeometry.cardSize, bounds = Path(CGRect(origin: .zero, size: size))
        var face = graphics
        face.clip(to: outline)
        face.translateBy(x: slot.rect.minX, y: slot.rect.minY)
        face.scaleBy(x: slot.rect.width / size.width, y: slot.rect.height / size.height)
        face.fill(bounds, with: .linearGradient(Card.paper, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
        drawBlooms(of: item, over: bounds, in: face)
        face.fill(bounds, with: .radialGradient(Card.highlight, center: CGPoint(x: size.width, y: 0), startRadius: 0, endRadius: Card.highlightRight))
        face.fill(bounds, with: .radialGradient(Card.highlight, center: .zero, startRadius: 0, endRadius: Card.highlightLeft))
        drawEngraved(Card.mark, size: Card.markSize, at: Card.markAt, age: Pop.settledAge, in: face)
        let glyph = glyph(of: item)
        drawEngraved(glyph.name, size: Card.iconSize, at: Card.iconAt, age: glyph.age, in: face)
        var inked = face
        inked.addFilter(.shadow(color: Card.inkGlow, radius: Card.inkGlowRadius, x: 0, y: Card.inkGlowY))
        drawWords(of: item, at: CGPoint(x: Card.textX, y: Card.textMidY - item.text.size.height / 2), color: Card.ink, in: inked)

        let centre = CGPoint(x: slot.rect.midX, y: slot.rect.midY)
        graphics.stroke(outline, with: .conicGradient(Card.edge, center: centre, angle: .degrees(Card.edgeDegrees)), lineWidth: Card.edgeWidth)
        let inner = slot.rect.insetBy(dx: Card.innerEdgeInset, dy: Card.innerEdgeInset)
        guard inner.width > 0, inner.height > 0 else { return }
        graphics.stroke(RoundedRectangle(cornerRadius: max(radius(of: slot) - Card.innerEdgeInset, 0), style: .continuous).path(in: inner),
                        with: .color(.white.opacity(Card.innerEdgeOpacity)), lineWidth: Card.innerEdgeWidth)
    }

    /// Soft colour clouds from the album cover that bloom one after another while the chunk is sung.
    private func drawBlooms(of item: MoneyItem, over bounds: Path, in face: GraphicsContext) {
        let colours = bloomColours(for: item), size = MoneyGeometry.cardSize
        let duration = max(item.end - item.start, Card.minDuration)
        for (index, colour) in colours.enumerated() {
            let order = colours.count > 1 ? Double(index) / Double(colours.count - 1) : 0
            let shown = MoneyMath.smoothstep((position - item.start - Card.bloomDelay - Card.bloomSpread * duration * order) / Card.bloomRise)
            guard shown > 0 else { continue }
            let spot = Card.blooms[index]
            let gradient = Gradient(stops: Card.bloomStops.map { .init(color: colour.opacity($0.opacity * shown), location: $0.location) })
            face.fill(bounds, with: .radialGradient(gradient, center: CGPoint(x: spot.x * size.width, y: spot.y * size.height), startRadius: 0,
                                                    endRadius: spot.r * size.width * (Card.bloomStartRadius + (1 - Card.bloomStartRadius) * shown)))
        }
    }

    private func bloomColours(for item: MoneyItem) -> [Color] {
        let art = (context.artworkPalette ?? []).prefix(Card.blooms.count).map { Color(nsColor: $0) }
        let fallback = (0..<Card.fallbackCount).map {
            MoneyPalette.pick(item.seed, salt: Salt.bloomStart, offset: Card.fallbackStride * $0).mix(with: .white, by: Card.fallbackWhite)
        }
        let colours = art.isEmpty ? fallback : art
        let turn = Int(seededUnit(item.seed, salt: Salt.bloomTurn) * Double(colours.count)) % colours.count
        return Array(colours[turn...] + colours[..<turn])
    }

    /// A glyph pressed into the card: a thin contour with a light edge up-left and a shadow down-right.
    private func drawEngraved(_ name: String, size: CGFloat, at centre: CGPoint, age: Double, in face: GraphicsContext) {
        let glyph = face.symbol(name, size: size, weight: .medium, color: .white)
        let scale = 1 - Pop.dip * energy * MoneyMath.ring(age)
        let stage = face.posed(about: centre, scaleX: scale, scaleY: scale).faded(MoneyMath.clamp(age / Pop.fade))
        let box = CGRect(x: centre.x - size, y: centre.y - size, width: 2 * size, height: 2 * size)
        func contour(offset: CGSize, shading: GraphicsContext.Shading, in layer: inout GraphicsContext) {
            let point = CGPoint(x: centre.x + offset.width, y: centre.y + offset.height)
            layer.clipToLayer { $0.draw(glyph, at: point) }
            layer.clipToLayer(options: .inverse) { core in
                for shift in Card.erosion {
                    core.clipToLayer { $0.draw(glyph, at: CGPoint(x: point.x + shift.width, y: point.y + shift.height)) }
                }
                core.fill(Path(box), with: .color(.white))
            }
            layer.fill(Path(box), with: shading)
        }
        var lit = stage.faded(Card.litOpacity)
        lit.addFilter(.shadow(color: .black.opacity(Card.shadeOpacity), radius: Card.shadeBlur, x: Card.shadeOffset.width, y: Card.shadeOffset.height))
        lit.drawLayer { contour(offset: Card.litOffset, shading: .color(.white), in: &$0) }
        let metal = GraphicsContext.Shading.linearGradient(Card.metal, startPoint: CGPoint(x: centre.x, y: centre.y - size / 2),
                                                           endPoint: CGPoint(x: centre.x, y: centre.y + size / 2))
        stage.faded(Card.metalOpacity).drawLayer { contour(offset: .zero, shading: metal, in: &$0) }
    }

    // MARK: Pay row

    private func drawPay(_ item: MoneyItem, frame: CGRect, in graphics: GraphicsContext) {
        let title = context.trackArtist.isEmpty ? Pill.label : "\(Pill.label) \(context.trackArtist)"
        var header = graphics
        header.clip(to: Path(CGRect(x: frame.minX + Pay.header.x, y: frame.minY + Pay.header.y - Look.rowHeight / 2,
                                    width: frame.width - Pay.headerTrailingRoom, height: Look.rowHeight)))
        header.draw(graphics.label(Text(title), size: Pay.headerSize, weight: .regular, color: Look.secondary),
                    at: CGPoint(x: frame.minX + Pay.header.x, y: frame.minY + Pay.header.y), anchor: .leading)
        drawWords(of: item, at: CGPoint(x: frame.minX + Pay.text.x, y: frame.minY + Pay.text.y), color: .white, in: graphics)

        let centre = CGPoint(x: frame.maxX - Pay.disc.x, y: frame.midY + Pay.disc.y)
        let sinceEnd = position - item.end
        guard sinceEnd >= 0 else {
            // Waiting to be paid: the ring swells briefly every so often.
            let phase = clock.truncatingRemainder(dividingBy: Pay.pulseEvery)
            let pulse = phase >= 0 && phase < Pay.pulseLength ? sin(.pi * phase / Pay.pulseLength) : 0
            graphics.stroke(disc(at: centre, radius: Pay.radius * (1 + Pay.pulseGrowth * pulse)), with: .color(item.tint), lineWidth: Pay.ringWidth)
            graphics.draw(graphics.symbol("arrow.right.to.line", size: Pay.arrowSize, weight: .semibold, color: item.tint), at: centre)
            return
        }
        let filled = MoneyMath.spring(sinceEnd, response: Pay.fillResponse, damping: Pay.fillDamping)
        graphics.stroke(disc(at: centre, radius: Pay.radius), with: .color(item.tint), lineWidth: Pay.ringWidth)
        graphics.fill(disc(at: centre, radius: Pay.radius * max(filled, 0)), with: .color(item.tint))
        graphics.posed(about: centre, scaleX: filled, scaleY: filled)
            .draw(graphics.symbol("checkmark", size: Pay.checkSize, weight: .bold, color: .white), at: centre)
        graphics.faded(MoneyMath.clamp((sinceEnd - Pay.doneFadeFrom) / Pay.doneFadeSpan))
            .draw(graphics.label(Text(Pay.done), size: Pay.doneSize, weight: .medium, color: .white), at: CGPoint(x: centre.x, y: centre.y + Pay.doneBelow))
    }

    // MARK: Map row

    private func drawMap(_ slot: MoneySlot, frame: CGRect, in graphics: GraphicsContext) {
        let item = slot.item
        if let picture = slot.picture {
            let window = CGRect(x: slot.rect.minX, y: slot.rect.minY, width: slot.rect.width,
                                height: slot.rect.height * slot.pictureHeight / max(slot.rest.height, 1))
            let shown = graphics.faded(MoneyMath.clamp((slot.rect.width / slot.rest.width - MapRow.showFrom) / MapRow.showSpan))
            drawPicture(picture, in: window, slot: slot, graphics: shown)
            drawPin(for: slot, in: window, graphics: shown)
        }
        drawWords(of: item, at: CGPoint(x: frame.minX + MapRow.textInset.x, y: frame.minY + slot.pictureHeight + MapRow.textInset.y),
                  color: .white, in: graphics)
        let footerY = frame.maxY - MapRow.footerAboveBottom
        graphics.draw(graphics.label(Text(Pill.label), size: MapRow.paySize, weight: .medium, color: .white),
                      at: CGPoint(x: frame.maxX - MapRow.textInset.x, y: footerY), anchor: .trailing)
        guard let place = slot.picture?.place else { return }
        var caption = graphics.faded(MoneyMath.clamp((slot.age - MapRow.placeFadeFrom) / MapRow.placeFadeSpan))
        caption.clip(to: Path(CGRect(x: frame.minX, y: footerY - Look.rowHeight / 2, width: frame.width - MapRow.payRoom, height: Look.rowHeight)))
        caption.draw(graphics.label(Text("\(Image(systemName: "location.fill")) \(place)"), size: MapRow.placeSize, weight: .regular, color: Look.secondary),
                     at: CGPoint(x: frame.minX + MapRow.textInset.x, y: footerY), anchor: .leading)
    }

    /// The still fills the top of the row, starts zoomed in and blurred, and keeps creeping outwards.
    private func drawPicture(_ picture: MoneyMapPicture, in window: CGRect, slot: MoneySlot, graphics: GraphicsContext) {
        let age = slot.age, seed = slot.item.seed
        let corner = min(radius(of: slot), window.height)
        let top = UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
        let settled = MoneyMath.spring(age - MapRow.zoomDelay, response: MapRow.zoomResponse, damping: MapRow.zoomDamping)
        let zoom = MapRow.zoom - MapRow.zoomSettle * settled - MapRow.drift * min(age / MapRow.driftSpan, 1)
        let image = CGSize(width: picture.image.width, height: picture.image.height)
        let fill = max(window.width / image.width, window.height / image.height) * zoom
        let pan = CGPoint(x: (2 * seededUnit(seed, salt: Salt.panX) - 1) * MapRow.panX * window.width,
                          y: (2 * seededUnit(seed, salt: Salt.panY) - 1) * MapRow.panY * window.height)
        var clipped = graphics
        clipped.clip(to: top.path(in: window))
        let blur = MapRow.blur * (1 - age / MapRow.blurSpan)
        if blur > Look.minSoft { clipped.addFilter(.blur(radius: blur)) }
        clipped.draw(Image(decorative: picture.image, scale: 1),
                     in: CGRect(x: window.midX + pan.x - image.width * fill / 2, y: window.midY + pan.y - image.height * fill / 2,
                                width: image.width * fill, height: image.height * fill))
        graphics.stroke(top.path(in: window.insetBy(dx: 0.5, dy: 0.5)),
                        with: .linearGradient(MapRow.rim, startPoint: CGPoint(x: window.midX, y: window.minY), endPoint: CGPoint(x: window.midX, y: window.maxY)))
        graphics.draw(graphics.label(Text(MapRow.caption), size: MapRow.captionSize, weight: .semibold, color: .white.opacity(MapRow.captionOpacity)),
                      at: CGPoint(x: window.minX + MapRow.captionInset.x, y: window.maxY - MapRow.captionInset.y), anchor: .bottomLeading)
    }

    /// A pin drops onto the middle of the picture a moment after the row arrives.
    private func drawPin(for slot: MoneySlot, in window: CGRect, graphics: GraphicsContext) {
        let time = slot.age - MapRow.pinDelay
        guard time >= 0 else { return }
        let item = slot.item, tip = CGPoint(x: window.midX, y: window.midY + MapRow.pinTipBelowCentre)
        if time < MapRow.rippleLife {
            let phase = time / MapRow.rippleLife, reach = MapRow.rippleFrom + MapRow.rippleGrowth * phase
            let ripple = Path(ellipseIn: CGRect(x: tip.x - reach, y: tip.y - reach * MapRow.rippleFlatness,
                                                width: 2 * reach, height: 2 * reach * MapRow.rippleFlatness))
            graphics.stroke(ripple, with: .color(item.tint.opacity((1 - phase) * MapRow.rippleOpacity)), lineWidth: MapRow.rippleWidth)
        }
        let landed = MoneyMath.spring(time, response: MapRow.pinResponse, damping: MapRow.pinDamping)
        var pin = graphics.faded(MoneyMath.clamp(time / MapRow.pinFade))
        pin.translateBy(x: 0, y: -MapRow.pinDrop * (1 - landed))
        let head = CGPoint(x: tip.x, y: tip.y - MapRow.pinHeadAboveTip)
        let neck = Path { path in
            path.addLines([CGPoint(x: tip.x - MapRow.pinNeck.width, y: tip.y - MapRow.pinNeck.height),
                           CGPoint(x: tip.x + MapRow.pinNeck.width, y: tip.y - MapRow.pinNeck.height), tip])
            path.closeSubpath()
        }
        var body = pin
        body.addFilter(.shadow(color: .black.opacity(MapRow.pinShadow), radius: MapRow.pinShadowRadius, x: 0, y: MapRow.pinShadowY))
        body.fill(disc(at: head, radius: MapRow.pinHeadRadius).union(neck), with: .color(item.tint))
        let glyph = glyph(of: item)
        drawPopping(pin.symbol(glyph.name, size: MapRow.pinIconSize, weight: .semibold, color: .white), at: head, age: glyph.age, in: pin)
    }

    // MARK: Lead pill and receipt

    /// After a pause, a small pill turns up early where the next item will grow.
    private func drawLead(_ lead: MoneyLead, in graphics: GraphicsContext) {
        let item = lead.item, rect = lead.rect, isBubble = item.kind.isBubble
        let scale = MoneyMath.spring(lead.age, response: Pill.response, damping: Pill.damping) * (1 + Pill.breath * sin(Pill.breathSpeed * clock) * energy)
        let swing = isBubble ? (item.outgoing ? -Pill.bubbleDegrees : Pill.bubbleDegrees) : Pill.platterDegrees
        let pill = graphics.posed(about: CGPoint(x: rect.midX, y: rect.midY), degrees: swing * energy * MoneyMath.ring(lead.age), scaleX: scale, scaleY: scale)
            .faded(MoneyMath.clamp(lead.age / Pill.fade))
        let capsule = Capsule().path(in: rect)
        if isBubble {
            let side: CGFloat = item.outgoing ? -1 : 1
            let corner = CGPoint(x: item.outgoing ? rect.maxX : rect.minX, y: rect.maxY)
            let trail = disc(at: CGPoint(x: corner.x + side * Pill.knuckle.x, y: corner.y + Pill.knuckle.y), radius: Pill.knuckleRadius)
                .union(disc(at: CGPoint(x: corner.x + side * Pill.fingertip.x, y: corner.y + Pill.fingertip.y), radius: Pill.fingertipRadius))
            let fill = item.kind == .cash ? Look.cashFill : item.outgoing ? Look.messageBlue : Look.messageGrey
            pill.fill(capsule.union(trail), with: .color(fill))
        } else {
            pill.fill(capsule, with: .color(.black))
            if item.kind == .pay { drawRim(around: rect, radius: rect.height / 2, in: pill) }
        }
        drawPillContents(of: item, in: rect, graphics: pill)
    }

    private func drawPillContents(of item: MoneyItem, in rect: CGRect, graphics: GraphicsContext) {
        switch item.kind {
        case .cash, .message:
            for dot in 0..<Pill.dots {
                let wave = sin(Pill.dotSpeed * clock - Pill.dotPhase * Double(dot))
                let centre = CGPoint(x: rect.midX + (CGFloat(dot) - CGFloat(Pill.dots - 1) / 2) * Pill.dotSpacing,
                                     y: rect.midY - Pill.dotBob * wave * energy)
                graphics.fill(disc(at: centre, radius: Pill.dotSize / 2), with: .color(.white.opacity(Pill.dotDim + Pill.dotGlow * (0.5 + 0.5 * wave))))
            }
        case .pay:
            graphics.draw(graphics.label(Text(Pill.label), size: Pill.labelSize, weight: .medium, color: .white), at: CGPoint(x: rect.midX, y: rect.midY))
        case .island, .card, .map:
            graphics.draw(graphics.symbol(item.icon, size: Pill.iconSize, weight: .semibold, color: item.tint),
                          at: CGPoint(x: rect.minX + Pill.iconX, y: rect.midY))
            for bar in 0..<Pill.bars {
                let height = Pill.barMin + Pill.barSwing * abs(sin(Pill.barSpeed * clock + Pill.barPhase * Double(bar)))
                let x = rect.maxX - Pill.barInset - CGFloat(Pill.bars - 1 - bar) * Pill.barSpacing
                graphics.fill(Capsule().path(in: CGRect(x: x - Pill.barWidth / 2, y: rect.midY - height / 2, width: Pill.barWidth, height: height)),
                              with: .color(item.tint))
            }
        }
    }

    private func drawReceipt(_ receipt: MoneyReceipt, in graphics: GraphicsContext) {
        let text = graphics.label(Text(Look.receipt), size: Look.receiptSize, weight: .semibold, color: .white.opacity(Look.receiptOpacity))
        graphics.posed(about: receipt.corner, scaleX: receipt.scale, scaleY: receipt.scale).faded(receipt.alpha)
            .draw(text, at: receipt.corner, anchor: .topTrailing)
    }
}
