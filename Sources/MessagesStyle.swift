import AppKit
import SwiftUI

/// Messages: the song as a chat thread on a transparent background. Every lyric line is one bubble (grey
/// incoming on the left, blue outgoing on the right) that grows out of a typing bubble, and its words appear
/// one at a time as they are sung. The thread is drawn on a virtual 402-unit-wide sheet scaled to the screen.
/// Nothing is animated by SwiftUI: each frame is a closed-form function of the playback position and the
/// wall clock, worked out from the whole song rather than the active line, so it also holds through gaps.
struct MessagesStyle: View {
    let context: StyleContext

    var body: some View {
        let width = context.canvas.width
        let unit = min(context.band * Metrics.unitPerBand * context.settings.textScale, width * Metrics.sheetShare / Metrics.sheetWidth)
        // A window that has no size yet has no scale to draw at.
        let thread = unit > 0 ? MessageThread(plan: MessagesPlan.cached(for: context.lyrics), position: context.position,
                                              clock: context.clock, height: context.band / unit,
                                              motion: context.settings.reduceMotion ? 0 : 1) : nil
        if let thread, !thread.isBlank {
            sheet(thread, unit: unit)
        } else {
            Color.clear.frame(width: width, height: context.band)
        }
    }

    @ViewBuilder private func sheet(_ thread: MessageThread, unit: CGFloat) -> some View {
        let width = context.canvas.width, scale = unit * thread.jolt.zoom
        // The zoom pulse is anchored at the middle of the newest bubble's baseline.
        let origin = CGPoint(x: unit * thread.jolt.offset.dx + width / 2 - scale * Metrics.sheetWidth / 2,
                             y: unit * thread.jolt.offset.dy + (1 - thread.jolt.zoom) * unit * thread.bottom)
        let smear = min(Metrics.smearCap, unit * abs(thread.scrollVelocity) * Metrics.smearGain)
        let canvas = Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, _ in
            var sheet = graphics
            sheet.translateBy(x: origin.x, y: origin.y)
            sheet.scaleBy(x: scale, y: scale)
            thread.draw(in: sheet)
        }
        .frame(width: width, height: context.band)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: Metrics.topFade)],
                             startPoint: .top, endPoint: .bottom))
        .opacity(thread.opacity)
        .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
        // Stands in for a vertical motion blur, which needs a Metal shader this project cannot compile. A thread
        // at rest gets no blur at all rather than one of radius 0, which may still cost a full-width pass.
        if smear > Metrics.smearThreshold { canvas.blur(radius: smear * Metrics.smearSoftness) } else { canvas }
    }
}

private enum Metrics {
    // Sheet (lengths are sheet units unless noted)
    static let sheetWidth: CGFloat = 402, leftEdge: CGFloat = 16, rightEdge: CGFloat = 386
    static let unitPerBand = 0.125 / 40, sheetShare = 0.94      // points per unit: of the band, of the canvas width
    static let baselineLow = 0.55, baselineHigh = 0.76, baselineRoom: CGFloat = 80
    static let overscan: CGFloat = 20
    static let topFade = 0.12
    static let shadowOpacity = 0.32, shadowRadius = 14.0, shadowY = 5.0
    static let smearGain = 0.9, smearCap = 26.0, smearThreshold = 0.75, smearSoftness = 0.1, frame = 1.0 / 60
    static let blankOpacity = 0.002
    static let cachedPlans = 2

    // Plan
    static let sideGap = 0.7, longestRun = 3, flipChance = 0.25
    static let typingGap = 1.0, typingDelay = 0.25, typingLeadCap = 2.4
    static let stampGap = 12.0
    static let emphasisRatio = 1.6, emphasisWeight = 1.7, minDuration = 0.01
    static let settleAfterEnd = 0.4, settleAfterStart = 1.2
    // The same ranges as the Notifications style, so both join the same neighbours without a space.
    static let cjk: [ClosedRange<UInt32>] = [0x2E80...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF]

    // Bubbles
    static let wrapWidth: CGFloat = 272, rowHeight: CGFloat = 20
    static let padding = CGSize(width: 28, height: 20), minWidth: CGFloat = 40, maxWidth = rightEdge - leftEdge
    static let textInset = CGPoint(x: 14, y: 10)
    static let cornerRadius: CGFloat = 20
    static let gapStamp: CGFloat = 35, gapOtherSide: CGFloat = 10, gapSameSide: CGFloat = 2
    static let scrollSpring = Bounce(response: 0.5, damping: 0.8), growthSpring = Bounce(response: 0.42, damping: 0.6)
    static let popStart = 0.3, popFade = 0.06                   // a bubble with no typing lead
    static let entryBlur = 5.0, entryBlurLife = 0.16
    static let settledTolerance: CGFloat = 0.5
    static let tailFade = 0.16, tailGrowthStart = 0.55, tailGrowthSpan = 0.35, tailThreshold = 0.01

