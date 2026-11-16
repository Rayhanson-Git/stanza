import SwiftUI

/// Notifications, one frame of it: where the few visible slots of the plan sit at one playback position.
/// The newest slot rests on a baseline; each arrival pushes the feed up on a spring and older slots leave
/// through the top. Every value is a closed-form function of the position, so there is no state to keep.

private enum NotifySizing {
    static let bandShare: CGFloat = 0.125, referenceLine: CGFloat = 40, boost: CGFloat = 1.13, widthShare: CGFloat = 0.94
    static let baseMin: CGFloat = 0.55, baseMax: CGFloat = 0.76, baseRoomBelow: CGFloat = 52
    static let widgetHeadroom: CGFloat = 0.12, widgetHeadroomPad: CGFloat = 2, widgetScaleMin: CGFloat = 0.5
    static let slotGap: CGFloat = 8
    static let topCutoff: CGFloat = -22         // slots whose bottom is above this are out of sight
    static let pushSlots = 4                    // arrivals that can still be pushing the feed
}

private enum NotifyMotion {
    static let frame = 1.0 / 60
    static let presenceFloor = 0.002
    static let lastFadeDelay = 4.0, lastFadeLength = 2.5
    static let idleDim = 0.45, idleDelay = 5.0, idleLength = 2.0, idleLead = 2.0, idleLeadLength = 0.8
    // Stands in for a vertical motion blur (a Metal shader this project cannot compile): the same travel
    // value, as a much weaker all-round blur so the text stays readable.
    static let smearGain: CGFloat = 0.9, smearMax: CGFloat = 26, smearThreshold: CGFloat = 0.75, smearStandIn: CGFloat = 0.05
    // Arrival
    static let wobbleDecay = 0.17
    static let zoomOmega = 15.6, zoomStacked = 0.0315, zoomLongWord = 0.027
    static let zoom: [NotifyKind: Double] = [.banner: 0.045, .assistant: 0.054, .widget: 0.0675, .glance: 0.027]
    static let rippleReach = 3.0, rippleOmega = 12.0, rippleDelay = 0.035
    static let arrivalScale: CGFloat = 0.88, arrivalFade = 0.07, arrivalBlur: CGFloat = 4, arrivalBlurLength = 0.14
    static let handoff = 0.16
    // Word kicks
    static let kickWindow = 1.5, longKick = 1.7
    static let shoveReach = 1.9, shoveDecay = 0.17, shoveOmega = 12.0
    static let thumpDecay = 0.12, thumpOmega = 17.0, thumpSquash = 0.032, thumpTilt = 1.8
    // Slot tilt and squash
    static let tiltDegrees = 0.992, tiltFromWords = 0.25
    static let squash = 0.028, squashOmega = 16.8, squashFromStack = 0.014, squashFromWords = 0.4
    // Echo ring
    static let echoLength = 0.5, echoArrival = 0.4, echoStack = 0.3, echoLongWord = 0.85
    // Stacks
    static let stackPeek: CGFloat = 8, stackInset: CGFloat = 20, stackTopStep: CGFloat = 7.33
    static let stackMaxInsets: CGFloat = 3, stackMaxPeeks: CGFloat = 2, stackHidden = 2.9
    static let stackRadiusGain: CGFloat = 2, stackContentFade = 0.45, stackFadeFrom = 2.0, stackFadeLength = 0.8
    static let stackEnterShare: CGFloat = 0.6, stackEnterExtra: CGFloat = 14, stackEnterScale: CGFloat = 0.95
}

struct NotifyCardPose {
    let item: NotifyItem
    /// Where the card is drawn now.
    let rect: CGRect
    /// Where it comes to rest. Panel text is anchored here while the panel grows out of the pill.
    let rest: CGRect
    let radius: CGFloat
    let alpha: Double
    let blur: CGFloat
    /// Opacity of what is written on the card (it fades as the card sinks into a stack).
    let content: Double
    /// 1 → 0 while a panel that grew out of the pill still shows the pill's bars.
    let handoff: Double
    /// Outlines of the cards in front; this card is only drawn outside them.
    let cutouts: [Path]
    let age: Double

