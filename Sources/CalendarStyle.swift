import AppKit
import SwiftUI

/// Calendar: the song as one day in a planner. Song time is clock time (the song opens at 7 AM and every
/// second of music is four minutes), each lyric line is an event block at its start time as tall as it lasts,
/// and a "now" line walks down the day while the view scrolls to keep it in sight. The words of the running
/// event light up as they are sung. Drawn on a virtual card `Look.card` units big, scaled to the screen; every
/// frame is a closed-form function of the playback position, so it holds through gaps and before the first line.
struct CalendarStyle: View {
    let context: StyleContext

    var body: some View {
        let unit = Look.unit(for: context)
        let day = CalendarDay(context: context)
        // A card taller than the band at large sizes overflows it rather than being cut off.
        let height = max(context.band, Look.card.height * unit + 2 * Look.shadowRoom)
        // Faded out after the song ends: nothing to draw, so no canvas pass at all.
        if day.opacity < 0.002 {
            Color.clear.frame(width: context.canvas.width, height: context.band)
        } else {
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, size in
                guard unit > 0 else { return }
                var sheet = graphics
                sheet.translateBy(x: (size.width - Look.card.width * unit) / 2, y: (size.height - Look.card.height * unit) / 2)
                sheet.scaleBy(x: unit, y: unit)
                day.draw(in: sheet)
            }
            .frame(width: context.canvas.width, height: height)
            .opacity(day.opacity)
            .shadow(color: .black.opacity(Look.shadowOpacity), radius: Look.shadowRadius, y: Look.shadowY)
        }
    }
}

// MARK: - Constants (card units unless noted)

private enum Look {
    static let card = CGSize(width: 480, height: 320), cardRadius: CGFloat = 24
    static let heightShare = 0.8, widthShare = 0.92, screenShare = 0.9   // of the band, the canvas width and height
    static let shadowRoom: CGFloat = 40                                    // points
    static let shadowOpacity = 0.4, shadowRadius: CGFloat = 18, shadowY: CGFloat = 8

    static let background = Color(.sRGB, red: 0.071, green: 0.082, blue: 0.110)
    static let hairline = Color.white.opacity(0.08)
    static let now = Color(.sRGB, red: 1, green: 0.502, blue: 0.369)       // coral, kept out of the event palette
    /// Event colours; neighbouring lines never share one.
    static let palette: [Color] = [
        Color(.sRGB, red: 0.384, green: 0.561, blue: 1),        // cornflower
        Color(.sRGB, red: 0.243, green: 0.788, blue: 0.690),    // sea green
        Color(.sRGB, red: 0.651, green: 0.506, blue: 1),        // lilac
        Color(.sRGB, red: 0.949, green: 0.706, blue: 0.294),    // marigold
        Color(.sRGB, red: 0.941, green: 0.431, blue: 0.627),    // peony
        Color(.sRGB, red: 0.502, green: 0.792, blue: 0.424),    // fern
    ]

    // Header
    static let inset: CGFloat = 22
    static let datelineY: CGFloat = 20, titleY: CGFloat = 36, titleHeight: CGFloat = 30
    static let chipHeight: CGFloat = 20, chipPadding: CGFloat = 9, chipDot: CGFloat = 6
    static let dividerY: CGFloat = 76

    // Day body
    static let bodyTop: CGFloat = 77
    static let hourColumn: CGFloat = 58, eventsLeft: CGFloat = 64, eventsRight: CGFloat = 14
    static let pointsPerSecond: CGFloat = 14
    static let nowShare: CGFloat = 0.36                    // of the body, from its top
    static let leadIn: CGFloat = 16                        // room above 7 AM at the start
    static let fadeTop: CGFloat = 12, fadeBottom: CGFloat = 22

    // Events
    static let minHeight: CGFloat = 22, gap: CGFloat = 2, indent: CGFloat = 20, maxIndents = 2
    static let radius: CGFloat = 6, bar: CGFloat = 3
    static let textInset = CGSize(width: 10, height: 4.5), titleRow: CGFloat = 16, timeRow: CGFloat = 13
    static let growTime = 0.25, settle = 0.3, linger = 0.6, wordFade = 0.12

    // Gaps and the end of the song
    static let endAfter = 4.0, endRamp = 2.5

    /// Points per card unit: the card is `heightShare` of the band tall at Size 100 %, but never wider or taller than the screen allows.
    static func unit(for context: StyleContext) -> CGFloat {
        min(context.band * heightShare * context.scale / card.height, context.canvas.width * widthShare / card.width,
            context.canvas.height * screenShare / card.height)
    }
}