    // Shivers
    static let shiverAttack = 0.025, shiverDecay = 0.17, shiverSpeed = 12.0
    static let crestPhase = 1.115                               // radians into a shiver at which it first peaks
    static let wobbleDegrees = 6.2, squash = 0.078, squashSpeed = 16.8, squashY = 0.7
    static let ripple = 3.0, rippleDelay = 0.035
    static let landingZoom = 0.045, echoZoom = 0.027, zoomSpeed = 15.6, zoomDeadZone = 0.0004
    static let ringLife = 0.5, ringSpread: CGFloat = 16, ringWidth = 1.6, ringMinWidth = 0.6
    static let ringOpacity = 0.45, ringFadePower = 1.5, ringWhite = 0.55, echoStrength = 0.9

    // Words
    static let wordSpring = Bounce(response: 0.32, damping: 0.57), wordRise = 14.0
    static let popDecay = 0.12, popSpeed = 17.0, popDepth = 0.5, popFloor = 0.05
    static let holdAttack = 0.08, holdRelease = 4.0, holdScale = 0.07, holdLift = 1.2
    static let tiltDegrees = 8.0, tiltFullWidth: CGFloat = 44, tiltEmphasis = 1.3
    static let wordFade = 0.06, wordBlur = 2.5, wordBlurLife = 0.1
    static let kickLife = 1.5, kickReach = 1.9, kickDeadZone = 0.02
    static let nudgeSpeed = 17.0, nudgeDecay = 0.12, kickSwell = 0.032, kickDegrees = 1.8

    // Typing bubble
    static let typingSize = CGSize(width: 58, height: 36)
    static let typingSpring = Bounce(response: 0.37, damping: 0.6)
    static let typingBreath = 0.025, typingBreathSpeed = 3.1, typingTilt = 7.0, typingFade = 0.08
    static let thoughtLarge = (diameter: 12.0, inset: 4.0, rise: 3.5), thoughtSmall = (diameter: 5.5, inset: -3.5, rise: -3.5)
    static let dotSpeed = 5.236, dotLag = 0.85, dotDiameter = 8.5, dotSpacing = 13.0, dotLift = 2.4
    static let dotOpacity = 0.42, dotGlow = 0.5, dotsFade = 0.1

    // Stamp and receipt
    static let captionSize: CGFloat = 11, captionOpacity = 0.62
    static let stampRise: CGFloat = 17.5, stampFade = 0.35
    static let receiptX: CGFloat = 382, receiptDrop: CGFloat = 4, receiptDelay = 0.2, receiptFade = 0.12
    static let receiptSpring = Bounce(response: 0.31, damping: 0.62), readDelay = 0.35, ownTypingFade = 0.15

    // Gaps and the end of the song
    static let dimAfter = 5.0, dimRamp = 2.0, dimDepth = 0.45, wakeBefore = 2.0, wakeRamp = 0.8
    static let endAfter = 4.0, endRamp = 2.5
}

/// The tail: a small hook hanging under the bottom corner on the sender's side. Offsets from that corner,
/// x pointing into the bubble and y down.
private enum Tail {
    static let root = CGPoint(x: 25, y: -1), belly = CGPoint(x: 12, y: 1.5)
    static let tip = CGPoint(x: 3.2, y: 6.6), bend = CGPoint(x: 0.9, y: 7.2), nib = CGPoint(x: 2.2, y: 4.4)
    static let back = CGPoint(x: 6.4, y: 0.5), shoulder = CGPoint(x: 7, y: -10)
    static let pivot = CGPoint(x: 20, y: -2)
}

private enum Salt {
    static let side: UInt64 = 0x4D51, tilt: UInt64 = 0x4D52, kickAngle: UInt64 = 0x4D53, kickTurn: UInt64 = 0x4D54
}

private enum Palette {
    static let outgoing = Color(.sRGB, red: 0, green: 0.5333, blue: 1)
    static let incoming = Color(.sRGB, red: 0.149, green: 0.149, blue: 0.1608)
    static let text = Color.white
    static let caption = Color.white.opacity(Metrics.captionOpacity)
}

private enum Fonts {
    /// Rows are measured and drawn with the same font, so a word never shifts when its row settles.
    static let measuring = NSFont.systemFont(ofSize: 17)
    static let bubble = Font(measuring as CTFont)
    static let caption = Font.system(size: Metrics.captionSize)
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private func unit(_ value: Double) -> Double { min(max(value, 0), 1) }
private func smooth(_ value: Double) -> Double { unit(value) * unit(value) * (3 - 2 * unit(value)) }  // smoothstep

/// The step response of a damped spring: 0 until `time` 0, then overshooting and settling on 1.
private struct Bounce {
    let response: Double, damping: Double

    func value(at time: Double) -> Double {
        guard time > 0 else { return 0 }
        let omega = 2 * Double.pi / response, damped = omega * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * omega * time) * (cos(damped * time) + damping * omega / damped * sin(damped * time))
    }
}

/// A quick shiver that dies away; 0 before `time` 0.
private func shiver(_ time: Double, speed: Double, decay: Double = Metrics.shiverDecay) -> Double {
    guard time > 0 else { return 0 }
    return (1 - exp(-time / Metrics.shiverAttack)) * sin(speed * time) * exp(-time / decay)
}

/// A shiver scaled so that its first crest is about 1.
private func crest(_ time: Double, speed: Double, decay: Double = Metrics.shiverDecay) -> Double {
    shiver(time, speed: speed, decay: decay) * exp(Metrics.crestPhase / speed / decay) / sin(Metrics.crestPhase)
}

