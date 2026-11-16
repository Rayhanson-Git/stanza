import SwiftUI

/// Money, part 2: where everything is at one instant. `MoneyFeed` places the few visible items of a
/// `MoneyPlan` for one frame: the scroll spring, each item's growth, tilt, squash and echo, the lead pill,
/// the "Delivered" receipt and the whole feed's zoom, nudge and presence. Everything is a closed-form
/// function of the playback position, in the plan's 402-point-wide feed space.

// MARK: - Constants

private enum Motion {
    static let gap: CGFloat = 10, messageGap: CGFloat = 2
    static let incomingX: CGFloat = 16, outgoingX: CGFloat = 386, centreX: CGFloat = 201
    static let windowSize = 12                  // more started items than ever fit on screen
    static let offscreenY: CGFloat = -20
    static let scrollItems = 4, scrollResponse = 0.5, scrollDamping = 0.8
    static let rippleSize = 3.0, rippleDecay = 0.16, rippleSpeed = 15.0, rippleDelay = 0.035
    static let bubbleResponse = 0.4, bubbleDamping = 0.52, platterResponse = 0.5, platterDamping = 0.5, snap = 0.0005
    static let bubbleStartScale: CGFloat = 0.3, platterStartScale: CGFloat = 0.6
    static let softBlur = 5.0, settle = 0.16, fadeIn = 0.06
    static let tailFrom = 0.55, tailSpan = 0.35
    static let tiltDegrees = 7.0, platterTilt = 0.22
    static let squash = 0.09, squashDecay = 0.16, squashSpeed = 21.0, platterSquash = 0.5
    static let echoLife = 0.5, echoStrength = 0.45, longEchoStrength = 0.9
    static let kickDecay = 0.11, kickSpeed = 22.0, longGain = 1.7
    static let kickBubbleTilt = 1.8, kickPlatterTilt = 0.5, kickSquash = 0.035
    static let zoomDecay = 0.16, zoomSpeed = 19.5, bubbleZoom = 0.045, platterZoom = 0.0585, longZoom = 0.027
    static let nudge = 2.2
    static let gapDim = 0.45, gapDimAfter = 5.0, gapDimOver = 2.0, gapWakeBefore = 2.0, gapWakeOver = 0.8
    static let endFadeAfter = 4.0, endFadeOver = 2.5
    static let receiptDelay = 0.2, receiptFade = 0.12, receiptResponse = 0.3, receiptDamping = 0.5, receiptHide = 0.15
    static let receiptX: CGFloat = 382, receiptGap: CGFloat = 4
    static let frame = 1.0 / 60
}

private enum Salt {
    static let platterTilt: UInt64 = 0xD018, kickTilt: UInt64 = 0xD019, nudge: UInt64 = 0xD01A
}

private enum Fit {
    static let sizePerBand = 0.125 / 40, maxWidthShare = 0.94
    static let focusMin = 0.55, focusMax = 0.76, focusBottomRoom: CGFloat = 60
    static let cardTopShare = 0.12, cardTopRoom: CGFloat = 2, minCardScale: CGFloat = 0.45
    static let pictureTopShare = 0.06, minPicture: CGFloat = 64, maxPicture: CGFloat = 150
}

// MARK: - Geometry

/// The pill that announces an item after a pause, and that the item grows out of.
enum MoneyPill {
    static func size(for kind: MoneyKind) -> CGSize {
        switch kind {
        case .cash, .message: return CGSize(width: 58, height: 36)
        case .pay: return CGSize(width: 92, height: 37)
        case .island, .card, .map: return CGSize(width: 126, height: 37)
        }
    }
}

/// How the 402-point feed maps onto the lyric band.
struct MoneyGeometry {
    static let feedWidth: CGFloat = 402
    static let cardSize = CGSize(width: 370, height: 223)

    /// Screen points per feed point.
    let scale: CGFloat
    /// The band's height in feed points: a larger text scale leaves room for fewer items.
    let height: CGFloat
    /// The newest item's bottom edge.
    let bottomY: CGFloat
    let cardScale: CGFloat

    init?(canvas: CGSize, band: CGFloat, textScale: Double) {
        let scale = min(band * Fit.sizePerBand * textScale, canvas.width * Fit.maxWidthShare / Self.feedWidth)
        guard scale > 0 else { return nil }
        let height = band / scale
        let bottomY = max(Fit.focusMin * height, min(Fit.focusMax * height, height - Fit.focusBottomRoom))
        self.scale = scale
        self.height = height
        self.bottomY = bottomY
        cardScale = min(max((bottomY - Fit.cardTopShare * height - Fit.cardTopRoom) / Self.cardSize.height, Fit.minCardScale), 1)
    }