    init(item: NotifyItem, rect: CGRect, rest: CGRect, radius: CGFloat, age: Double, alpha: Double = 1, blur: CGFloat = 0,
         content: Double = 1, handoff: Double = 0, cutouts: [Path] = []) {
        (self.item, self.rect, self.rest, self.radius, self.age) = (item, rect, rest, radius, age)
        (self.alpha, self.blur, self.content, self.handoff, self.cutouts) = (alpha, blur, content, handoff, cutouts)
    }

    var outline: Path { NotifyCardPose.outline(rect, radius: radius) }

    static func outline(_ rect: CGRect, radius: CGFloat) -> Path {
        Path(roundedRect: rect, cornerRadius: max(0, min(radius, min(rect.width, rect.height) / 2)), style: .continuous)
    }
}

struct NotifyEcho {
    let strength: Double
    /// 0 as the ring leaves the card, 1 when it is gone.
    let phase: Double
}

struct NotifySlotPose {
    /// Back to front.
    let cards: [NotifyCardPose]
    let rect: CGRect
    /// What the echo rings spread out from: the card as it is now, or the whole stack.
    let ringRect: CGRect
    let ringRadius: CGFloat
    let tiltDegrees: Double
    let squash: Double
    let echoes: [NotifyEcho]
}

/// The small "listening" capsule that shows before an assistant panel.
struct NotifyPillPose {
    let seed: Double
    let age: Double
    let top: CGFloat
}

struct NotifyFeed {
    let plan: NotifyPlan
    /// Oldest first.
    let slots: [NotifySlotPose]
    let pill: NotifyPillPose?
    /// The design column's origin and scale on the canvas.
    let origin: CGPoint
    let scale: CGFloat
    let presence: Double
    let blur: CGFloat
    /// The resting bottom of the newest slot, in design units.
    let base: CGFloat
    /// 0 with Reduce Motion, else 1: scales every decorative wobble.
    let motion: Double

    /// nil when nothing is on screen: before the first item, or once the last one has faded.
    @MainActor init?(context: StyleContext) {
        guard context.band > 0, context.canvas.width > 0, !context.lyrics.words.isEmpty else { return nil }
        let plan = NotifyPlanCache.plan(for: context.lyrics)
        guard let current = plan.currentIndex(at: context.position) else { return nil }
        let presence = Self.presence(of: plan, current: current, at: context.position)
        guard presence >= NotifyMotion.presenceFloor else { return nil }
        let stage = NotifyStage(context: context, plan: plan, current: current)
        let zoom = stage.zoom, unit = stage.unit
        let travel = stage.push(at: context.position) - stage.push(at: context.position + NotifyMotion.frame)
        let smear = min(unit * abs(travel) * NotifyMotion.smearGain, NotifyMotion.smearMax)
        self.plan = plan
        self.presence = presence
        slots = stage.slotPoses()
        pill = stage.pillPose
        scale = unit * zoom
        origin = CGPoint(x: context.canvas.width / 2 - NotifyMetrics.columnWidth / 2 * unit * zoom + unit * stage.kicks.offset.dx * stage.motion,
                         // The zoom is anchored on the baseline, so the newest card swells in place.
                         y: unit * stage.kicks.offset.dy * stage.motion + (1 - zoom) * unit * stage.base)
        blur = smear > NotifyMotion.smearThreshold ? smear * NotifyMotion.smearStandIn : 0
        base = stage.base
        motion = stage.motion
    }

    /// The feed fades out after the last line, and dims in a long silence that has no glance row.
    private static func presence(of plan: NotifyPlan, current: Int, at position: Double) -> Double {
        let sinceEnd = position - plan.items[current].end
        guard current + 1 < plan.items.count else {
            return 1 - NotifyMath.smooth((sinceEnd - NotifyMotion.lastFadeDelay) / NotifyMotion.lastFadeLength)
        }
        let untilNext = plan.items[current + 1].start - position
        return 1 - NotifyMotion.idleDim * NotifyMath.smooth((sinceEnd - NotifyMotion.idleDelay) / NotifyMotion.idleLength)
            * NotifyMath.smooth((untilNext - NotifyMotion.idleLead) / NotifyMotion.idleLeadLength)
    }
}