// MARK: Plan

/// The part that depends only on the song: who "sends" each line and how its text wraps.
struct MessagesPlan {
    struct Word {
        let text: String
        let start: Double, end: Double
        let x: CGFloat, width: CGFloat
        let row: Int
        /// Held much longer than its neighbours, so it lands harder.
        let isEmphasized: Bool
        /// -1 or 1: which way the word tips as it pops.
        let tilt: Double
        /// From here on the word is drawn plain.
        let settle: Double

        var weight: Double { isEmphasized ? Metrics.emphasisWeight : 1 }
    }

    struct Message {
        let isOutgoing: Bool
        let start: Double, end: Double
        /// How long the typing bubble shows before the line; 0 for none.
        let typingLead: Double
        let hasStamp: Bool
        let gapAbove: CGFloat
        let words: [Word]
        let rows: [String]
        let size: CGSize
        /// An unbroken word wider than the sheet: its text is cut off at the bubble's edge.
        let isCutOff: Bool
        let settle: Double
    }

    /// What the plan was made from. The cache compares it whole, so corrected lyrics of the same shape get a new plan.
    let lyrics: TimedLyrics
    let messages: [Message]

    init(lyrics: TimedLyrics) {
        self.lyrics = lyrics
        var messages: [Message] = []
        var isOutgoing = false, run = 0, previousEnd = 0.0
        for line in lyrics.lines {
            // An empty word would leave a doubled space in its row.
            let line = line.filter { !$0.text.isEmpty }
            // Overlapping voices need not be in time order: a line spans its earliest start to its latest end.
            guard let start = line.map(\.start).min(), let end = line.map(\.end).max() else { continue }
            let gap = start - previousEnd
            let flips = !messages.isEmpty && (gap >= Metrics.sideGap || run >= Metrics.longestRun
                                              || seededUnit(start, salt: Salt.side) < Metrics.flipChance)
            if flips { (isOutgoing, run) = (!isOutgoing, 0) }
            run += 1
            previousEnd = end
            messages.append(Self.message(line, from: start, to: end, isOutgoing: isOutgoing, gap: gap, after: messages.last))
        }
        self.messages = messages
    }

    /// Plans are kept for the two most recent songs so the layout is not redone every frame. Main thread only.
    @MainActor private static var recent: [MessagesPlan] = []

    @MainActor static func cached(for lyrics: TimedLyrics) -> MessagesPlan {
        // Arrays that share storage compare without looking at their elements, which is the case on every frame of a song.
        if let known = recent.first(where: { $0.lyrics == lyrics }) { return known }
        let plan = MessagesPlan(lyrics: lyrics)
        recent = [plan] + recent.prefix(Metrics.cachedPlans - 1)
        return plan
    }

    /// The newest message that has started, if any. Not a binary search: starts need not be in order (see `init`).
    func index(at position: Double) -> Int? { messages.lastIndex { $0.start <= position } }

    /// How far the thread still has to slide up to make room for message `index`.
    func scroll(for index: Int, at position: Double) -> CGFloat {
        let message = messages[index]
        return (1 - Metrics.scrollSpring.value(at: position - message.start)) * (message.size.height + message.gapAbove)
    }

    private static func message(_ line: [TimedWord], from start: Double, to end: Double, isOutgoing: Bool, gap: Double,
                                after previous: Message?) -> Message {
        let (words, rows) = layOut(line)
        let hasStamp = previous == nil || gap >= Metrics.stampGap
        let gapAbove = hasStamp ? Metrics.gapStamp : previous?.isOutgoing == isOutgoing ? Metrics.gapSameSide : Metrics.gapOtherSide
        let width = max(Metrics.minWidth, (rows.map(measure).max() ?? 0) + Metrics.padding.width)
        return Message(isOutgoing: isOutgoing, start: start, end: end,
                       typingLead: gap < Metrics.typingGap ? 0 : min(gap - Metrics.typingDelay, Metrics.typingLeadCap),
                       hasStamp: hasStamp, gapAbove: gapAbove, words: words, rows: rows,
                       size: CGSize(width: min(width, Metrics.maxWidth),
                                    height: CGFloat(rows.count) * Metrics.rowHeight + Metrics.padding.height),
                       isCutOff: width > Metrics.maxWidth, settle: words.map(\.settle).max() ?? 0)
    }

    /// Greedy word wrap; every word remembers where it sits so it can be drawn on its own while it is sung.
    private static func layOut(_ line: [TimedWord]) -> (words: [Word], rows: [String]) {
        let mean = line.reduce(0) { $0 + max(Metrics.minDuration, $1.end - $1.start) } / Double(line.count)
        var words: [Word] = [], rows = [""]
        for (index, word) in line.enumerated() {
            let row = rows[rows.count - 1]
            let joiner = row.isEmpty || isUnspaced(line[index - 1].text, word.text) ? "" : " "
            let wraps = !row.isEmpty && measure(row + joiner + word.text) > Metrics.wrapWidth
            let prefix = wraps ? "" : row + joiner
            if wraps { rows.append(word.text) } else { rows[rows.count - 1] = prefix + word.text }
            words.append(Word(text: word.text, start: word.start, end: word.end, x: measure(prefix), width: measure(word.text),
                              row: rows.count - 1,
                              isEmphasized: line.count != 1 && word.end - word.start >= Metrics.emphasisRatio * mean,
                              tilt: seededUnit(word.start, salt: Salt.tilt) < 0.5 ? -1 : 1,
                              settle: max(word.end + Metrics.settleAfterEnd, word.start + Metrics.settleAfterStart)))
        }
        return (words, rows)
    }