    /// The height of the picture on top of a map item whose text part is `base` tall.
    func pictureHeight(aboveBase base: CGFloat) -> CGFloat {
        min(max(bottomY - Fit.pictureTopShare * height - base, Fit.minPicture), Fit.maxPicture)
    }
}

// MARK: - The feed

struct MoneyEcho {
    let progress: Double
    let strength: Double
}

/// One visible item: where it will rest, where it is right now, and how it is being thrown about.
struct MoneySlot {
    let item: MoneyItem
    /// The frame this instant, while the item grows in.
    let rect: CGRect
    let rest: CGRect
    let age: Double
    let tail: Double
    let tiltDegrees: Double
    let squash: Double
    let soft: Double
    let alpha: Double
    /// 1 → 0 while the lead pill's contents fade out of the newborn item.
    let handoff: Double
    let echo: MoneyEcho?
    /// A picture row keeps its shape (`pictureHeight`) while its picture is away being fetched again.
    let picture: MoneyMapPicture?
    let pictureHeight: CGFloat
}

/// How a map item is drawn: as an island, or as a picture row (whose picture can be missing for a moment).
enum MoneyMapRow {
    case island
    case pictured(MoneyMapPicture?)
}

struct MoneyLead {
    let item: MoneyItem
    let rect: CGRect
    let age: Double
}

/// The "Delivered" line under the newest outgoing bubble.
struct MoneyReceipt {
    let corner: CGPoint
    let alpha: Double
    let scale: Double
}

struct MoneyFeed {
    /// Oldest first.
    let slots: [MoneySlot]
    let lead: MoneyLead?
    let receipt: MoneyReceipt?
    let presence: Double
    /// Feed points scrolled during the last sixtieth of a second.
    let travel: Double
    let zoom: Double
    let nudge: CGSize

    /// `mapRow` says how a map item is drawn. It is told whether the item, or the pill announcing it, has
    /// come up yet: from that moment its answer must stay the same, so that an item never changes kind
    /// while it is on screen.
    init(plan: MoneyPlan, geometry: MoneyGeometry, position: Double, energy: Double,
         mapRow: (MoneyItem, _ hasComeUp: Bool) -> MoneyMapRow) {
        func entry(_ index: Int) -> FeedEntry {
            let item = plan.items[index]
            guard item.kind == .map else { return FeedEntry(item: item, geometry: geometry) }
            switch mapRow(item, position >= item.start - item.lead) {
            case .pictured(let picture): return FeedEntry(item: item, geometry: geometry, isPictured: true, picture: picture)
            case .island: return FeedEntry(item: plan.islandTwins[index] ?? item, geometry: geometry)
            }
        }
        let newest = plan.newestIndex(at: position)
        let started = newest.map { Array((max(0, $0 - Motion.windowSize + 1)...$0).reversed()) } ?? []
        let next = (newest ?? -1) + 1
        let layout = FeedLayout(geometry: geometry, position: position, energy: energy, window: started.map(entry),
                                upcoming: next < plan.items.count ? entry(next) : nil)
        let scroll = layout.scroll(at: position)
        slots = layout.slots(scroll: scroll)
        lead = layout.lead(scroll: scroll)
        receipt = layout.receipt(under: slots.last, lead: lead)
        presence = layout.presence
        travel = scroll - layout.scroll(at: position - Motion.frame)
        zoom = layout.zoom
        nudge = layout.nudge
    }
}

/// An item as it is drawn this frame: a map item with its picture, or the island standing in for it.
private struct FeedEntry {
    let item: MoneyItem
    let picture: MoneyMapPicture?
    let pictureHeight: CGFloat
    let size: CGSize

    init(item: MoneyItem, geometry: MoneyGeometry, isPictured: Bool = false, picture: MoneyMapPicture? = nil) {
        self.item = item
        self.picture = picture
        pictureHeight = isPictured ? geometry.pictureHeight(aboveBase: item.size.height) : 0
        let cardScale = item.kind == .card ? geometry.cardScale : 1
        size = CGSize(width: item.size.width * cardScale, height: item.size.height * cardScale + pictureHeight)
    }
}

/// The newest sung word of the newest item: each word gives the item and the whole feed a small kick.
private struct WordKick {
    let word: MoneyWord
    let age: Double

    var gain: Double { word.isLong ? Motion.longGain : 1 }
    var pulse: Double { gain * exp(-age / Motion.kickDecay) * cos(Motion.kickSpeed * age) }
}

private struct FeedLayout {
    let geometry: MoneyGeometry
    let position: Double
    let energy: Double
    /// Started items, newest first.
    let window: [FeedEntry]
    let upcoming: FeedEntry?