/// What the newest item's words do to the whole feed: each one shoves it a little, long ones harder.
private struct NotifyKicks {
    let offset: CGVector
    let squash: Double
    let tilt: Double
    /// Seconds since the newest long-held word began, while it is recent enough to matter.
    let longAge: Double?

    init(words: [NotifyWord], position: Double) {
        var offset = CGVector.zero, squash = 0.0, tilt = 0.0, longAge: Double?
        for word in words {
            let age = position - word.start
            guard age >= 0, age <= NotifyMotion.kickWindow else { continue }
            let strength = word.isLong ? NotifyMotion.longKick : 1
            let shove = NotifyMotion.shoveReach * strength * NotifyMath.kick(age, decay: NotifyMotion.shoveDecay, omega: NotifyMotion.shoveOmega)
            let angle = 2 * Double.pi * seededUnit(word.start, salt: NotifySalt.kickAngle)
            let thump = strength * NotifyMath.kick(age, decay: NotifyMotion.thumpDecay, omega: NotifyMotion.thumpOmega)
            offset = CGVector(dx: offset.dx + shove * cos(angle), dy: offset.dy + shove * sin(angle))
            squash += NotifyMotion.thumpSquash * thump
            tilt += NotifyMotion.thumpTilt * (seededUnit(word.start, salt: NotifySalt.kickTilt) - 0.5) * thump
            if word.isLong { longAge = age }
        }
        (self.offset, self.squash, self.tilt, self.longAge) = (offset, squash, tilt, longAge)
    }
}

private struct NotifyStage {
    let plan: NotifyPlan
    let position: Double
    let current: Int
    /// Screen points per design unit.
    let unit: CGFloat
    let base: CGFloat
    let widgetScale: CGFloat
    let motion: Double
    let kicks: NotifyKicks

    init(context: StyleContext, plan: NotifyPlan, current: Int) {
        let byHeight = context.band * NotifySizing.bandShare * context.settings.textScale / NotifySizing.referenceLine * NotifySizing.boost
        let unit = min(byHeight, context.canvas.width * NotifySizing.widthShare / NotifyMetrics.columnWidth)
        let height = context.band / unit
        let base = max(NotifySizing.baseMin * height, min(NotifySizing.baseMax * height, height - NotifySizing.baseRoomBelow))
        let room = base - NotifySizing.widgetHeadroom * height - NotifySizing.widgetHeadroomPad
        self.plan = plan
        self.current = current
        self.unit = unit
        self.base = base
        position = context.position
        widgetScale = min(max(room / NotifyMetrics.widgetSize.height, NotifySizing.widgetScaleMin), 1)
        motion = context.settings.reduceMotion ? 0 : 1
        kicks = NotifyKicks(words: plan.items[current].words, position: context.position)
    }

    private var newestSlot: Int { plan.slotOf[current] }
    private var newestSlotAge: Double { position - plan.items[plan.slots[newestSlot].lowerBound].start }

    private func size(of item: NotifyItem) -> CGSize {
        item.kind == .widget ? CGSize(width: item.size.width * widgetScale, height: item.size.height * widgetScale) : item.size
    }

    private func radius(of item: NotifyItem) -> CGFloat {
        switch item.kind {
        case .banner, .glance: return NotifyMetrics.bannerRadius
        case .assistant: return NotifyMetrics.panelRadius
        case .widget: return NotifyMetrics.widgetRadius * widgetScale
        }
    }

    /// How far below its resting place the feed still is: every recent arrival starts a full slot down.
    func push(at time: Double) -> CGFloat {
        (max(0, newestSlot - NotifySizing.pushSlots + 1)...newestSlot).reduce(0) { total, slot in
            let first = plan.items[plan.slots[slot].lowerBound]
            return total + (size(of: first).height + NotifySizing.slotGap) * (1 - NotifySpring.push.value(at: time - first.start))
        }
    }