private enum Clock {
    static let openingMinute = 7 * 60.0, minutesPerSecond = 4.0
    static let gridMinutes = 30.0

    /// "7:42 AM" for a moment of the song.
    static func label(_ seconds: Double, short: Bool = false) -> String {
        let minutes = (openingMinute + max(0, seconds) * minutesPerSecond).rounded()
        let hour24 = Int(minutes / 60) % 24, minute = Int(minutes.truncatingRemainder(dividingBy: 60))
        let hour = hour24 % 12 == 0 ? 12 : hour24 % 12, half = hour24 < 12 ? "AM" : "PM"
        if short { return minute == 0 ? "\(hour) \(half)" : String(format: "%d:%02d", hour, minute) }
        return String(format: "%d:%02d %@", hour, minute, half)
    }

    /// Song seconds at which grid line `index` (every half hour from 7 AM) falls.
    static func gridSecond(_ index: Int) -> Double { Double(index) * gridMinutes / minutesPerSecond }
}

private enum Salt { static let tint: UInt64 = 0xCA1E }

private func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }
private func smooth(_ value: Double) -> Double { clamp01(value) * clamp01(value) * (3 - 2 * clamp01(value)) }
private func mix(_ from: Double, _ to: Double, _ amount: Double) -> Double { from + (to - from) * amount }

// MARK: - The day at one instant

/// One lyric line as an event.
private struct CalendarEvent {
    let words: [TimedWord]
    let start: Double, end: Double
    let tint: Color
    /// Pushed right when it starts under the one before it (duets).
    let indent: CGFloat
    /// Its resting height on the day, from its duration.
    let height: CGFloat

    var top: CGFloat { CGFloat(start) * Look.pointsPerSecond }
}

private struct CalendarDay {
    enum Status { case before(Double), during(CalendarEvent), free(Double), done }

    let position: Double
    let title: String
    let dateline: String
    let events: [CalendarEvent]
    /// The event that has started most recently, if any.
    let current: Int?
    /// Card offset of the timeline's zero (song second 0).
    let scroll: CGFloat
    let opacity: Double
    let motion: Double

    init(context: StyleContext) {
        position = context.position
        motion = context.settings.reduceMotion ? 0 : 1
        let title = context.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? "Today" : title
        dateline = Self.dateline(Date(timeIntervalSinceReferenceDate: context.clock))
        events = Self.events(context.lyrics.lines)
        current = events.lastIndex { $0.start <= context.position }
        let nowY = CGFloat(context.position) * Look.pointsPerSecond
        scroll = Look.bodyTop - max(-Look.leadIn, nowY - Look.nowShare * Self.bodyHeight)
        let lastEnd = events.map(\.end).max() ?? 0
        opacity = 1 - smooth((context.position - lastEnd - Look.endAfter) / Look.endRamp)
    }

    static var bodyHeight: CGFloat { Look.card.height - Look.bodyTop }

    private static let datelineFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return formatter
    }()

    private static func dateline(_ date: Date) -> String { datelineFormat.string(from: date).uppercased() }

    /// Events in song order with their colours, heights and indents. Cheap enough to redo every frame.
    static func events(_ lines: [[TimedWord]]) -> [CalendarEvent] {
        var events: [CalendarEvent] = [], recentTints: [Int] = []
        for (index, line) in lines.enumerated() {
            // Overlapping voices need not be in time order: a line spans its earliest start to its latest end.
            guard let start = line.map(\.start).min(), let end = line.map(\.end).max() else { continue }
            // Never the colour of either of the two events before it.
            let choices = Look.palette.indices.filter { !recentTints.contains($0) }
            let tint = choices[min(choices.count - 1, Int(seededUnit(start, salt: Salt.tint) * Double(choices.count)))]
            recentTints = [tint] + recentTints.prefix(1)
            // Stops short of the next event, unless that one starts so soon it is indented beside this one instead.
            let next = lines.indices.contains(index + 1) ? lines[index + 1].map(\.start).min() ?? .infinity : .infinity
            let room = CGFloat(next - start) * Look.pointsPerSecond - Look.gap
            let natural = max(CGFloat(end - start) * Look.pointsPerSecond, Look.minHeight)
            let height = room >= Look.minHeight ? min(natural, room) : natural
            let overlapped = events.last.map { $0.top + $0.height > CGFloat(start) * Look.pointsPerSecond + Look.gap } ?? false
            let indent = overlapped ? min((events.last?.indent ?? 0) + Look.indent, Look.indent * CGFloat(Look.maxIndents)) : 0
            events.append(CalendarEvent(words: line.filter { !$0.text.isEmpty }, start: start, end: end,
                                        tint: Look.palette[tint], indent: indent, height: height))
        }
        return events
    }

    var status: Status {
        guard let current else { return events.first.map { .before($0.start) } ?? .done }
        let event = events[current]
        if position < event.end + Look.linger { return .during(event) }
        return events.indices.contains(current + 1) ? .free(events[current + 1].start) : .done
    }
}