    private var kick: WordKick? {
        window.first?.item.text.words.last { $0.start <= position }.map { WordKick(word: $0, age: position - $0.start) }
    }

    private func gap(_ newer: MoneyItem, _ older: MoneyItem) -> CGFloat {
        newer.kind == .message && older.kind == .message && newer.outgoing == older.outgoing ? Motion.messageGap : Motion.gap
    }

    private func gap(below depth: Int) -> CGFloat {
        depth + 1 < window.count ? gap(window[depth].item, window[depth + 1].item) : Motion.gap
    }

    /// Each arriving item pushes the feed up by its own height on a spring; this is what is left of that push.
    func scroll(at time: Double) -> CGFloat {
        window.prefix(Motion.scrollItems).enumerated().reduce(0) { total, entry in
            let settled = MoneyMath.spring(time - entry.element.item.start, response: Motion.scrollResponse, damping: Motion.scrollDamping)
            return total + (entry.element.size.height + gap(below: entry.offset)) * (1 - settled)
        }
    }

    /// Older items shiver one after another as a new one lands.
    private func ripple(depth: Int) -> CGFloat {
        guard depth > 0, let newest = window.first?.item else { return 0 }
        let time = position - newest.start - Motion.rippleDelay * Double(depth)
        guard time > 0 else { return 0 }
        return -Motion.rippleSize * energy * exp(-time / Motion.rippleDecay) * sin(Motion.rippleSpeed * time)
    }

    func slots(scroll: CGFloat) -> [MoneySlot] {
        var cursor = geometry.bottomY
        var slots: [MoneySlot] = []
        for (depth, entry) in window.enumerated() {
            let top = scroll + cursor - entry.size.height + ripple(depth: depth)
            guard top + entry.size.height >= Motion.offscreenY else { break }
            slots.append(slot(depth: depth, rest: CGRect(origin: CGPoint(x: restX(entry.item, width: entry.size.width), y: top),
                                                         size: entry.size)))
            cursor -= entry.size.height + gap(below: depth)
        }
        return slots.reversed()
    }

    private func restX(_ item: MoneyItem, width: CGFloat) -> CGFloat {
        guard item.kind.isBubble else { return Motion.centreX - width / 2 }
        return item.outgoing ? Motion.outgoingX - width : Motion.incomingX
    }

    private func slot(depth: Int, rest: CGRect) -> MoneySlot {
        let entry = window[depth], item = entry.item, isBubble = item.kind.isBubble
        let age = position - item.start
        let raw = MoneyMath.spring(age, response: isBubble ? Motion.bubbleResponse : Motion.platterResponse,
                                   damping: isBubble ? Motion.bubbleDamping : Motion.platterDamping)
        let growth = abs(raw - 1) < Motion.snap ? 1 : raw
        let hasLead = item.lead > 0
        let startScale = isBubble ? Motion.bubbleStartScale : Motion.platterStartScale
        let from = hasLead ? MoneyPill.size(for: item.kind) : CGSize(width: rest.width * startScale, height: rest.height * startScale)
        let size = CGSize(width: from.width + growth * (rest.width - from.width), height: from.height + growth * (rest.height - from.height))
        let x = isBubble ? (item.outgoing ? rest.maxX - size.width : rest.minX) : rest.midX - size.width / 2
        let settling = 1 - MoneyMath.clamp(age / Motion.settle)
        let kick = depth == 0 ? self.kick : nil
        return MoneySlot(item: item, rect: CGRect(x: x, y: hasLead ? rest.minY : rest.maxY - size.height, width: size.width, height: size.height),
                         rest: rest, age: age, tail: tail(depth: depth, growth: growth),
                         tiltDegrees: tilt(item, age: age, kick: kick), squash: squash(item, age: age, kick: kick),
                         soft: Motion.softBlur * settling, alpha: hasLead ? 1 : MoneyMath.clamp(age / Motion.fadeIn),
                         handoff: hasLead ? settling : 0, echo: echo(age: age, kick: kick),
                         picture: entry.picture, pictureHeight: entry.pictureHeight)
    }

    /// A bubble's tail grows late, and tucks away when the next bubble on the same side arrives.
    private func tail(depth: Int, growth: Double) -> Double {
        let item = window[depth].item
        guard item.kind.isBubble else { return 0 }
        let grown = MoneyMath.clamp((growth - Motion.tailFrom) / Motion.tailSpan)
        guard depth > 0 else { return grown }
        let newer = window[depth - 1].item
        guard newer.kind.isBubble, newer.outgoing == item.outgoing else { return grown }
        return grown * (1 - MoneyMath.clamp((position - newer.start) / Motion.settle))
    }