    /// A swell of the whole feed as an item lands, and a smaller one for a long-held word.
    var zoom: CGFloat {
        let item = plan.items[current]
        let isStackedOn = plan.slots[newestSlot].lowerBound != current
        let strength = isStackedOn ? NotifyMotion.zoomStacked : NotifyMotion.zoom[item.kind] ?? 0
        let landing = NotifyMath.ring(position - item.start, decay: NotifyMotion.wobbleDecay, omega: NotifyMotion.zoomOmega)
        let held = kicks.longAge.map { NotifyMath.ring($0, decay: NotifyMotion.wobbleDecay, omega: NotifyMotion.zoomOmega) } ?? 0
        return 1 + motion * (strength * landing + NotifyMotion.zoomLongWord * held)
    }

    var pillPose: NotifyPillPose? {
        guard current + 1 < plan.items.count else { return nil }
        let next = plan.items[current + 1]
        let age = position - (next.start - next.lead)
        guard next.kind == .assistant, next.lead > 0, age >= 0 else { return nil }
        return NotifyPillPose(seed: next.seed, age: age, top: base + push(at: position) + NotifySizing.slotGap)
    }

    /// Slots from the newest upward until they pass the top of the band, returned oldest first.
    func slotPoses() -> [NotifySlotPose] {
        var poses: [NotifySlotPose] = []
        var bottom = base + push(at: position)
        var slot = newestSlot
        while slot >= 0 && bottom > NotifySizing.topCutoff {
            let pose = slotPose(slot, level: poses.count, bottom: bottom)
            poses.append(pose)
            bottom -= pose.rect.height + NotifySizing.slotGap
            slot -= 1
        }
        return poses.reversed()
    }

    private func slotPose(_ slot: Int, level: Int, bottom: CGFloat) -> NotifySlotPose {
        let range = plan.slots[slot]
        let started = range.filter { plan.items[$0].start <= position }.map { plan.items[$0] }
        let shown = started.isEmpty ? [plan.items[range.lowerBound]] : started
        let sizes = shown.map(size(of:))
        let settles = shown.dropFirst().map { NotifySpring.stack.value(at: position - $0.start) }
        // A stack grows by a peek per added banner, plus whatever taller or shorter the new front card is.
        let growth = settles.enumerated().reduce(CGFloat(0)) { total, entry in
            total + entry.element * (NotifyMotion.stackPeek + sizes[entry.offset + 1].height - sizes[entry.offset].height)
        }
        let rippleAge = newestSlotAge - NotifyMotion.rippleDelay * Double(level)
        let ripple = level == 0 ? 0 : -NotifyMotion.rippleReach * motion
            * NotifyMath.ring(rippleAge, decay: NotifyMotion.wobbleDecay, omega: NotifyMotion.rippleOmega)
        let height = sizes[0].height + growth
        let rect = CGRect(x: (NotifyMetrics.columnWidth - sizes[0].width) / 2, y: bottom - height + ripple, width: sizes[0].width, height: height)
        let cards = shown.count == 1 ? [arrivingCard(shown[0], in: rect)] : stackCards(shown, sizes: sizes, settles: settles, in: rect)
        let age = position - shown[0].start
        let stackAge = shown.count > 1 ? position - shown[shown.count - 1].start : nil
        let isStill = shown[0].kind == .glance
        let ring = shown.count == 1 ? (cards[0].rect, cards[0].radius) : (rect, NotifyMetrics.bannerRadius)
        return NotifySlotPose(cards: cards, rect: rect, ringRect: ring.0, ringRadius: ring.1,
                              tiltDegrees: isStill ? 0 : tilt(seed: shown[0].seed, age: age, isNewest: level == 0),
                              squash: isStill ? 0 : squash(age: age, stackAge: stackAge, isNewest: level == 0),
                              echoes: echoes(age: age, stackAge: stackAge, isNewest: level == 0))
    }

    private func tilt(seed: Double, age: Double, isNewest: Bool) -> Double {
        let sign = seededUnit(seed, salt: NotifySalt.slotTilt) >= 0.5 ? 1.0 : -1.0
        let landing = sign * NotifyMotion.tiltDegrees * NotifyMath.kick(age, decay: NotifyMotion.shoveDecay, omega: NotifyMotion.shoveOmega)
        return motion * (landing + (isNewest ? NotifyMotion.tiltFromWords * kicks.tilt : 0))
    }

