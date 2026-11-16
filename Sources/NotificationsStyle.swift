import SwiftUI

/// Notifications: every lyric line arrives the way a phone would deliver it — as a notification banner
/// (quick ones collapse into a stack), an assistant panel with a rainbow rim, a "Now Playing" widget or,
/// in a long silence, a small glance row. Words appear one at a time as they are sung. The plan lives in
/// `NotificationsPlan.swift`, the per-frame placement in `NotificationsFeed.swift`; this file only paints.
/// Everything is drawn in one Canvas from the playback position alone: there is no view state.
struct NotificationsStyle: View {
    let context: StyleContext

    var body: some View {
        let feed = NotifyFeed(context: context)
        let canvas = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, _ in
            guard let feed else { return }
            NotifyPainter(context: context, feed: feed).draw(in: graphics)
        }
        .frame(width: context.canvas.width, height: context.band)
        // Old items are not removed on a timer; they are pushed up and dissolve here.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: NotifyLook.topFade)],
                             startPoint: .top, endPoint: .bottom))
        .opacity(feed?.presence ?? 0)
        .shadow(color: .black.opacity(NotifyLook.shadowOpacity), radius: NotifyLook.shadowRadius, y: NotifyLook.shadowY)
        // A feed at rest gets no blur at all rather than one of radius 0, which may still cost a full-width pass.
        if let blur = feed?.blur, blur > 0 { canvas.blur(radius: blur) } else { canvas }
    }
}

// MARK: Constants (design units)

private enum NotifyLook {
    static let topFade = 0.12
    static let shadowOpacity = 0.32, shadowRadius: CGFloat = 14, shadowY: CGFloat = 5
    static let drawFloor = 0.002, blurFloor: CGFloat = 0.05
    static let grey = Color(.sRGB, red: 0.9725, green: 0.9725, blue: 0.9725)
    static let secondary = 0.58
    // Faked glass: a dark fill, a faint grey sheen and two hairline rims
    static let bannerShade = 0.54, panelShade = 0.62, widgetShade = 0.6
    static let sheen = Gradient(colors: [grey.opacity(0.17), grey.opacity(0.09)])
    static let rimInset: CGFloat = 0.5, rimWidth: CGFloat = 1
    static let rimDown = Gradient(colors: [.white.opacity(0.36), .white.opacity(0.07), .white.opacity(0.17)])
    static let rimAcross = Gradient(stops: [.init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0), location: 0.2),
                                            .init(color: .white.opacity(0), location: 0.82), .init(color: .white.opacity(0.22), location: 1)])
    static let squashVertical = 0.7
    static let echoReach: CGFloat = 16, echoOpacity = 0.55, echoFadePower = 1.5, echoWidth: CGFloat = 0.6, echoWidthGain: CGFloat = 1.6
}

private enum NotifyReveal {
    static let riseShare: CGFloat = 0.7, lift = 1.2, liftAttack = 0.08, liftRelease = 4.0
    static let pop = 0.07, longGain = 1.7, wobbleDecay = 0.12, wobbleOmega = 17.0, wobbleDip = 0.5, minScale = 0.05
    static let leanDegrees = 8.0, leanFullWidth: CGFloat = 44, longLean = 1.3
    static let fadeWindow = 0.1, fadeIn = 0.06, blur: CGFloat = 2.5
    static let glyphDecay = 0.17, glyphOmega = 12.0, glyphDegrees = 14.0
}

private enum NotifyBanner {
    static let tileSide: CGFloat = 38.33, tileX: CGFloat = 14, tileRadius: CGFloat = 8.6
    static let tileLighten = 0.24, tileDarken = 0.2
    static let tileRimInset: CGFloat = 0.3, tileRimRadius: CGFloat = 8.3, tileRimWidth: CGFloat = 0.6
    static let tileRim = Gradient(colors: [.white.opacity(0.45), .white.opacity(0.04)])
    static let glyphSize: CGFloat = 19
    static let timeX: CGFloat = 356, timeSize: CGFloat = 15
    static let recent = 50.0, minuteRounding = 10.0, secondsPerMinute = 60.0
}