    private func tilt(_ item: MoneyItem, age: Double, kick: WordKick?) -> Double {
        let isBubble = item.kind.isBubble
        let lean = seededUnit(item.seed, salt: Salt.platterTilt) < 0.5 ? -Motion.platterTilt : Motion.platterTilt
        let direction = isBubble ? (item.outgoing ? -1 : 1) : lean
        let arrival = Motion.tiltDegrees * direction * MoneyMath.ring(age)
        let word = kick.map { $0.pulse * (seededUnit($0.word.start, salt: Salt.kickTilt) - 0.5) * (isBubble ? Motion.kickBubbleTilt : Motion.kickPlatterTilt) }
        return energy * (arrival + (word ?? 0))
    }

    private func squash(_ item: MoneyItem, age: Double, kick: WordKick?) -> Double {
        let amplitude = item.kind == .map ? 0 : item.kind.isBubble ? 1 : Motion.platterSquash
        let arrival = Motion.squash * exp(-age / Motion.squashDecay) * sin(Motion.squashSpeed * age)
        return energy * amplitude * (arrival + (kick?.pulse ?? 0) * Motion.kickSquash)
    }

    private func echo(age: Double, kick: WordKick?) -> MoneyEcho? {
        if let kick, kick.word.isLong, kick.age < Motion.echoLife {
            return MoneyEcho(progress: kick.age / Motion.echoLife, strength: Motion.longEchoStrength)
        }
        return age < Motion.echoLife ? MoneyEcho(progress: age / Motion.echoLife, strength: Motion.echoStrength) : nil
    }

    func lead(scroll: CGFloat) -> MoneyLead? {
        guard let item = upcoming?.item, item.lead > 0 else { return nil }
        let age = position - (item.start - item.lead)
        guard age >= 0 else { return nil }
        let size = MoneyPill.size(for: item.kind)
        let above = window.first.map { gap(item, $0.item) } ?? Motion.gap
        return MoneyLead(item: item, rect: CGRect(x: restX(item, width: size.width), y: scroll + geometry.bottomY + above,
                                                  width: size.width, height: size.height), age: age)
    }

    func receipt(under newest: MoneySlot?, lead: MoneyLead?) -> MoneyReceipt? {
        guard let newest, newest.item.kind.isBubble, newest.item.outgoing else { return nil }
        let age = position - newest.item.end - Motion.receiptDelay
        guard age >= 0 else { return nil }
        // It makes way for the next outgoing bubble's typing pill.
        let hidden = lead.map { $0.item.kind.isBubble && $0.item.outgoing ? MoneyMath.clamp($0.age / Motion.receiptHide) : 0 } ?? 0
        let landed = MoneyMath.spring(age, response: Motion.receiptResponse, damping: Motion.receiptDamping)
        return MoneyReceipt(corner: CGPoint(x: Motion.receiptX, y: newest.rest.maxY + Motion.receiptGap),
                            alpha: MoneyMath.clamp(age / Motion.receiptFade) * (1 - hidden), scale: 1 - energy * (1 - landed))
    }

    /// The feed dims in a long silence, wakes before the next item, and leaves after the last one.
    var presence: Double {
        guard let current = window.first?.item else { return 1 }
        let quiet = position - current.end
        guard let next = upcoming?.item else { return 1 - MoneyMath.smoothstep((quiet - Motion.endFadeAfter) / Motion.endFadeOver) }
        return 1 - Motion.gapDim * MoneyMath.smoothstep((quiet - Motion.gapDimAfter) / Motion.gapDimOver)
            * MoneyMath.smoothstep((next.start - position - Motion.gapWakeBefore) / Motion.gapWakeOver)
    }

    var zoom: Double {
        guard let newest = window.first?.item else { return 1 }
        func bump(_ age: Double) -> Double { exp(-age / Motion.zoomDecay) * sin(Motion.zoomSpeed * age) }
        let arrival = bump(position - newest.start) * (newest.kind.isBubble ? Motion.bubbleZoom : Motion.platterZoom)
        let held = kick.map { $0.word.isLong ? bump($0.age) * Motion.longZoom : 0 } ?? 0
        return 1 + energy * (arrival + held)
    }

    var nudge: CGSize {
        guard let kick else { return .zero }
        let reach = energy * Motion.nudge * kick.gain * MoneyMath.ring(kick.age)
        let angle = 2 * Double.pi * seededUnit(kick.word.start, salt: Salt.nudge)
        return CGSize(width: reach * cos(angle), height: reach * sin(angle))
    }
}