    private func squash(age: Double, stackAge: Double?, isNewest: Bool) -> Double {
        let landing = NotifyMotion.squash * NotifyMath.ring(age, decay: NotifyMotion.wobbleDecay, omega: NotifyMotion.squashOmega)
        let stacking = NotifyMotion.squashFromStack
            * (stackAge.map { NotifyMath.kick($0, decay: NotifyMotion.shoveDecay, omega: NotifyMotion.shoveOmega) } ?? 0)
        return motion * (landing + stacking + (isNewest ? NotifyMotion.squashFromWords * kicks.squash : 0))
    }

    private func echoes(age: Double, stackAge: Double?, isNewest: Bool) -> [NotifyEcho] {
        let sources: [(strength: Double, age: Double?)] = [(NotifyMotion.echoArrival, age), (NotifyMotion.echoStack, stackAge),
                                                           (NotifyMotion.echoLongWord, isNewest ? kicks.longAge : nil)]
        return sources.compactMap { source in
            guard let age = source.age, age >= 0, age < NotifyMotion.echoLength else { return nil }
            return NotifyEcho(strength: source.strength, phase: age / NotifyMotion.echoLength)
        }
    }

    // MARK: Cards

    /// A card on its own: it swells into place, or (an assistant panel after a pause) grows out of the pill.
    private func arrivingCard(_ item: NotifyItem, in slot: CGRect) -> NotifyCardPose {
        let age = position - item.start
        let grown = CGFloat(NotifySpring.panel.value(at: age))
        let radius = radius(of: item)
        if item.kind == .assistant && item.lead > 0 {
            let pill = NotifyMetrics.pillSize
            let size = CGSize(width: NotifyMath.lerp(pill.width, slot.width, grown), height: NotifyMath.lerp(pill.height, slot.height, grown))
            let rect = CGRect(x: slot.midX - size.width / 2, y: slot.minY, width: size.width, height: size.height)
            return NotifyCardPose(item: item, rect: rect, rest: slot, radius: radius, age: age, handoff: max(0, 1 - age / NotifyMotion.handoff))
        }
        let scale = NotifyMath.lerp(NotifyMotion.arrivalScale, 1, grown)
        let size = CGSize(width: slot.width * scale, height: slot.height * scale)
        let rect = CGRect(x: slot.midX - size.width / 2, y: slot.maxY - size.height, width: size.width, height: size.height)
        return NotifyCardPose(item: item, rect: rect, rest: slot, radius: radius * scale, age: age, alpha: fadeIn(age), blur: arrivalBlur(age))
    }

    private func fadeIn(_ age: Double) -> Double { min(max(age / NotifyMotion.arrivalFade, 0), 1) }
    private func arrivalBlur(_ age: Double) -> CGFloat { NotifyMotion.arrivalBlur * max(0, 1 - age / NotifyMotion.arrivalBlurLength) }

    /// A stack: the newest banner in front, each older one sunk behind it and peeking out below.
    private func stackCards(_ shown: [NotifyItem], sizes: [CGSize], settles: [Double], in slot: CGRect) -> [NotifyCardPose] {
        let frontIndex = shown.count - 1
        let lift = NotifyMotion.stackPeek * settles.reduce(0, +)
        let frontRest = CGRect(x: slot.minX, y: slot.maxY - lift - sizes[frontIndex].height, width: slot.width, height: sizes[frontIndex].height)
        let front = frontCard(shown[frontIndex], rest: frontRest, settled: settles[frontIndex - 1])
        var cards = [front]
        var cutouts = [front.outline]
        for index in (0..<frontIndex).reversed() {
            // settles[j − 1] belongs to shown[j], so the cards in front of `index` are settles[index...].
            let depth = settles[index...].reduce(0, +)
            guard depth < NotifyMotion.stackHidden else { continue }
            let card = buriedCard(shown[index], height: sizes[index].height, depth: depth, front: frontRest, cutouts: cutouts)
            cards.insert(card, at: 0)
            cutouts.append(card.outline)
        }
        return cards
    }