private enum NotifyPanel {
    typealias Glow = (opacity: Double, blur: CGFloat, width: CGFloat)
    static let spin = 0.9                       // radians per second of song
    static let outerGlow: Glow = (0.8, 9, 6), innerGlow: Glow = (0.4, 11, 12), pillGlow: Glow = (0.6, 7, 5)
    static let rimInset: CGFloat = 0.8, rimWidth: CGFloat = 1.6, rimGain = 1.25
    static let glowFadeDelay = 0.5, glowFadeLength = 1.9, glowFloor = 0.5
    static let glowWindow = 2.0, glowLongGain = 1.5, glowDecay = 0.32
    static let pillShade = 0.6, pillSheen = 0.12, pillFade = 0.08
    static let barCount = 7, barWidth: CGFloat = 3.5, barPitch: CGFloat = 6.5, barMin: CGFloat = 5, barGain: CGFloat = 11
    static let barFalloff = 6.0, barPhase = 0.9, barSpeed = 5.2
}

private enum NotifyWidget {
    static let blobSpots: [(x: CGFloat, y: CGFloat, radius: CGFloat)] = [(0.88, 0.16, 0.5), (0.1, 1, 0.48), (0.6, 0.82, 0.36),
                                                                         (0.02, 0.1, 0.32), (1, 0.95, 0.3)]
    static let fallbackSteps = [0, 3, 6, 9], fallbackLighten = 0.2
    static let blobDelay = 0.05, blobSpread = 0.7, blobBloom = 0.7, blobMinDuration = 0.4
    static let blobSmall: CGFloat = 0.6, blobCore = 0.6, blobMid = 0.32, blobMidStop: CGFloat = 0.45
    static let gloss = Gradient(colors: [NotifyLook.grey.opacity(0.13), NotifyLook.grey.opacity(0.03)])
    static let glyphCenter = CGPoint(x: 26, y: 26), glyphSize: CGFloat = 14, glyphOpacity = 0.9
    static let headerSize: CGFloat = 13
    static let titleOrigin = CGPoint(x: 40, y: 18), titleOpacity = 0.8, titleFallback = "Now Playing"
    static let titleClip = CGRect(x: 40, y: 16, width: 281.67, height: 20)
    static let timeCorner = CGPoint(x: 331.67, y: 18), timeOpacity = 0.55
    static let track = CGRect(x: 18, y: 142.33, width: 313.67, height: 4), trackOpacity = 0.2, fillOpacity = 0.92
    static let textBottom: CGFloat = 130.33
    static let progressTail = 0.3, progressMinWord = 0.12
}

private enum NotifyGlance {
    static let shadowOpacity = 0.5, shadowRadius: CGFloat = 3, shadowY: CGFloat = 1
    static let noteCenter = CGPoint(x: 14, y: 10.5), divider = CGRect(x: 23, y: 4, width: 1, height: 13)
    static let caption = "NOW PLAYING", captionOrigin = CGPoint(x: 27, y: 4), captionSize: CGFloat = 13
    static let rowsOrigin = CGPoint(x: 8, y: 18), rowPitch: CGFloat = 16, rowSize: CGFloat = 12
    static let rowsClip = CGRect(x: 8, y: 18, width: 148, height: 50)
    static let primary = 0.92, untitled = "Unknown song"
    static let discSide: CGFloat = 58, discShade = 0.15, discOpacity = 0.72
    static let countdownCenter = CGPoint(x: 207, y: 36), songCenter = CGPoint(x: 297, y: 36)
    static let arcRadius: CGFloat = 23.5, arcWidth: CGFloat = 5, trackOpacity = 0.2, arcOpacity = 0.95
    static let countdownSize: CGFloat = 20, noteSize: CGFloat = 18, minSpan = 0.01
    static let top = -90.0, turn = 360.0, sweepStart = 135.0, sweep = 270.0
    static let percentSize: CGFloat = 14, percentRise: CGFloat = 1, smallNote: CGFloat = 10, smallNoteDrop: CGFloat = 22.5
}

private extension GraphicsContext {
    func faded(_ amount: Double) -> GraphicsContext {
        var copy = self
        copy.opacity *= min(max(amount, 0), 1)
        return copy
    }

    func blurred(_ radius: CGFloat) -> GraphicsContext {
        var copy = self
        copy.addFilter(.blur(radius: radius))
        return copy
    }

    func clipped(to path: Path) -> GraphicsContext {
        var copy = self
        copy.clip(to: path)
        return copy
    }