// MARK: - Drawing

extension CalendarDay {
    func draw(in graphics: GraphicsContext) {
        let card = Path(roundedRect: CGRect(origin: .zero, size: Look.card), cornerRadius: Look.cardRadius, style: .continuous)
        graphics.fill(card, with: .color(Look.background))
        drawHeader(in: graphics)
        var body = graphics
        body.clip(to: card)
        body.clip(to: Path(CGRect(x: 0, y: Look.bodyTop, width: Look.card.width, height: Self.bodyHeight)))
        drawGrid(in: body)
        drawNowLine(in: body)
        drawEvents(in: body)
        drawNowPill(in: body)
        drawFades(in: body)
        graphics.stroke(card, with: .color(Look.hairline), lineWidth: 1)
    }

    // MARK: Header

    private func drawHeader(in graphics: GraphicsContext) {
        let dateline = Text(dateline).font(.system(size: 11, weight: .bold)).kerning(0.8).foregroundStyle(Look.now)
        graphics.draw(dateline, at: CGPoint(x: Look.inset, y: Look.datelineY), anchor: .topLeading)
        let title = graphics.resolve(Text(title).font(.system(size: 23, weight: .bold)).foregroundStyle(.white))
        graphics.draw(title, in: CGRect(x: Look.inset, y: Look.titleY, width: Look.card.width - 2 * Look.inset, height: Look.titleHeight))
        drawChip(in: graphics)
        graphics.fill(Path(CGRect(x: 0, y: Look.dividerY, width: Look.card.width, height: 1)), with: .color(Look.hairline))
    }