    private static func measure(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: Fonts.measuring]).width
    }

    /// Chinese, Japanese and full-width neighbours are written without a space between them.
    private static func isUnspaced(_ left: String, _ right: String) -> Bool {
        func isCJK(_ scalar: Unicode.Scalar?) -> Bool {
            scalar.map { scalar in Metrics.cjk.contains { $0.contains(scalar.value) } } ?? false
        }
        return isCJK(left.unicodeScalars.last) && isCJK(right.unicodeScalars.first)
    }
}

// MARK: Thread

/// The knocks that the words of the newest line give the thread and their own bubble.
private struct Jolt {
    let offset: CGVector
    /// Added to the newest bubble's scale and rotation.
    let swell: Double, degrees: Double
    let zoom: Double
    /// Ages of emphasised words that landed within the last half second; each re-fires the ring.
    let echoes: [Double]

    init(newest: MessagesPlan.Message?, position: Double, motion: Double) {
        typealias Word = MessagesPlan.Word
        let live = (newest?.words ?? []).map { (word: $0, age: position - $0.start) }.filter { $0.age > 0 && $0.age < Metrics.kickLife }
        func sum(_ term: (Word, Double) -> Double) -> Double { motion * live.reduce(0) { $0 + term($1.word, $1.age) } }
        func push(_ word: Word, _ age: Double) -> Double { Metrics.kickReach * word.weight * crest(age, speed: Metrics.shiverSpeed) }
        func nudge(_ word: Word, _ age: Double) -> Double { word.weight * crest(age, speed: Metrics.nudgeSpeed, decay: Metrics.nudgeDecay) }
        func angle(_ word: Word) -> Double { 2 * Double.pi * seededUnit(word.start, salt: Salt.kickAngle) }
        let reach = CGVector(dx: sum { push($0, $1) * cos(angle($0)) }, dy: sum { push($0, $1) * sin(angle($0)) })
        let echoes = motion > 0 ? live.filter { $0.word.isEmphasized && $0.age < Metrics.ringLife }.map(\.age) : []
        let landing = Metrics.landingZoom * shiver(newest.map { position - $0.start } ?? 0, speed: Metrics.zoomSpeed)
        let pulse = motion * echoes.reduce(landing) { $0 + Metrics.echoZoom * shiver($1, speed: Metrics.zoomSpeed) }
        offset = hypot(reach.dx, reach.dy) < Metrics.kickDeadZone ? .zero : reach
        swell = Metrics.kickSwell * sum(nudge)
        degrees = Metrics.kickDegrees * sum { (seededUnit($0.start, salt: Salt.kickTurn) - 0.5) * nudge($0, $1) }
        zoom = abs(pulse) < Metrics.zoomDeadZone ? 1 : 1 + pulse
        self.echoes = echoes
    }
}

/// Everything on the sheet at one instant, in sheet units.
private struct MessageThread {
    struct Bubble {
        let message: MessagesPlan.Message
        let age: Double
        /// Where the bubble rests, scroll and ripple included.
        let frame: CGRect
        /// 1 while this is the last bubble of its same-side run.
        let tailPresence: Double
        let isNewest: Bool
    }

    struct Typing {
        let isOutgoing: Bool, age: Double, frame: CGRect
    }

    struct Receipt {
        let text: String, opacity: Double, scale: Double, anchor: CGPoint
    }

    let position: Double, clock: Double, motion: Double
    /// The baseline the newest bubble rests on.
    let bottom: CGFloat
    let bubbles: [Bubble]
    let typing: Typing?
    let receipt: Receipt?
    let jolt: Jolt
    let opacity: Double
    /// Sheet units per frame.
    let scrollVelocity: CGFloat

    var isBlank: Bool { opacity < Metrics.blankOpacity || (bubbles.isEmpty && typing == nil) }

    init(plan: MessagesPlan, position: Double, clock: Double, height: CGFloat, motion: Double) {
        let messages = plan.messages, current = plan.index(at: position)
        let newest = current.map { messages[$0] }
        let upcoming = messages.indices.contains((current ?? -1) + 1) ? messages[(current ?? -1) + 1] : nil
        let bottom = max(Metrics.baselineLow * height, min(Metrics.baselineHigh * height, height - Metrics.baselineRoom))
        let scroll = current.map { plan.scroll(for: $0, at: position) } ?? 0
        let typing = upcoming.flatMap { Self.typing(before: $0, floor: bottom + scroll, position: position) }
        self.position = position
        self.clock = clock
        self.motion = motion
        self.bottom = bottom
        self.typing = typing
        bubbles = current.map { Self.stack(messages, newest: $0, floor: bottom + scroll, position: position, motion: motion) } ?? []
        receipt = newest.flatMap { Self.receipt(under: $0, typing: typing, floor: bottom + scroll, position: position, motion: motion) }
        jolt = Jolt(newest: newest, position: position, motion: motion)
        opacity = Self.opacity(after: newest, before: upcoming, position: position)
        scrollVelocity = scroll - (current.map { plan.scroll(for: $0, at: position + Metrics.frame) } ?? 0)
    }