    /// A copy whose origin is `rect`'s corner and whose units make `rect` exactly `designWidth` wide.
    func fitted(to rect: CGRect, designWidth: CGFloat) -> GraphicsContext {
        var copy = self
        copy.translateBy(x: rect.minX, y: rect.minY)
        copy.scaleBy(x: rect.width / designWidth, y: rect.width / designWidth)
        return copy
    }
}

// MARK: Painter

private struct NotifyPainter {
    let feed: NotifyFeed
    let position: Double
    let motion: Double
    let title: String
    let artist: String
    let artwork: [NSColor]?

    init(context: StyleContext, feed: NotifyFeed) {
        self.feed = feed
        position = context.position
        motion = feed.motion
        title = context.trackTitle
        artist = context.trackArtist
        artwork = context.artworkPalette
    }

    func draw(in graphics: GraphicsContext) {
        var scene = graphics
        scene.translateBy(x: feed.origin.x, y: feed.origin.y)
        scene.scaleBy(x: feed.scale, y: feed.scale)
        feed.slots.forEach { draw($0, in: scene) }
        if let pill = feed.pill { draw(pill, in: scene) }
    }

    /// A slot leans and squashes about the middle of its bottom edge when it lands and with every word.
    private func draw(_ slot: NotifySlotPose, in graphics: GraphicsContext) {
        var layer = graphics
        layer.translateBy(x: slot.rect.midX, y: slot.rect.maxY)
        layer.rotate(by: .degrees(slot.tiltDegrees))
        layer.scaleBy(x: 1 + slot.squash, y: 1 - NotifyLook.squashVertical * slot.squash)
        layer.translateBy(x: -slot.rect.midX, y: -slot.rect.maxY)
        for echo in slot.echoes {
            let fade = 1 - echo.phase
            let reach = NotifyLook.echoReach * (1 - fade * fade * fade)
            let ring = NotifyCardPose.outline(slot.ringRect.insetBy(dx: -reach, dy: -reach), radius: slot.ringRadius + reach)
            layer.stroke(ring, with: .color(.white.opacity(echo.strength * NotifyLook.echoOpacity * pow(fade, NotifyLook.echoFadePower))),
                         lineWidth: NotifyLook.echoWidth + NotifyLook.echoWidthGain * fade)
        }
        slot.cards.forEach { draw($0, in: layer) }
    }

    private func draw(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        guard card.alpha > NotifyLook.drawFloor else { return }
        var layer = graphics
        card.cutouts.forEach { layer.clip(to: $0, options: .inverse) }
        let isGlance = card.item.kind == .glance
        // A fading or blurred card has to be composited as one piece, or its overlapping fills would show through.
        guard card.alpha < 1 || card.blur > NotifyLook.blurFloor || isGlance else { return paint(card, in: layer) }
        layer.opacity *= card.alpha
        if card.blur > NotifyLook.blurFloor { layer.addFilter(.blur(radius: card.blur)) }
        if isGlance {
            layer.addFilter(.shadow(color: .black.opacity(NotifyGlance.shadowOpacity), radius: NotifyGlance.shadowRadius,
                                    x: 0, y: NotifyGlance.shadowY))
        }
        layer.drawLayer { paint(card, in: $0) }
    }

    private func paint(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        switch card.item.kind {
        case .banner: drawBanner(card, in: graphics)
        case .assistant: drawPanel(card, in: graphics)
        case .widget: drawWidget(card, in: graphics)
        case .glance: drawGlance(card, in: graphics)
        }
    }

    // MARK: Shared pieces