    /// What the day holds right now, top right: the running event's end, the next free stretch, or the first event.
    private func drawChip(in graphics: GraphicsContext) {
        let (label, dot): (String, Color?) = switch status {
        case .before(let start): ("Starts \(Clock.label(start))", nil)
        case .during(let event): ("Until \(Clock.label(event.end))", event.tint)
        case .free(let next): ("Free until \(Clock.label(next))", nil)
        case .done: ("Nothing else today", nil)
        }
        let text = graphics.resolve(Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.78)))
        let textWidth = text.measure(in: CGSize(width: 400, height: 40)).width
        let dotRoom = dot == nil ? 0 : Look.chipDot + 6
        let width = textWidth + dotRoom + 2 * Look.chipPadding
        let rect = CGRect(x: Look.card.width - Look.inset - width, y: Look.datelineY - 4, width: width, height: Look.chipHeight)
        graphics.fill(Path(roundedRect: rect, cornerRadius: Look.chipHeight / 2), with: .color(.white.opacity(0.08)))
        if let dot {
            graphics.fill(Path(ellipseIn: CGRect(x: rect.minX + Look.chipPadding, y: rect.midY - Look.chipDot / 2,
                                                 width: Look.chipDot, height: Look.chipDot)), with: .color(dot))
        }
        graphics.draw(text, at: CGPoint(x: rect.minX + Look.chipPadding + dotRoom, y: rect.midY), anchor: .leading)
    }

    // MARK: Body

    private func y(_ seconds: Double) -> CGFloat { scroll + CGFloat(seconds) * Look.pointsPerSecond }

    /// Hour and half-hour rules with their times in the left column; the label under the now line steps aside.
    private func drawGrid(in graphics: GraphicsContext) {
        let firstSecond = Double((Look.bodyTop - scroll) / Look.pointsPerSecond)
        let lastSecond = firstSecond + Double(Self.bodyHeight / Look.pointsPerSecond)
        let step = Clock.gridSecond(1)
        let nowY = y(position)
        for index in max(0, Int((firstSecond / step).rounded(.down)))...max(0, Int((lastSecond / step).rounded(.up))) {
            let second = Clock.gridSecond(index), lineY = y(second), isHour = index % 2 == 0
            graphics.fill(Path(CGRect(x: Look.eventsLeft - 4, y: lineY, width: Look.card.width - Look.eventsLeft, height: 0.75)),
                          with: .color(.white.opacity(isHour ? 0.11 : 0.05)))
            let clearance = clamp01((abs(lineY - nowY) - 16) / 10)
            let label = Text(Clock.label(second, short: true))
                .font(.system(size: isHour ? 10.5 : 9.5, weight: isHour ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(.white.opacity((isHour ? 0.55 : 0.28) * clearance))
            graphics.draw(label, at: CGPoint(x: Look.hourColumn - 8, y: lineY), anchor: .trailing)
        }
    }

    private func drawEvents(in graphics: GraphicsContext) {
        let top = Look.bodyTop - Look.card.height, bottom = Look.card.height * 2
        // The running event is drawn last and the one it took over from just before, over any neighbour they grow across.
        let front = current.map { [$0 - 1, $0].filter(events.indices.contains) } ?? []
        for index in events.indices.filter({ !front.contains($0) }) + front {
            let eventY = y(events[index].start)
            guard eventY < bottom, eventY + events[index].height + Look.titleRow * 3 > top else { continue }
            drawEvent(index, in: graphics)
        }
    }

    /// 0 until `time`, then up to 1 over `span` seconds (a step under reduce motion).
    private func ramp(after time: Double, over span: Double) -> Double {
        motion == 0 ? (position >= time ? 1 : 0) : smooth((position - time) / span)
    }

    /// 1 until the event after `index` starts, then down to 0.
    private func handover(_ index: Int) -> Double {
        events.indices.contains(index + 1) ? 1 - ramp(after: events[index + 1].start, over: Look.settle) : 1
    }

    private func drawEvent(_ index: Int, in graphics: GraphicsContext) {
        let event = events[index]
        // How far it has begun, and how much it is the running event: up as it starts, down as it ends or is taken over.
        let begun = ramp(after: event.start, over: Look.settle)
        let live = begun * (1 - ramp(after: event.end + Look.linger, over: Look.settle)) * handover(index)
        let x = Look.eventsLeft + event.indent, width = Look.card.width - Look.eventsRight - x
        let textWidth = width - Look.textInset.width - Look.bar - 6
        let title = graphics.resolve(titleText(of: event, live: live, begun: begun))
        // The running event grows, if it must, until its whole title fits, and settles back when the next one starts.
        let fit = title.measure(in: CGSize(width: textWidth, height: 1_000)).height + 2 * Look.textInset.height
        let growth = ramp(after: event.start, over: Look.growTime) * handover(index)
        let height = event.height + max(0, fit - event.height) * growth
        let rect = CGRect(x: x, y: y(event.start), width: width, height: height)
        let shape = Path(roundedRect: rect, cornerRadius: Look.radius, style: .continuous)

        func tone(upcoming: Double, past: Double, running: Double) -> Double { mix(mix(upcoming, past, begun), running, live) }
        if event.indent > 0 { graphics.stroke(shape, with: .color(Look.background), lineWidth: 3) }
        // Opaque, so the grid and the now line pass behind it.
        graphics.fill(shape, with: .color(Look.background))
        graphics.fill(shape, with: .color(event.tint.opacity(tone(upcoming: 0.09, past: 0.15, running: 0.30))))
        if live > 0 { graphics.stroke(shape, with: .color(event.tint.opacity(0.7 * live)), lineWidth: 1) }
        var inside = graphics
        inside.clip(to: shape)
        if live > 0 {
            // The part of the event already behind the now line is a shade lighter.
            inside.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y(position) - rect.minY)),
                        with: .color(event.tint.opacity(0.14 * live)))
        }
        inside.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: Look.bar, height: rect.height)),
                    with: .color(event.tint.opacity(tone(upcoming: 0.35, past: 0.55, running: 1))))

        // Whole rows only: a resting event shows as much of its title as its time allows.
        let rows = max(1, ((height - 2 * Look.textInset.height) / Look.titleRow).rounded(.down))
        let textRect = CGRect(x: rect.minX + Look.bar + Look.textInset.width, y: rect.minY + Look.textInset.height,
                              width: textWidth, height: min(fit - 2 * Look.textInset.height, rows * Look.titleRow))
        inside.draw(title, in: textRect)
        if textRect.maxY + Look.timeRow <= rect.maxY - Look.textInset.height + 1 {
            let time = Text("\(Clock.label(event.start)) – \(Clock.label(event.end))").font(.system(size: 10, weight: .medium))
                .foregroundStyle(event.tint.opacity(tone(upcoming: 0.36, past: 0.55, running: 1)))
            inside.draw(time, at: CGPoint(x: textRect.minX, y: textRect.maxY + 1), anchor: .topLeading)
        }
    }

    /// While running: sung words bright (each fading up as it starts), the rest faint. Otherwise one tone.
    private func titleText(of event: CalendarEvent, live: Double, begun: Double) -> Text {
        let font = Font.system(size: 12.5, weight: .semibold)
        let faint = 0.34, resting = mix(faint, 0.62, begun)
        return event.words.enumerated().reduce(Text("")) { text, entry in
            let (index, word) = entry
            let sung = faint + (1 - faint) * (motion == 0 ? (position >= word.start ? 1 : 0) : clamp01((position - word.start) / Look.wordFade))
            let piece = Text(word.text).font(font).foregroundStyle(.white.opacity(mix(resting, sung, live)))
            return index == 0 ? piece : text + Text(" ").font(font) + piece
        }
    }

    /// The now line runs behind the events, so it never strikes through a title.
    private func drawNowLine(in graphics: GraphicsContext) {
        let lineY = y(position)
        graphics.fill(Path(CGRect(x: Look.eventsLeft - 4, y: lineY - 0.75, width: Look.card.width, height: 1.5)), with: .color(Look.now))
    }

    /// The dot that leads the now line, and the current time in a pill over the hour column.
    private func drawNowPill(in graphics: GraphicsContext) {
        let lineY = y(position)
        graphics.fill(Path(ellipseIn: CGRect(x: Look.eventsLeft - 9, y: lineY - 4.5, width: 9, height: 9)), with: .color(Look.now))
        let label = graphics.resolve(Text(Clock.label(position, short: false).replacingOccurrences(of: " AM", with: "")
                                            .replacingOccurrences(of: " PM", with: ""))
            .font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(.white))
        let size = label.measure(in: CGSize(width: 100, height: 30))
        let pill = CGRect(x: Look.hourColumn - 8 - size.width - 10, y: lineY - 8, width: size.width + 10, height: 16)
        graphics.fill(Path(roundedRect: pill, cornerRadius: 8), with: .color(Look.now))
        graphics.draw(label, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
    }

    /// The day melts into the card at the top and bottom of the body.
    private func drawFades(in graphics: GraphicsContext) {
        let clear = Look.background.opacity(0)
        graphics.fill(Path(CGRect(x: 0, y: Look.bodyTop, width: Look.card.width, height: Look.fadeTop)),
                      with: .linearGradient(Gradient(colors: [Look.background, clear]), startPoint: CGPoint(x: 0, y: Look.bodyTop),
                                            endPoint: CGPoint(x: 0, y: Look.bodyTop + Look.fadeTop)))
        graphics.fill(Path(CGRect(x: 0, y: Look.card.height - Look.fadeBottom, width: Look.card.width, height: Look.fadeBottom)),
                      with: .linearGradient(Gradient(colors: [clear, Look.background]),
                                            startPoint: CGPoint(x: 0, y: Look.card.height - Look.fadeBottom),
                                            endPoint: CGPoint(x: 0, y: Look.card.height)))
    }
}