    /// Bubbles stacked upwards from `floor` until they leave the top of the sheet; returned oldest first.
    private static func stack(_ messages: [MessagesPlan.Message], newest: Int, floor: CGFloat, position: Double, motion: Double) -> [Bubble] {
        let landed = position - messages[newest].start
        var bubbles: [Bubble] = [], floor = floor
        for index in stride(from: newest, through: 0, by: -1) {
            guard floor > -Metrics.overscan else { break }
            let message = messages[index], depth = newest - index
            // Each older bubble bobs a moment after the one below it.
            let ripple = -Metrics.ripple * motion * shiver(landed - Metrics.rippleDelay * Double(depth), speed: Metrics.shiverSpeed)
            let top = floor - message.size.height
            let handsOver = index < newest && messages[index + 1].isOutgoing == message.isOutgoing
            bubbles.append(Bubble(
                message: message, age: position - message.start,
                frame: CGRect(x: message.isOutgoing ? Metrics.rightEdge - message.size.width : Metrics.leftEdge,
                              y: top + (depth > 0 ? ripple : 0), width: message.size.width, height: message.size.height),
                tailPresence: handsOver ? 1 - unit((position - messages[index + 1].start) / Metrics.tailFade) : 1,
                isNewest: depth == 0))
            floor = top - message.gapAbove
        }
        return bubbles.reversed()
    }

    private static func typing(before message: MessagesPlan.Message, floor: CGFloat, position: Double) -> Typing? {
        let age = position - (message.start - message.typingLead)
        guard message.typingLead > 0, age >= 0 else { return nil }
        let x = message.isOutgoing ? Metrics.rightEdge - Metrics.typingSize.width : Metrics.leftEdge
        return Typing(isOutgoing: message.isOutgoing, age: age,
                      frame: CGRect(origin: CGPoint(x: x, y: floor + message.gapAbove), size: Metrics.typingSize))
    }

    /// "Delivered" under the newest outgoing bubble; "Read" once the other side has been typing for a moment.
    private static func receipt(under message: MessagesPlan.Message, typing: Typing?, floor: CGFloat, position: Double,
                                motion: Double) -> Receipt? {
        let age = position - message.end - Metrics.receiptDelay
        guard message.isOutgoing, age > 0 else { return nil }
        let isRead = typing.map { !$0.isOutgoing && $0.age >= Metrics.readDelay } ?? false
        let ownTyping = typing.map { $0.isOutgoing ? 1 - unit($0.age / Metrics.ownTypingFade) : 1 } ?? 1
        return Receipt(text: isRead ? "Read" : "Delivered", opacity: unit(age / Metrics.receiptFade) * ownTyping,
                       scale: 1 - motion * (1 - Metrics.receiptSpring.value(at: age)),
                       anchor: CGPoint(x: Metrics.receiptX, y: floor + Metrics.receiptDrop))
    }

    /// Dims in a long gap, wakes before the next line, and fades away after the last one.
    private static func opacity(after newest: MessagesPlan.Message?, before upcoming: MessagesPlan.Message?, position: Double) -> Double {
        guard let newest else { return 1 }
        let quiet = position - newest.end
        guard let upcoming else { return 1 - smooth((quiet - Metrics.endAfter) / Metrics.endRamp) }
        return 1 - Metrics.dimDepth * smooth((quiet - Metrics.dimAfter) / Metrics.dimRamp)
            * smooth((upcoming.start - position - Metrics.wakeBefore) / Metrics.wakeRamp)
    }
}

// MARK: Drawing

extension MessageThread {
    /// Stamps first, then bubbles oldest to newest, the typing bubble and the receipt.
    func draw(in graphics: GraphicsContext) {
        bubbles.filter(\.message.hasStamp).forEach { drawStamp(above: $0, in: graphics) }
        bubbles.forEach { drawBubble($0, in: graphics) }
        if let typing { drawTyping(typing, in: graphics) }
        if let receipt { drawReceipt(receipt, in: graphics) }
    }

    private func color(isOutgoing: Bool) -> Color { isOutgoing ? Palette.outgoing : Palette.incoming }

    private func rounded(_ rect: CGRect, radius: CGFloat = Metrics.cornerRadius) -> Path {
        Path(roundedRect: rect, cornerRadius: min(rect.width / 2, rect.height / 2, radius), style: .circular)
    }

    /// `graphics` turned and stretched about `pivot`.
    private func posed(_ graphics: GraphicsContext, about pivot: CGPoint, degrees: Double, scale: CGSize) -> GraphicsContext {
        var posed = graphics
        posed.translateBy(x: pivot.x, y: pivot.y)
        posed.rotate(by: .degrees(degrees))
        posed.scaleBy(x: scale.width, y: scale.height)
        posed.translateBy(x: -pivot.x, y: -pivot.y)
        return posed
    }

    // MARK: Bubbles