    private func drawGlass(_ rect: CGRect, radius: CGFloat, shade: Double, in graphics: GraphicsContext) {
        let shape = NotifyCardPose.outline(rect, radius: radius)
        graphics.fill(shape, with: .color(.black.opacity(shade)))
        graphics.fill(shape, with: .linearGradient(NotifyLook.sheen, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                   endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        drawRim(rect, radius: radius, in: graphics)
    }

    private func drawRim(_ rect: CGRect, radius: CGFloat, in graphics: GraphicsContext) {
        let edge = NotifyCardPose.outline(rect.insetBy(dx: NotifyLook.rimInset, dy: NotifyLook.rimInset), radius: radius - NotifyLook.rimInset)
        graphics.stroke(edge, with: .linearGradient(NotifyLook.rimDown, startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)), lineWidth: NotifyLook.rimWidth)
        graphics.stroke(edge, with: .linearGradient(NotifyLook.rimAcross, startPoint: rect.origin,
                                                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: NotifyLook.rimWidth)
    }

    private func label(_ string: String, size: CGFloat, weight: Font.Weight = .regular, opacity: Double = 1,
                       design: Font.Design = .default, fixedDigits: Bool = false) -> Text {
        let font = Font.system(size: size, weight: weight, design: design)
        return Text(string).font(fixedDigits ? font.monospacedDigit() : font).foregroundStyle(.white.opacity(opacity))
    }

    private static func clock(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// An SF Symbol; with an `age` (seconds since it appeared) it lands with a wobble.
    private func drawSymbol(_ name: String, size: CGFloat, opacity: Double = 1, age: Double? = nil, at center: CGPoint,
                            in graphics: GraphicsContext) {
        let swing = age.map { $0 >= 0 ? motion * exp(-$0 / NotifyReveal.glyphDecay) * cos(NotifyReveal.glyphOmega * $0) : 0 } ?? 0
        let scale = max(NotifyReveal.minScale, 1 - NotifyReveal.wobbleDip * swing)
        var layer = graphics
        layer.translateBy(x: center.x, y: center.y)
        layer.rotate(by: .degrees(NotifyReveal.glyphDegrees * swing))
        layer.scaleBy(x: scale, y: scale)
        layer.draw(Text(Image(systemName: name)).font(.system(size: size, weight: .semibold)).foregroundStyle(.white.opacity(opacity)), at: .zero)
    }

    /// The item's glyph: its app symbol until a sung word brings a picture of its own.
    private func drawGlyph(of card: NotifyCardPose, size: CGFloat, opacity: Double = 1, at center: CGPoint, in graphics: GraphicsContext) {
        guard let icon = card.item.icons.last(where: { $0.at <= position }) else { return }
        drawSymbol(icon.name, size: size, opacity: opacity, age: icon.at.isFinite ? position - icon.at : card.age, at: center, in: graphics)
    }

    // MARK: Words

    /// Sung words only: each rises into place, pops, leans and sharpens; words not yet sung are not drawn.
    private func drawWords(_ layout: NotifyLayout, at origin: CGPoint, in graphics: GraphicsContext) {
        let font = layout.type.font
        let middle = layout.type.lineHeight / 2
        guard position < layout.until else {
            for row in layout.rows {
                graphics.draw(Text(row.text).font(font).foregroundStyle(.white),
                              at: CGPoint(x: origin.x, y: origin.y + row.y + middle), anchor: .leading)
            }
            return
        }
        for word in layout.words where word.start <= position {
            drawWord(word, font: font, at: CGPoint(x: origin.x + word.x, y: origin.y + word.y + middle),
                     rise: NotifyReveal.riseShare * layout.type.lineHeight, in: graphics)
        }
    }

    private func drawWord(_ word: NotifyWord, font: Font, at left: CGPoint, rise: CGFloat, in graphics: GraphicsContext) {
        let age = position - word.start
        let gain = word.isLong ? NotifyReveal.longGain : 1
        let wobble = motion * exp(-age / NotifyReveal.wobbleDecay) * cos(NotifyReveal.wobbleOmega * age)
        // The word being sung sits a touch larger and higher; there is no highlight colour.
        let active = min(age / NotifyReveal.liftAttack, 1) * (1 - NotifyMath.smooth((position - word.end) * NotifyReveal.liftRelease)) * motion
        let drop = rise * (1 - NotifySpring.word.value(at: age)) - NotifyReveal.lift * active
        let scale = (1 + NotifyReveal.pop * gain * active) * max(NotifyReveal.minScale, 1 - NotifyReveal.wobbleDip * gain * wobble)
        let lean = word.sign * NotifyReveal.leanDegrees * wobble * min(NotifyReveal.leanFullWidth / max(word.width, 1), 1)
            * (word.isLong ? NotifyReveal.longLean : 1)
        var layer = graphics
        if age < NotifyReveal.fadeWindow {
            layer.opacity *= min(age / NotifyReveal.fadeIn, 1)
            layer.addFilter(.blur(radius: NotifyReveal.blur * (1 - age / NotifyReveal.fadeWindow)))
        }
        // Scaled from its left edge so the words after it never shift; leans about its own middle.
        layer.translateBy(x: left.x, y: left.y + drop)
        layer.scaleBy(x: scale, y: scale)
        layer.translateBy(x: word.width / 2, y: 0)
        layer.rotate(by: .degrees(lean))
        layer.draw(Text(word.text).font(font).foregroundStyle(.white), at: .zero)
    }

    // MARK: Banner

    private func drawBanner(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        drawGlass(card.rect, radius: card.radius, shade: NotifyLook.bannerShade, in: graphics)
        guard card.content > NotifyLook.drawFloor else { return }
        let item = card.item
        let content = graphics.clipped(to: card.outline).faded(card.content).fitted(to: card.rect, designWidth: NotifyMetrics.bannerWidth)
        drawIconTile(card, in: content)
        let headY = item.body.words.isEmpty ? (item.size.height - item.head.type.lineHeight) / 2 : NotifyMetrics.bannerHeadY
        drawWords(item.head, at: CGPoint(x: NotifyMetrics.bannerTextX, y: headY), in: content)
        drawWords(item.body, at: CGPoint(x: NotifyMetrics.bannerTextX, y: NotifyMetrics.bannerBodyY), in: content)
        guard item.head.size.width <= NotifyMetrics.bannerHeadFit else { return }
        let since = position - item.end
        let minutes = max(1, Int((since + NotifyBanner.minuteRounding) / NotifyBanner.secondsPerMinute))
        content.draw(label(since < NotifyBanner.recent ? "now" : "\(minutes)m ago", size: NotifyBanner.timeSize, opacity: NotifyLook.secondary),
                     at: CGPoint(x: NotifyBanner.timeX, y: headY + item.head.type.lineHeight / 2), anchor: .trailing)
    }

    private func drawIconTile(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        let side = NotifyBanner.tileSide
        let tile = CGRect(x: NotifyBanner.tileX, y: (card.item.size.height - side) / 2, width: side, height: side)
        let top = CGPoint(x: tile.midX, y: tile.minY), bottom = CGPoint(x: tile.midX, y: tile.maxY)
        let tint = card.item.tint
        let colors = [tint.mix(with: .white, by: NotifyBanner.tileLighten), tint.mix(with: .black, by: NotifyBanner.tileDarken)]
        graphics.fill(NotifyCardPose.outline(tile, radius: NotifyBanner.tileRadius),
                      with: .linearGradient(Gradient(colors: colors), startPoint: top, endPoint: bottom))
        let rim = NotifyCardPose.outline(tile.insetBy(dx: NotifyBanner.tileRimInset, dy: NotifyBanner.tileRimInset), radius: NotifyBanner.tileRimRadius)
        graphics.stroke(rim, with: .linearGradient(NotifyBanner.tileRim, startPoint: top, endPoint: bottom), lineWidth: NotifyBanner.tileRimWidth)
        drawGlyph(of: card, size: NotifyBanner.glyphSize, at: CGPoint(x: tile.midX, y: tile.midY), in: graphics)
    }

    // MARK: Assistant panel and pill

    private func rainbow(around rect: CGRect, seed: Double) -> GraphicsContext.Shading {
        let angle = NotifyPanel.spin * position + 2 * Double.pi * seededUnit(seed, salt: NotifySalt.rainbowPhase)
        return .conicGradient(Gradient(colors: NotifyTables.rainbow), center: CGPoint(x: rect.midX, y: rect.midY), angle: .radians(angle))
    }

    /// How brightly the rainbow shines: it pulses with every word and fades out after the line.
    private func glowLevel(of item: NotifyItem) -> Double {
        let pulse = item.words.reduce(0.0) { total, word in
            let age = position - word.start
            guard age >= 0, age <= NotifyPanel.glowWindow else { return total }
            return total + (word.isLong ? NotifyPanel.glowLongGain : 1) * exp(-age / NotifyPanel.glowDecay) * (1 - exp(-age / NotifyMath.attack))
        }
        let fade = 1 - NotifyMath.smooth((position - item.end - NotifyPanel.glowFadeDelay) / NotifyPanel.glowFadeLength)
        return fade * (NotifyPanel.glowFloor + (1 - NotifyPanel.glowFloor) * min(1, pulse))
    }

    private func drawPanel(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        let item = card.item, shape = card.outline
        let colors = rainbow(around: card.rect, seed: item.seed)
        let glow = glowLevel(of: item)
        let outer = NotifyPanel.outerGlow, inner = NotifyPanel.innerGlow
        // The glow is gone a few seconds after the line, long before the panel leaves; its blurred strokes go with it.
        let glows = glow > NotifyLook.drawFloor
        if glows { graphics.faded(glow * outer.opacity).blurred(outer.blur).stroke(shape, with: colors, lineWidth: outer.width) }
        drawGlass(card.rect, radius: card.radius, shade: NotifyLook.panelShade, in: graphics)
        if glows {
            graphics.clipped(to: shape).faded(glow * inner.opacity).blurred(inner.blur).stroke(shape, with: colors, lineWidth: inner.width)
            let rim = NotifyCardPose.outline(card.rect.insetBy(dx: NotifyPanel.rimInset, dy: NotifyPanel.rimInset),
                                             radius: card.radius - NotifyPanel.rimInset)
            graphics.faded(NotifyPanel.rimGain * glow).stroke(rim, with: colors, lineWidth: NotifyPanel.rimWidth)
        }
        let padding = NotifyMetrics.panelPadding
        // Anchored where the panel will rest, so the text is uncovered rather than dragged along while the panel grows.
        drawWords(item.body, at: CGPoint(x: card.rest.minX + padding, y: card.rest.minY + padding),
                  in: graphics.clipped(to: shape).faded(1 - card.handoff))
        guard card.handoff > 0 else { return }
        drawBars(center: CGPoint(x: card.rect.midX, y: card.rect.minY + NotifyMetrics.pillSize.height / 2), in: graphics.faded(card.handoff))
    }

    private func drawBars(center: CGPoint, in graphics: GraphicsContext) {
        for index in 0..<NotifyPanel.barCount {
            let offset = Double(index - NotifyPanel.barCount / 2)
            let swing = abs(sin(NotifyPanel.barPhase * Double(index) + NotifyPanel.barSpeed * position))
            let height = NotifyPanel.barMin + NotifyPanel.barGain * (1 - abs(offset) / NotifyPanel.barFalloff) * swing
            let bar = CGRect(x: center.x + offset * NotifyPanel.barPitch - NotifyPanel.barWidth / 2, y: center.y - height / 2,
                             width: NotifyPanel.barWidth, height: height)
            graphics.fill(Path(roundedRect: bar, cornerRadius: NotifyPanel.barWidth / 2),
                          with: .color(NotifyTables.rainbow[index % NotifyPanel.barCount]))
        }
    }

    private func draw(_ pill: NotifyPillPose, in graphics: GraphicsContext) {
        let size = NotifyMetrics.pillSize
        let rect = CGRect(x: (NotifyMetrics.columnWidth - size.width) / 2, y: pill.top, width: size.width, height: size.height)
        let scale = NotifySpring.pill.value(at: pill.age)
        var layer = graphics.faded(pill.age / NotifyPanel.pillFade)
        layer.translateBy(x: rect.midX, y: rect.midY)
        layer.scaleBy(x: scale, y: scale)
        layer.translateBy(x: -rect.midX, y: -rect.midY)
        let capsule = NotifyCardPose.outline(rect, radius: size.height / 2)
        let colors = rainbow(around: rect, seed: pill.seed)
        let glow = NotifyPanel.pillGlow
        layer.faded(glow.opacity).blurred(glow.blur).stroke(capsule, with: colors, lineWidth: glow.width)
        layer.fill(capsule, with: .color(.black.opacity(NotifyPanel.pillShade)))
        layer.fill(capsule, with: .color(NotifyLook.grey.opacity(NotifyPanel.pillSheen)))
        layer.stroke(NotifyCardPose.outline(rect.insetBy(dx: NotifyPanel.rimInset, dy: NotifyPanel.rimInset), radius: size.height / 2),
                     with: colors, lineWidth: NotifyPanel.rimWidth)
        drawBars(center: CGPoint(x: rect.midX, y: rect.midY), in: layer)
    }

    // MARK: Widget

    private func drawWidget(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        let item = card.item, design = NotifyMetrics.widgetSize
        graphics.fill(card.outline, with: .color(.black.opacity(NotifyLook.widgetShade)))
        let content = graphics.clipped(to: card.outline).fitted(to: card.rect, designWidth: design.width)
        drawBlobs(for: item, in: content)
        content.fill(Path(CGRect(origin: .zero, size: design)),
                     with: .linearGradient(NotifyWidget.gloss, startPoint: .zero, endPoint: CGPoint(x: 0, y: design.height)))
        drawWidgetHeader(card, in: content)
        let track = NotifyWidget.track
        let filled = CGRect(x: track.minX, y: track.minY, width: track.width * lineProgress(of: item), height: track.height)
        content.fill(Path(roundedRect: track, cornerRadius: track.height / 2), with: .color(.white.opacity(NotifyWidget.trackOpacity)))
        content.fill(Path(roundedRect: filled, cornerRadius: track.height / 2), with: .color(.white.opacity(NotifyWidget.fillOpacity)))
        drawWords(item.body, at: CGPoint(x: NotifyMetrics.widgetTextX, y: NotifyWidget.textBottom - item.body.size.height), in: content)
        drawRim(card.rect, radius: card.radius, in: graphics)
    }

    /// Soft colour blobs that bloom one after another over the line: the album's colours, or a few tints.
    private func drawBlobs(for item: NotifyItem, in graphics: GraphicsContext) {
        let palette = widgetPalette(seed: item.seed), size = NotifyMetrics.widgetSize
        let shift = Int(seededUnit(item.seed, salt: NotifySalt.blobOrder) * Double(palette.count))
        let duration = max(NotifyWidget.blobMinDuration, item.end - item.start)
        for index in palette.indices {
            let spot = NotifyWidget.blobSpots[index % NotifyWidget.blobSpots.count]
            let delay = NotifyWidget.blobDelay + NotifyWidget.blobSpread * duration * Double(index) / Double(max(palette.count, 2) - 1)
            let bloom = NotifyMath.smooth((position - item.start - delay) / NotifyWidget.blobBloom)
            guard bloom > 0 else { continue }
            let radius = spot.radius * size.height * (NotifyWidget.blobSmall + (1 - NotifyWidget.blobSmall) * bloom)
            let center = CGPoint(x: spot.x * size.width, y: spot.y * size.height)
            let color = palette[(index + shift) % palette.count]
            let stops = [Gradient.Stop(color: color.opacity(NotifyWidget.blobCore * bloom), location: 0),
                         Gradient.Stop(color: color.opacity(NotifyWidget.blobMid * bloom), location: NotifyWidget.blobMidStop),
                         Gradient.Stop(color: color.opacity(0), location: 1)]
            graphics.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                          with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: radius))
        }
    }

    private func widgetPalette(seed: Double) -> [Color] {
        if let artwork, !artwork.isEmpty { return artwork.map { Color(nsColor: $0) } }
        let tints = NotifyTables.tints
        let first = Int(seededUnit(seed, salt: NotifySalt.paletteStart) * Double(tints.count))
        return NotifyWidget.fallbackSteps.map { tints[(first + $0) % tints.count].mix(with: .white, by: NotifyWidget.fallbackLighten) }
    }

    private func drawWidgetHeader(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        drawGlyph(of: card, size: NotifyWidget.glyphSize, opacity: NotifyWidget.glyphOpacity, at: NotifyWidget.glyphCenter, in: graphics)
        let time = graphics.resolve(label(Self.clock(position), size: NotifyWidget.headerSize, weight: .medium, opacity: NotifyWidget.timeOpacity,
                                          fixedDigits: true))
        graphics.draw(time, at: NotifyWidget.timeCorner, anchor: .topTrailing)
        // The title gives way to the time: it is cut off where the time begins.
        let room = NotifyWidget.titleClip
        let clip = CGRect(x: room.minX, y: room.minY, width: room.width - time.measure(in: NotifyMetrics.widgetSize).width, height: room.height)
        let heading = label(title.isEmpty ? NotifyWidget.titleFallback : title, size: NotifyWidget.headerSize, weight: .semibold,
                            opacity: NotifyWidget.titleOpacity)
        graphics.clipped(to: Path(clip)).draw(heading, at: NotifyWidget.titleOrigin, anchor: .topLeading)
    }

    /// How far through this line the song is (not through the track): the mean progress of its words.
    private func lineProgress(of item: NotifyItem) -> Double {
        guard position < item.end + NotifyWidget.progressTail, !item.words.isEmpty else { return 1 }
        let total = item.words.reduce(0.0) { $0 + NotifyMath.smooth((position - $1.start) / max($1.end - $1.start, NotifyWidget.progressMinWord)) }
        return total / Double(item.words.count)
    }

    // MARK: Glance

    private func drawGlance(_ card: NotifyCardPose, in graphics: GraphicsContext) {
        let content = graphics.fitted(to: card.rect, designWidth: NotifyMetrics.glanceSize.width)
        let dim = NotifyLook.secondary
        drawSymbol(NotifyTables.glanceSymbol, size: NotifyGlance.captionSize, opacity: dim, at: NotifyGlance.noteCenter, in: content)
        content.fill(Path(NotifyGlance.divider), with: .color(.white.opacity(dim)))
        content.draw(label(NotifyGlance.caption, size: NotifyGlance.captionSize, weight: .heavy, opacity: dim),
                     at: NotifyGlance.captionOrigin, anchor: .topLeading)
        let rows = [(title.isEmpty ? NotifyGlance.untitled : title, NotifyGlance.primary), (artist, dim), (Self.clock(position), dim)]
            .filter { !$0.0.isEmpty }
        let clipped = content.clipped(to: Path(NotifyGlance.rowsClip))
        for (index, row) in rows.enumerated() {
            let corner = CGPoint(x: NotifyGlance.rowsOrigin.x, y: NotifyGlance.rowsOrigin.y + NotifyGlance.rowPitch * CGFloat(index))
            clipped.draw(label(row.0, size: NotifyGlance.rowSize, weight: .medium, opacity: row.1, fixedDigits: true), at: corner, anchor: .topLeading)
        }
        drawCountdown(card.item, in: content)
        drawSongGauge(in: content)
    }

    private func drawDisc(at center: CGPoint, in graphics: GraphicsContext) {
        let side = NotifyGlance.discSide
        graphics.fill(Path(ellipseIn: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)),
                      with: .color(Color(white: NotifyGlance.discShade).opacity(NotifyGlance.discOpacity)))
    }