// MARK: - Self-check

/// Checks of the day rules, in the form `runSelfCheck` expects: one message per failure.
func calendarStyleSelfCheck() -> [String] {
    func line(_ number: Int, from start: Double, count: Int, spacing: Double = 0.4) -> [TimedWord] {
        (0..<count).map { TimedWord(text: "w\($0)", start: start + spacing * Double($0), end: start + spacing * Double($0) + 0.35, line: number) }
    }
    // A short line followed closely by another, a long one, then a duet line that starts inside the long one.
    let lines = [line(0, from: 1, count: 1), line(1, from: 3, count: 12), line(2, from: 4, count: 3)] + (3..<12).map { line($0, from: 20 + Double($0) * 4, count: 4) }
    let events = CalendarDay.events(lines)
    let tints = events.map(\.tint)
    let checks: [(Bool, String)] = [
        (Clock.label(0) == "7:00 AM" && Clock.label(75) == "12:00 PM" && Clock.label(1.5, short: true) == "7:06"
            && Clock.label(15, short: true) == "8 AM" && Clock.label(-3) == "7:00 AM", "calendar: song seconds read as clock times"),
        (events.count == lines.count && events[0].height >= Look.minHeight && events[0].top + events[0].height <= events[1].top,
         "calendar: a short event is tall enough for its title but stops before the next one"),
        (events[1].indent == 0 && events[2].indent == Look.indent, "calendar: an event that starts under the one before it is indented"),
        (zip(tints, tints.dropFirst()).allSatisfy { $0 != $1 } && zip(tints, tints.dropFirst(2)).allSatisfy { $0 != $1 },
         "calendar: no event shares a colour with either of the two before it"),
    ]
    return checks.filter { !$0.0 }.map(\.1)
}