    private func drawBubble(_ bubble: Bubble, in graphics: GraphicsContext) {
        let message = bubble.message, age = bubble.age
        let growth = Metrics.growthSpring.value(at: age)
        let shape = shape(of: bubble, growth: growth)
        // The bubble wobbles and squashes about its tail corner as it lands, and again a little with each word.
        let squash = Metrics.squash * motion * shiver(age, speed: Metrics.squashSpeed)
        let swell = bubble.isNewest ? 1 + jolt.swell : 1
        let wobble = (message.isOutgoing ? 1 : -1) * Metrics.wobbleDegrees * motion * crest(age, speed: Metrics.shiverSpeed)
        let pose = posed(graphics, about: CGPoint(x: message.isOutgoing ? bubble.frame.maxX : bubble.frame.minX, y: bubble.frame.maxY),
                         degrees: wobble + (bubble.isNewest ? jolt.degrees : 0),
                         scale: CGSize(width: (1 + squash) * swell, height: (1 - Metrics.squashY * squash) * swell))
        var body = pose
        body.opacity = message.typingLead > 0 ? 1 : unit(age / Metrics.popFade)
        let softness = Metrics.entryBlur * (1 - age / Metrics.entryBlurLife)
        if softness > 0 { body.addFilter(.blur(radius: softness)) }
        // A layer costs an offscreen pass, so only the few frames that blur or fade the whole bubble use one.
        if softness > 0 || body.opacity < 1 {
            body.drawLayer { drawBody(of: bubble, shape: shape, growth: growth, in: $0) }
        } else {
            drawBody(of: bubble, shape: shape, growth: growth, in: body)
        }
        drawRings(around: shape, of: bubble, in: pose)
    }

    /// The bubble's outline right now: it grows out of the typing bubble (top fixed) or pops up from its
    /// bottom edge, always from the sender's side.
    private func shape(of bubble: Bubble, growth: Double) -> CGRect {
        let rest = bubble.frame, grewFromTyping = bubble.message.typingLead > 0
        let start = grewFromTyping ? Metrics.typingSize : CGSize(width: Metrics.popStart * rest.width, height: Metrics.popStart * rest.height)
        let size = CGSize(width: start.width + (rest.width - start.width) * growth, height: start.height + (rest.height - start.height) * growth)
        return CGRect(x: bubble.message.isOutgoing ? rest.maxX - size.width : rest.minX,
                      y: grewFromTyping ? rest.minY : rest.maxY - size.height, width: size.width, height: size.height)
    }

    private func drawBody(of bubble: Bubble, shape: CGRect, growth: Double, in graphics: GraphicsContext) {
        let message = bubble.message, fill = GraphicsContext.Shading.color(color(isOutgoing: message.isOutgoing))
        let outline = rounded(shape)
        let tail = bubble.tailPresence * unit((growth - Metrics.tailGrowthStart) / Metrics.tailGrowthSpan)
        graphics.fill(outline, with: fill)
        if tail > Metrics.tailThreshold { graphics.fill(tailPath(under: shape, isOutgoing: message.isOutgoing, amount: tail), with: fill) }
        if message.typingLead > 0, bubble.age < Metrics.dotsFade {
            drawDots(at: CGPoint(x: shape.midX, y: shape.midY), opacity: 1 - bubble.age / Metrics.dotsFade, in: graphics)
        }
        var text = graphics
        let isSettled = abs(shape.width - bubble.frame.width) <= Metrics.settledTolerance
            && abs(shape.height - bubble.frame.height) <= Metrics.settledTolerance
        if !isSettled || message.isCutOff { text.clip(to: outline) }
        drawText(of: message, at: CGPoint(x: shape.minX + Metrics.textInset.x, y: bubble.frame.minY + Metrics.textInset.y), in: text)
    }

    private func tailPath(under shape: CGRect, isOutgoing: Bool, amount: Double) -> Path {
        let corner = CGPoint(x: isOutgoing ? shape.maxX : shape.minX, y: shape.maxY), inward: CGFloat = isOutgoing ? -1 : 1
        func point(_ offset: CGPoint) -> CGPoint {
            CGPoint(x: corner.x + inward * (Tail.pivot.x + (offset.x - Tail.pivot.x) * amount),
                    y: corner.y + Tail.pivot.y + (offset.y - Tail.pivot.y) * amount)
        }
        return Path { path in
            path.move(to: point(Tail.root))
            path.addQuadCurve(to: point(Tail.tip), control: point(Tail.belly))
            path.addQuadCurve(to: point(Tail.nib), control: point(Tail.bend))
            path.addQuadCurve(to: point(Tail.shoulder), control: point(Tail.back))
            path.closeSubpath()
        }
    }

    /// An outline that spreads from the bubble as it lands, and again for every long-held word.
    private func drawRings(around shape: CGRect, of bubble: Bubble, in graphics: GraphicsContext) {
        guard motion > 0 else { return }
        let tint = bubble.message.isOutgoing ? Palette.outgoing : Palette.text.opacity(Metrics.ringWhite)
        let echoes = bubble.isNewest ? jolt.echoes.map { (age: $0, strength: Metrics.echoStrength) } : []
        for ring in [(age: bubble.age, strength: 1.0)] + echoes where ring.age < Metrics.ringLife {
            let remaining = 1 - ring.age / Metrics.ringLife
            let spread = Metrics.ringSpread * (1 - remaining * remaining * remaining)
            let outline = rounded(shape.insetBy(dx: -spread, dy: -spread), radius: Metrics.cornerRadius + spread)
            graphics.stroke(outline, with: .color(tint.opacity(Metrics.ringOpacity * ring.strength * pow(remaining, Metrics.ringFadePower))),
                            lineWidth: Metrics.ringWidth * remaining + Metrics.ringMinWidth)
        }
    }