    private func drawArc(at center: CGPoint, from start: Double, sweep: Double, opacity: Double, in graphics: GraphicsContext) {
        guard sweep > 0 else { return }
        let arc = Path {
            $0.addArc(center: center, radius: NotifyGlance.arcRadius, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
        }
        graphics.stroke(arc, with: .color(.white.opacity(opacity)), style: StrokeStyle(lineWidth: NotifyGlance.arcWidth, lineCap: .round))
    }

    /// A ring that fills as the silence runs out, with the seconds left until the next line.
    private func drawCountdown(_ item: NotifyItem, in graphics: GraphicsContext) {
        let center = NotifyGlance.countdownCenter
        let elapsed = min(max((position - item.start) / max(item.end - item.start, NotifyGlance.minSpan), 0), 1)
        drawDisc(at: center, in: graphics)
        drawArc(at: center, from: NotifyGlance.top, sweep: NotifyGlance.turn, opacity: NotifyGlance.trackOpacity, in: graphics)
        drawArc(at: center, from: NotifyGlance.top, sweep: NotifyGlance.turn * elapsed, opacity: NotifyGlance.arcOpacity, in: graphics)
        guard position < item.end else {
            return drawSymbol(NotifyTables.glanceSymbol, size: NotifyGlance.noteSize, age: position - item.end, at: center, in: graphics)
        }
        let seconds = Int((item.end - position).rounded(.up))
        graphics.draw(label("\(seconds)", size: NotifyGlance.countdownSize, weight: .semibold, design: .rounded), at: center)
    }

    /// How far through the song's lyrics the playback is.
    private func drawSongGauge(in graphics: GraphicsContext) {
        let center = NotifyGlance.songCenter
        let progress = feed.plan.length > 0 ? min(max(position / feed.plan.length, 0), 1) : 0
        drawDisc(at: center, in: graphics)
        drawArc(at: center, from: NotifyGlance.sweepStart, sweep: NotifyGlance.sweep, opacity: NotifyGlance.trackOpacity, in: graphics)
        drawArc(at: center, from: NotifyGlance.sweepStart, sweep: NotifyGlance.sweep * progress, opacity: NotifyGlance.arcOpacity, in: graphics)
        graphics.draw(label("\(Int(progress * 100))%", size: NotifyGlance.percentSize, weight: .semibold, design: .rounded),
                      at: CGPoint(x: center.x, y: center.y - NotifyGlance.percentRise))
        drawSymbol(NotifyTables.glanceSymbol, size: NotifyGlance.smallNote, at: CGPoint(x: center.x, y: center.y + NotifyGlance.smallNoteDrop),
                   in: graphics)
    }
}