    private func frontCard(_ item: NotifyItem, rest: CGRect, settled: Double) -> NotifyCardPose {
        let age = position - item.start
        let scale = NotifyMath.lerp(NotifyMotion.stackEnterScale, 1, settled)
        let drop = (NotifyMotion.stackEnterShare * rest.height + NotifyMotion.stackEnterExtra) * (1 - settled)
        let rect = CGRect(x: rest.midX - rest.width * scale / 2, y: rest.midY + drop - rest.height * scale / 2,
                          width: rest.width * scale, height: rest.height * scale)
        return NotifyCardPose(item: item, rect: rect, rest: rest, radius: NotifyMetrics.bannerRadius * scale, age: age,
                              alpha: fadeIn(age), blur: arrivalBlur(age))
    }

    private func buriedCard(_ item: NotifyItem, height: CGFloat, depth: Double, front: CGRect, cutouts: [Path]) -> NotifyCardPose {
        let sunk = CGFloat(depth)
        let inset = NotifyMotion.stackInset * min(sunk, NotifyMotion.stackMaxInsets)
        let peeks = min(sunk, NotifyMotion.stackMaxPeeks)
        let bottom = front.maxY + NotifyMotion.stackPeek * peeks
        let top = NotifyMath.lerp(bottom - height, front.minY + NotifyMotion.stackTopStep * peeks, min(sunk, 1))
        let rect = CGRect(x: front.minX + inset, y: top, width: front.width - 2 * inset, height: bottom - top)
        return NotifyCardPose(item: item, rect: rect, rest: rect, radius: NotifyMetrics.bannerRadius + NotifyMotion.stackRadiusGain * min(sunk, 1),
                              age: position - item.start,
                              alpha: 1 - NotifyMath.smooth((depth - NotifyMotion.stackFadeFrom) / NotifyMotion.stackFadeLength),
                              content: 1 - NotifyMath.smooth(depth / NotifyMotion.stackContentFade), cutouts: cutouts)
    }
}

// MARK: Self-check

/// Assert-style checks of the plan rules and the feed geometry; returns one line per failure.
func notificationsStyleSelfCheck() -> [String] {
    // The self-check runs on the main thread, where the plan cache lives.
    MainActor.assumeIsolated { notificationsStyleFailures() }
}