    // MARK: Text

    private func label(_ text: String, in graphics: GraphicsContext) -> GraphicsContext.ResolvedText {
        graphics.resolve(Text(text).font(Fonts.bubble).foregroundStyle(Palette.text))
    }

    /// Whole rows once the line has settled; before that only the words sung so far, each on its own.
    private func drawText(of message: MessagesPlan.Message, at origin: CGPoint, in graphics: GraphicsContext) {
        guard position < message.settle else {
            for (row, text) in message.rows.enumerated() {
                graphics.draw(label(text, in: graphics), at: CGPoint(x: origin.x, y: origin.y + CGFloat(row) * Metrics.rowHeight),
                              anchor: .topLeading)
            }
            return
        }
        for word in message.words {
            guard position >= word.start else { return }
            drawWord(word, at: CGPoint(x: origin.x + word.x, y: origin.y + CGFloat(word.row) * Metrics.rowHeight), in: graphics)
        }
    }

    /// A word pops in from below, de-blurs, and stays slightly swollen and lifted while it is being sung.
    private func drawWord(_ word: MessagesPlan.Word, at corner: CGPoint, in graphics: GraphicsContext) {
        let age = position - word.start, text = label(word.text, in: graphics)
        guard position < word.settle else { return graphics.draw(text, at: corner, anchor: .topLeading) }
        let ring = exp(-age / Metrics.popDecay) * cos(Metrics.popSpeed * age)
        let pop = max(Metrics.popFloor, 1 - Metrics.popDepth * word.weight * ring * motion)
        let hold = min(age / Metrics.holdAttack, 1) * (1 - smooth((position - word.end) * Metrics.holdRelease))
        let scale = (1 + Metrics.holdScale * word.weight * hold * motion) * pop
        let degrees = word.tilt * Metrics.tiltDegrees * motion * ring * min(Metrics.tiltFullWidth / word.width, 1)
            * (word.isEmphasized ? Metrics.tiltEmphasis : 1)
        let drop = Metrics.wordRise * (1 - Metrics.wordSpring.value(at: age)) - Metrics.holdLift * hold * motion
        // The left edge stays put; the word turns and swells about the middle of its row.
        var layer = posed(graphics, about: CGPoint(x: corner.x, y: corner.y + drop + Metrics.rowHeight / 2), degrees: degrees,
                          scale: CGSize(width: scale, height: scale))
        if age < Metrics.wordBlurLife {
            layer.opacity = unit(age / Metrics.wordFade)
            layer.addFilter(.blur(radius: Metrics.wordBlur * (1 - age / Metrics.wordBlurLife)))
        }
        layer.draw(text, at: CGPoint(x: corner.x, y: corner.y + drop), anchor: .topLeading)
    }

    // MARK: Typing bubble, stamp, receipt

    private func drawTyping(_ typing: Typing, in graphics: GraphicsContext) {
        let frame = typing.frame, side: CGFloat = typing.isOutgoing ? 1 : -1
        let edge = CGPoint(x: typing.isOutgoing ? frame.maxX : frame.minX, y: frame.maxY)
        let scale = Metrics.typingSpring.value(at: typing.age) * (1 + Metrics.typingBreath * motion * sin(Metrics.typingBreathSpeed * clock))
        let tilt = side * Metrics.typingTilt * motion * exp(-typing.age / Metrics.shiverDecay) * cos(Metrics.shiverSpeed * typing.age)
        var layer = posed(graphics, about: edge, degrees: tilt, scale: CGSize(width: scale, height: scale))
        layer.opacity = unit(typing.age / Metrics.typingFade)
        let fill = GraphicsContext.Shading.color(color(isOutgoing: typing.isOutgoing))
        layer.fill(rounded(frame), with: fill)
        for thought in [Metrics.thoughtLarge, Metrics.thoughtSmall] {
            layer.fill(Path(ellipseIn: CGRect(x: edge.x - side * thought.inset - thought.diameter / 2,
                                              y: edge.y - thought.rise - thought.diameter / 2,
                                              width: thought.diameter, height: thought.diameter)), with: fill)
        }
        drawDots(at: CGPoint(x: frame.midX, y: frame.midY), opacity: 1, in: layer)
    }

    /// Three dots bouncing one after another, on the wall clock so they keep going while the music waits.
    private func drawDots(at center: CGPoint, opacity: Double, in graphics: GraphicsContext) {
        for dot in 0..<3 {
            let bounce = max(0, sin(clock * Metrics.dotSpeed - Metrics.dotLag * Double(dot)))
            let rect = CGRect(x: center.x + Double(dot - 1) * Metrics.dotSpacing - Metrics.dotDiameter / 2,
                              y: center.y - Metrics.dotLift * bounce - Metrics.dotDiameter / 2,
                              width: Metrics.dotDiameter, height: Metrics.dotDiameter)
            graphics.fill(Path(ellipseIn: rect), with: .color(Palette.text.opacity((Metrics.dotOpacity + Metrics.dotGlow * bounce) * opacity)))
        }
    }

    /// "Today" and the real time of day at which the bubble below it appeared.
    private func drawStamp(above bubble: Bubble, in graphics: GraphicsContext) {
        let time = Fonts.time.string(from: Date(timeIntervalSinceReferenceDate: clock - bubble.age))
        let stamp = Text("\(Text("Today").fontWeight(.semibold)) \(time)").font(Fonts.caption).foregroundStyle(Palette.caption)
        var layer = graphics
        layer.opacity = unit(bubble.age / Metrics.stampFade)
        layer.draw(stamp, at: CGPoint(x: Metrics.sheetWidth / 2, y: bubble.frame.minY - Metrics.stampRise), anchor: .center)
    }

    private func drawReceipt(_ receipt: Receipt, in graphics: GraphicsContext) {
        var layer = posed(graphics, about: receipt.anchor, degrees: 0, scale: CGSize(width: receipt.scale, height: receipt.scale))
        layer.opacity = receipt.opacity
        layer.draw(Text(receipt.text).font(Fonts.caption.weight(.semibold)).foregroundStyle(Palette.caption), at: receipt.anchor,
                   anchor: .topTrailing)
    }
}

// MARK: Self-check

/// Checks of the plan rules, in the form `runSelfCheck` expects: one message per failure.
func messagesStyleSelfCheck() -> [String] {
    func line(_ number: Int, from start: Double, _ texts: [String]) -> [TimedWord] {
        texts.enumerated().map { TimedWord(text: $1, start: start + 0.4 * Double($0), end: start + 0.4 * Double($0) + 0.35, line: number) }
    }
    // Two words, then after 1.25 s a line long enough to wrap, then after a long silence a Chinese line.
    let words = line(0, from: 1, ["hi", "there"]) + line(1, from: 3, Array(repeating: "everything", count: 9)) + line(2, from: 20, ["你", "好"])
    let plan = MessagesPlan(lyrics: TimedLyrics(tier: .wordLevel, words: words))
    let wrapped = plan.messages[1]
    let leads = zip(plan.messages.map(\.typingLead), [0.75, 1, 2.4]).allSatisfy { abs($0 - $1) < 0.0001 }
    // The same word count, first start and last end as `words`, with one word corrected.
    let corrected = words.map { TimedWord(text: $0.text == "there" ? "world" : $0.text, start: $0.start, end: $0.end, line: $0.line) }
    // The self-check runs on the main thread, where the plan cache lives.
    let cachedRows = MainActor.assumeIsolated {
        [words, corrected, words].map { MessagesPlan.cached(for: TimedLyrics(tier: .wordLevel, words: $0)).messages[0].rows }
    }
    // A duet: the third line is listed after the second but starts before it, and its own words are out of order too.
    let duet = MessagesPlan(lyrics: TimedLyrics(tier: .wordLevel, words: line(0, from: 1, ["one"]) + line(1, from: 10, ["two"]) + [
        TimedWord(text: "late", start: 8.5, end: 8.8, line: 2), TimedWord(text: "early", start: 8, end: 9.5, line: 2)]))
    let odd = MessagesPlan(lyrics: TimedLyrics(tier: .wordLevel, words: line(0, from: 1, ["a", "", "b", String(repeating: "w", count: 80)])))
    let checks: [(Bool, String)] = [
        (cachedRows == [["hi there"], ["hi world"], ["hi there"]], "messages: lyrics of the same shape but different words get their own plan"),
        (duet.index(at: 0.5) == nil && duet.index(at: 9) == 2 && duet.index(at: 11) == 2 && duet.messages[2].start == 8
            && duet.messages[2].end == 9.5, "messages: a line that starts before the one listed ahead of it is still found"),
        (odd.messages[0].rows.first == "a b" && odd.messages[0].size.width == Metrics.maxWidth && odd.messages[0].isCutOff
            && !wrapped.isCutOff, "messages: an empty word leaves no doubled space and an over-wide word stays on the sheet"),
        (plan.messages.map(\.isOutgoing) == [false, true, false], "messages: the song starts incoming and a pause changes sides"),
        (leads, "messages: typing lead is the gap less a quarter second, capped, and absent for the shortest gaps"),
        (plan.messages.map(\.hasStamp) == [true, false, true], "messages: a stamp before the first line and after a long silence"),
        (wrapped.rows.count > 1 && wrapped.size.width <= Metrics.wrapWidth + Metrics.padding.width
            && wrapped.words.allSatisfy { $0.x + $0.width <= Metrics.wrapWidth + 0.5 }, "messages: a long line wraps inside the bubble"),
        (plan.messages[2].rows == ["你好"], "messages: no space between Chinese neighbours"),
        (plan.index(at: 0.5) == nil && plan.index(at: 3) == 1 && plan.index(at: 99) == 2, "messages: the newest started line is found"),
    ]
    return checks.filter { !$0.0 }.map(\.1)
}