@MainActor private func notificationsStyleFailures() -> [String] {
    func lyrics(_ script: [(start: Double, words: [String])]) -> TimedLyrics {
        TimedLyrics(tier: .wordLevel, words: script.enumerated().flatMap { number, entry in
            entry.words.enumerated().map { index, text in
                TimedWord(text: text, start: entry.start + 0.4 * Double(index), end: entry.start + 0.4 * Double(index) + 0.35, line: number)
            }
        })
    }
    let verse = ["Paint", "the", "quiet", "harbour,", "every", "lamp", "still", "burning"]
    let song = lyrics([(1, verse), (5, ["oh"]), (9, ["Where", "did", "you", "go?"]), (30, ["Hum", "it", "low"])])
    let symbolsBefore = WordVisuals.shared.revision
    let plan = NotifyPlanCache.plan(for: song)
    // The same word count, first start and last end as `song`, with one word corrected.
    let corrected = lyrics([(1, Array(verse.dropLast()) + ["glow"]), (5, ["oh"]), (9, ["Where", "did", "you", "go?"]), (30, ["Hum", "it", "low"])])
    let correctedPlan = NotifyPlanCache.plan(for: corrected)
    // A plan is rebuilt when word symbols arrive, which the background loader may do at any moment.
    let isCached = NotifyPlanCache.plan(for: song) === plan || WordVisuals.shared.revision != symbolsBefore
    // A duet: the third line is listed after the second but starts before it.
    let duetSong = lyrics([(1, ["one", "more"]), (5, ["two"]), (4, ["three"])])
    let duet = NotifyPlan(lyrics: duetSong)
    let unordered = NotifyPlan(lyrics: TimedLyrics(tier: .wordLevel, words: [
        TimedWord(text: "late", start: 3.5, end: 3.8, line: 0), TimedWord(text: "early", start: 3, end: 4.5, line: 0)])).items[0]
    let duetNow = duet.currentIndex(at: 4.5).map { duet.items[$0] }
    let duetFeed = NotifyFeed(context: StyleContext(line: ActiveLine(index: 2, words: duetSong.lines[2], shown: 1), lyrics: duetSong, position: 4.5,
                                                    clock: 0, canvas: CGSize(width: 1440, height: 900), band: 504, settings: AppSettings.shared))
    let spaced = NotifyPlan(lyrics: lyrics([(1, ["a", "", "b"])])).items[0]
    let quick = NotifyPlan(lyrics: lyrics((0..<12).map { (2 + 0.5 * Double($0), ["la"]) }))
    let panel = plan.items.first { $0.kind == .assistant }
    let glance = plan.items.first { $0.kind == .glance }
    let widget = NotifyPlan(lyrics: lyrics([(1, verse + verse + verse)])).items[0]
    let context = StyleContext(line: ActiveLine(index: 1, words: song.lines[1], shown: 1), lyrics: song, position: 8, clock: 0,
                               canvas: CGSize(width: 1440, height: 900), band: 504, settings: AppSettings.shared)
    let feed = NotifyFeed(context: context)
    let peak = NotifyMath.kick(atan(0.17 * 12) / 12, decay: 0.17, omega: 12)
    let checks: [(Bool, String)] = [
        (NotifySpring.push.value(at: 0) == 0 && NotifySpring.push.value(at: 5) == 1 && NotifySpring.panel.value(at: 0.3) > 1,
         "a spring starts at 0, overshoots and settles on exactly 1"),
        (peak > 0.95 && peak <= 1, "a kick peaks at about 1"),
        (NotifyQuestion.matches(["Do", "you", "feel", "it"]) && NotifyQuestion.matches(["What's", "up"]) && NotifyQuestion.matches(["so", "why?"])
            && !NotifyQuestion.matches(["we", "could", "drive"]), "question lines are recognised"),
        (plan.items.map(\.kind) == [.widget, .banner, .assistant, .glance, .widget],
         "kinds: widget first, a single word is a banner, a question a panel, a long silence a glance and then a widget"),
        (abs((panel?.lead ?? 0) - 2.4) < 0.0001 && abs((glance?.start ?? 0) - 11.55) < 0.0001 && glance?.end == 30,
         "the pill's lead is capped; the glance spans the silence"),
        (plan.slots.flatMap { Array($0) } == Array(plan.items.indices) && plan.slotOf == [0, 1, 2, 3, 4], "every item sits in exactly one slot"),
        (quick.items.allSatisfy { $0.kind == .banner } && quick.slots.allSatisfy { $0.count <= 3 } && quick.slots.contains { $0.count > 1 },
         "quick banners stack, three at most"),
        (NotifyTypesetter.headCount(of: song.lines[0]) == 4 && NotifyTypesetter.headCount(of: Array(song.lines[0][4...])) == 2
            && NotifyTypesetter.headCount(of: song.lines[3]) == 3, "banner title: up to the first break, or all of a short line"),
        (widget.body.type.size < 30 && widget.body.size.width <= NotifyMetrics.widgetTextWidth, "a long line shrinks the widget's text"),
        (plan.currentIndex(at: 0.5) == nil && plan.currentIndex(at: 9) == 2 && isCached, "current item lookup; the plan is cached"),
        (correctedPlan !== plan && plan.items[0].words.last?.text == "burning" && correctedPlan.items[0].words.last?.text == "glow",
         "lyrics of the same shape but different words get their own plan"),
        (duet.items.map(\.start) == [1, 5, 4] && duetNow?.words.map(\.text) == ["three"] && duet.currentIndex(at: 0.5) == nil
            && duetFeed != nil, "a line that starts before the one listed ahead of it is still found"),
        (unordered.start == 3 && unordered.end == 4.5, "a line spans its earliest start to its latest end"),
        (spaced.words.map(\.text) == ["a", "b"] && (spaced.head.rows + spaced.body.rows).map(\.text) == ["a b"],
         "an empty word leaves no doubled space"),
        (feed?.slots.count == 2 && abs((feed?.slots.last?.rect.maxY ?? 0) - (feed?.base ?? -1)) < 0.01
            && abs((feed?.slots.first?.rect.maxY ?? 0) + 8 - (feed?.slots.last?.rect.minY ?? -1)) < 0.01,
         "a settled feed rests on its baseline with 8 units between slots"),
    ]
    return checks.filter { !$0.0 }.map { "notifications: " + $0.1 }
}
