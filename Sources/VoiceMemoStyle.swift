import AppKit
import SwiftUI

/// Voice Memo: the song as a list of recordings. Every lyric line is one take: the line being sung is the open
/// item at the foot of the list, its waveform drawing itself left to right behind a playhead while the transcript
/// underneath lights up word by word; the lines before it sit above as closed rows with their length. The
/// waveform is made up from the word timings (a burst at each word, dying away), not from the audio. Drawn on a
/// virtual card `Look.card` units big, scaled to the screen; every frame is a closed-form function of the
/// playback position, so it holds through gaps and before the first line.
struct VoiceMemoStyle: View {
    let context: StyleContext

    var body: some View {
        let unit = Look.unit(for: context)
        let list = MemoList(context: context)
        // A card taller than the band at large sizes overflows it rather than being cut off.
        let height = max(context.band, Look.card.height * unit + 2 * Look.shadowRoom)
        // Faded out after the song ends: nothing to draw, so no canvas pass at all.
        if list.opacity < 0.002 {
            Color.clear.frame(width: context.canvas.width, height: context.band)
        } else {
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { graphics, size in
                guard unit > 0 else { return }
                var sheet = graphics
                sheet.translateBy(x: (size.width - Look.card.width * unit) / 2, y: (size.height - Look.card.height * unit) / 2)
                sheet.scaleBy(x: unit, y: unit)
                list.draw(in: sheet)
            }
            .frame(width: context.canvas.width, height: height)
            .opacity(list.opacity)
            .shadow(color: .black.opacity(Look.shadowOpacity), radius: Look.shadowRadius, y: Look.shadowY)
        }
    }
}

// MARK: - Constants (card units unless noted)

private enum Look {
    static let card = CGSize(width: 460, height: 350), cardRadius: CGFloat = 26
    static let heightShare = 0.8, widthShare = 0.92, screenShare = 0.9    // of the band, the canvas width and height
    static let shadowRoom: CGFloat = 40                                     // points
    static let shadowOpacity = 0.45, shadowRadius: CGFloat = 18, shadowY: CGFloat = 8

    static let background = Color(.sRGB, red: 0.075, green: 0.059, blue: 0.118)
    static let hairline = Color.white.opacity(0.08)
    static let teal = Color(.sRGB, red: 0.204, green: 0.878, blue: 0.769)
    static let violet = Color(.sRGB, red: 0.561, green: 0.42, blue: 1)

    // Header
    static let inset: CGFloat = 22
    static let titleY: CGFloat = 20, dividerY: CGFloat = 60

    // List
    static let listTop: CGFloat = 61, listBottom: CGFloat = 12
    static let rowHeight: CGFloat = 50, fade: CGFloat = 26, panelGap: CGFloat = 6

    // The open take
    static let panelInset: CGFloat = 12, panelRadius: CGFloat = 18, padding: CGFloat = 16
    static let headline: CGFloat = 20, subline: CGFloat = 16
    static let waveTop: CGFloat = 12, waveHeight: CGFloat = 50, bars = 60, barShare: CGFloat = 0.52, barFloor: CGFloat = 2.4
    static let axis: CGFloat = 18, transcriptGap: CGFloat = 6, transcriptLine: CGFloat = 20
    static let openTime = 0.35, linger = 0.6, wordFade = 0.1, pulseSpeed = 4.2

    // Gaps and the end of the song
    static let endAfter = 4.0, endRamp = 2.5

    /// Points per card unit: the card is `heightShare` of the band tall at Size 100 %, but never wider or taller than the screen allows.
    static func unit(for context: StyleContext) -> CGFloat {
        min(context.band * heightShare * context.scale / card.height, context.canvas.width * widthShare / card.width,
            context.canvas.height * screenShare / card.height)
    }
}

/// How the made-up waveform responds to the words.
private enum Wave {
    static let attack = 0.03, decay = 0.15, burst = 1.0, sustain = 0.14, release = 0.08, floor = 0.06
    static let grain = 0.55             // how much each bar varies from its neighbours
    static let salt: UInt64 = 0x40E0
}

private func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }
private func smooth(_ value: Double) -> Double { clamp01(value) * clamp01(value) * (3 - 2 * clamp01(value)) }

/// "0:07" or, with `padded`, "00:07".
private func duration(_ seconds: Double, padded: Bool = false) -> String {
    let whole = Int(max(0, seconds).rounded(.down))
    return String(format: padded ? "%02d:%02d" : "%d:%02d", whole / 60, whole % 60)
}

// MARK: - The list at one instant

/// One lyric line as a recording.
private struct Take {
    let number: Int
    let words: [TimedWord]
    let start: Double, end: Double

    var length: Double { max(end - start, 0.5) }
    var text: String { words.map(\.text).joined(separator: " ") }

    /// Loudness of the made-up waveform at song second `time`, 0...1: a burst at every word start that dies away,
    /// a little held while the word lasts, roughened per bar so neighbours differ.
    func level(at time: Double, bar: Int) -> Double {
        let energy = words.reduce(0.0) { sum, word in
            let since = time - word.start
            guard since >= 0 else { return sum }
            let burst = Wave.burst * min(1, since / Wave.attack) * exp(-since / Wave.decay)
            let held = time < word.end ? Wave.sustain : Wave.sustain * exp(-(time - word.end) / Wave.release)
            return sum + burst + held
        }
        let grain = 1 - Wave.grain + Wave.grain * seededUnit(start + Double(bar) * 0.37, salt: Wave.salt)
        return min(1, Wave.floor + energy * grain)
    }
}

private struct MemoList {
    enum State { case ready, live, saved }

    let position: Double, clock: Double, motion: Double
    let trackTitle: String
    let takes: [Take]
    /// The take that has started most recently; before the first line, the first take, waiting.
    let open: Int?
    let opacity: Double

    init(context: StyleContext) {
        position = context.position
        clock = context.clock
        motion = context.settings.reduceMotion ? 0 : 1
        trackTitle = context.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        takes = context.lyrics.lines.enumerated().compactMap { index, line in
            // Overlapping voices need not be in time order: a line spans its earliest start to its latest end.
            guard let start = line.map(\.start).min(), let end = line.map(\.end).max() else { return nil }
            return Take(number: index + 1, words: line.filter { !$0.text.isEmpty }, start: start, end: end)
        }
        let position = context.position
        open = takes.lastIndex { $0.start <= position } ?? (takes.isEmpty ? nil : 0)
        let lastEnd = takes.map(\.end).max() ?? 0
        opacity = 1 - smooth((context.position - lastEnd - Look.endAfter) / Look.endRamp)
    }

    func state(of take: Take) -> State {
        position < take.start ? .ready : position < take.end + Look.linger ? .live : .saved
    }
}

// MARK: - Drawing

extension MemoList {
    func draw(in graphics: GraphicsContext) {
        let card = Path(roundedRect: CGRect(origin: .zero, size: Look.card), cornerRadius: Look.cardRadius, style: .continuous)
        graphics.fill(card, with: .color(Look.background))
        drawHeader(in: graphics)
        var list = graphics
        list.clip(to: card)
        list.clip(to: Path(CGRect(x: 0, y: Look.listTop, width: Look.card.width, height: Look.card.height - Look.listTop)))
        if let open { drawList(open: open, in: list) }
        graphics.stroke(card, with: .color(Look.hairline), lineWidth: 1)
    }

    private func drawHeader(in graphics: GraphicsContext) {
        graphics.draw(Text("Recordings").font(.system(size: 23, weight: .bold)).foregroundStyle(.white),
                      at: CGPoint(x: Look.inset, y: Look.titleY), anchor: .topLeading)
        let count = takes.filter { $0.start <= position }.count
        let caption = Text(count == 0 ? "No takes yet" : count == 1 ? "1 take" : "\(count) takes").font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        graphics.draw(caption, at: CGPoint(x: Look.card.width - Look.inset, y: Look.titleY + 15), anchor: .trailing)
        graphics.fill(Path(CGRect(x: 0, y: Look.dividerY, width: Look.card.width, height: 1)), with: .color(Look.hairline))
    }

    /// The open take at the foot with closed rows stacked above it. When a take starts, the one before it shrinks
    /// into a row while the new one grows in below on the same curve, so nothing in the stack jumps.
    private func drawList(open: Int, in graphics: GraphicsContext) {
        let take = takes[open]
        // The first take is already on show, waiting, before it starts, so it has nothing to open from.
        let opening = open == 0 || motion == 0 ? 1 : smooth((position - take.start) / Look.openTime)
        let bottom = Look.card.height - Look.listBottom
        let (fullHeight, transcript) = panelLayout(of: take, in: graphics)
        let panel = CGRect(x: Look.panelInset, y: bottom - fullHeight * opening, width: panelWidth, height: fullHeight * opening)
        var rowBottom = panel.minY - Look.panelGap * opening
        if open > 0 {
            let outgoing = takes[open - 1], (outgoingHeight, outgoingTranscript) = panelLayout(of: outgoing, in: graphics)
            let slot = Look.rowHeight + (outgoingHeight - Look.rowHeight) * (1 - opening)
            // Its insides are gone by halfway and its row only fades in after, so the two never overlap.
            if opening < 1 {
                var closing = graphics
                closing.opacity = 1 - opening
                drawPanel(outgoing, in: CGRect(x: Look.panelInset, y: rowBottom - slot, width: panelWidth, height: slot),
                          content: 1 - smooth(2 * opening), transcript: outgoingTranscript, in: closing)
            }
            var row = graphics
            row.opacity = smooth(2 * opening - 1)
            drawRow(outgoing, bottom: rowBottom, isLast: true, in: row)
            rowBottom -= slot + Look.panelGap * (1 - opening)
        }
        for index in stride(from: open - 2, through: 0, by: -1) where rowBottom > Look.listTop {
            drawRow(takes[index], bottom: rowBottom, isLast: false, in: graphics)
            rowBottom -= Look.rowHeight
        }
        drawFade(in: graphics)
        if opening > 0 { drawPanel(take, in: panel, content: opening, transcript: transcript, in: graphics) }
    }

    private var panelWidth: CGFloat { Look.card.width - 2 * Look.panelInset }

    /// How tall a take is when open, and its transcript as drawn.
    private func panelLayout(of take: Take, in graphics: GraphicsContext) -> (CGFloat, GraphicsContext.ResolvedText) {
        let transcript = graphics.resolve(transcriptText(of: take))
        let chrome = 2 * Look.padding + Look.headline + Look.subline + Look.waveTop + Look.waveHeight + Look.axis + Look.transcriptGap
        // An extremely long line is cut off (with an ellipsis) rather than pushing the take out of the card.
        let room = Look.card.height - Look.listTop - Look.listBottom - chrome - Look.panelInset
        let height = min(room, transcript.measure(in: CGSize(width: panelWidth - 2 * Look.padding, height: 1_000)).height)
        return (chrome + max(height, Look.transcriptLine), transcript)
    }

    /// A closed take: its words as the title, its number, its length.
    private func drawRow(_ take: Take, bottom: CGFloat, isLast: Bool, in graphics: GraphicsContext) {
        let top = bottom - Look.rowHeight, textWidth = Look.card.width - 2 * Look.inset - 60
        let title = Text(take.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.86))
        graphics.draw(graphics.resolve(title), in: CGRect(x: Look.inset, y: top + 8, width: textWidth, height: 18))
        graphics.draw(Text("Recording \(take.number)").font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.4)),
                      at: CGPoint(x: Look.inset, y: top + 28), anchor: .topLeading)
        graphics.draw(Text(duration(take.length)).font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5)), at: CGPoint(x: Look.card.width - Look.inset, y: top + Look.rowHeight / 2), anchor: .trailing)
        if !isLast {
            graphics.fill(Path(CGRect(x: Look.inset, y: bottom - 0.5, width: Look.card.width - 2 * Look.inset, height: 0.75)),
                          with: .color(Look.hairline))
        }
    }

    /// Older rows melt into the card under the header.
    private func drawFade(in graphics: GraphicsContext) {
        graphics.fill(Path(CGRect(x: 0, y: Look.listTop, width: Look.card.width, height: Look.fade)),
                      with: .linearGradient(Gradient(colors: [Look.background, Look.background.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: Look.listTop), endPoint: CGPoint(x: 0, y: Look.listTop + Look.fade)))
    }

    // MARK: The open take

    /// One open take; `content` fades what is inside while the panel itself grows.
    private func drawPanel(_ take: Take, in rect: CGRect, content: Double, transcript: GraphicsContext.ResolvedText,
                           in graphics: GraphicsContext) {
        let shape = Path(roundedRect: rect, cornerRadius: Look.panelRadius, style: .continuous)
        graphics.fill(shape, with: .linearGradient(Gradient(colors: [Look.violet.opacity(0.16), Look.teal.opacity(0.07)]),
                                                   startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        graphics.stroke(shape, with: .color(.white.opacity(0.09)), lineWidth: 1)
        var inside = graphics
        inside.clip(to: shape)
        inside.opacity *= content
        let left = rect.minX + Look.padding, right = rect.maxX - Look.padding
        var y = rect.minY + Look.padding

        let usesTrackTitle = !trackTitle.isEmpty
        let title = Text(usesTrackTitle ? trackTitle : "Recording \(take.number)").font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
        inside.draw(inside.resolve(title), in: CGRect(x: left, y: y, width: right - left - 90, height: Look.headline))
        drawStatus(of: take, at: CGPoint(x: right, y: y + Look.headline / 2), in: inside)
        y += Look.headline
        let subtitle = usesTrackTitle ? "Recording \(take.number) · Today" : "Today"
        inside.draw(Text(subtitle).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.45)),
                    at: CGPoint(x: left, y: y), anchor: .topLeading)
        y += Look.subline + Look.waveTop

        drawWave(of: take, in: CGRect(x: left, y: y, width: right - left, height: Look.waveHeight), in: inside)
        y += Look.waveHeight
        let axisFont = Font.system(size: 10, weight: .medium).monospacedDigit()
        inside.draw(Text("0:00").font(axisFont).foregroundStyle(.white.opacity(0.35)), at: CGPoint(x: left, y: y + 5), anchor: .topLeading)
        inside.draw(Text(duration(take.length)).font(axisFont).foregroundStyle(.white.opacity(0.35)),
                    at: CGPoint(x: right, y: y + 5), anchor: .topTrailing)
        y += Look.axis + Look.transcriptGap
        inside.draw(transcript, in: CGRect(x: left, y: y, width: right - left, height: rect.maxY - Look.padding - y))
    }

    /// Elapsed time on the right, behind a teal dot that pulses while the take runs and a tick once it is saved.
    private func drawStatus(of take: Take, at anchor: CGPoint, in graphics: GraphicsContext) {
        let state = state(of: take)
        let elapsed = state == .ready ? 0 : min(position - take.start, take.length)
        let time = graphics.resolve(Text(duration(elapsed, padded: true)).font(.system(size: 16, weight: .semibold).monospacedDigit())
            .foregroundStyle(state == .live ? Look.teal : .white.opacity(0.7)))
        let width = time.measure(in: CGSize(width: 200, height: 40)).width
        graphics.draw(time, at: anchor, anchor: .trailing)
        let mark = CGPoint(x: anchor.x - width - 12, y: anchor.y)
        switch state {
        case .live:
            let pulse = motion == 0 ? 1 : 0.55 + 0.45 * (0.5 + 0.5 * cos(clock * Look.pulseSpeed))
            graphics.fill(Path(ellipseIn: CGRect(x: mark.x - 4, y: mark.y - 4, width: 8, height: 8)), with: .color(Look.teal.opacity(pulse)))
        case .saved:
            graphics.draw(Text(Image(systemName: "checkmark.circle.fill")).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45)), at: mark, anchor: .center)
        case .ready:
            graphics.stroke(Path(ellipseIn: CGRect(x: mark.x - 4, y: mark.y - 4, width: 8, height: 8)),
                            with: .color(.white.opacity(0.4)), lineWidth: 1.2)
        }
    }

    /// Mirrored bars up to the playhead, a dotted track after it.
    private func drawWave(of take: Take, in rect: CGRect, in graphics: GraphicsContext) {
        let slot = rect.width / CGFloat(Look.bars), barWidth = slot * Look.barShare
        let played = state(of: take) == .ready ? 0 : clamp01((position - take.start) / take.length)
        let ink = GraphicsContext.Shading.linearGradient(Gradient(colors: [Look.teal, Look.violet]),
                                                          startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0))
        var bars = Path(), track = Path()
        for bar in 0..<Look.bars {
            let x = rect.minX + (CGFloat(bar) + 0.5) * slot
            // How much of this bar's slice of the take has been heard; the newest bar grows as it fills.
            let heard = clamp01(played * Double(Look.bars) - Double(bar))
            if heard > 0 {
                let time = take.start + (Double(bar) + 0.5) / Double(Look.bars) * take.length
                let height = max(Look.barFloor, rect.height * CGFloat(take.level(at: time, bar: bar) * heard))
                bars.addRoundedRect(in: CGRect(x: x - barWidth / 2, y: rect.midY - height / 2, width: barWidth, height: height),
                                    cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
            } else {
                track.addEllipse(in: CGRect(x: x - 1, y: rect.midY - 1, width: 2, height: 2))
            }
        }
        graphics.fill(track, with: .color(.white.opacity(0.18)))
        graphics.fill(bars, with: ink)
        // The playhead, with a knob on top.
        let headX = rect.minX + rect.width * CGFloat(played)
        graphics.fill(Path(CGRect(x: headX - 0.75, y: rect.minY - 4, width: 1.5, height: rect.height + 8)), with: .color(.white))
        graphics.fill(Path(ellipseIn: CGRect(x: headX - 4, y: rect.minY - 8, width: 8, height: 8)), with: .color(.white))
    }

    /// Sung words white, the word being sung teal, the rest faint.
    private func transcriptText(of take: Take) -> Text {
        let font = Font.system(size: 15, weight: .medium)
        let faint = 0.28, state = state(of: take)
        return take.words.enumerated().reduce(Text("")) { text, entry in
            let (index, word) = entry
            let lit = state == .ready ? 0 : motion == 0 ? (position >= word.start ? 1 : 0) : clamp01((position - word.start) / Look.wordFade)
            let singing = state == .live && position >= word.start && position < word.end
            let color = singing ? Look.teal.opacity(faint + (1 - faint) * lit) : Color.white.opacity(faint + (1 - faint) * lit)
            let piece = Text(word.text).font(font).foregroundStyle(color)
            return index == 0 ? piece : text + Text(" ").font(font) + piece
        }
    }
}

// MARK: - Self-check

/// Checks of the take rules, in the form `runSelfCheck` expects: one message per failure.
func voiceMemoStyleSelfCheck() -> [String] {
    let words = [TimedWord(text: "one", start: 10, end: 10.3, line: 0), TimedWord(text: "two", start: 10.6, end: 11, line: 0)]
    let take = Take(number: 1, words: words, start: 10, end: 11)
    let levels = stride(from: 9.5, through: 12, by: 0.05).map { take.level(at: $0, bar: 0) }
    let checks: [(Bool, String)] = [
        (duration(65.9) == "1:05" && duration(7, padded: true) == "00:07" && duration(-1) == "0:00", "voice memo: lengths read m:ss"),
        (levels.allSatisfy { (0...1).contains($0) }, "voice memo: the waveform stays between silence and full"),
        (take.level(at: 10.08, bar: 3) > take.level(at: 9.9, bar: 3) && take.level(at: 10.08, bar: 3) > take.level(at: 10.5, bar: 3),
         "voice memo: a bar is tallest just after a word starts and dies away after"),
        (Take(number: 1, words: [words[0]], start: 10, end: 10).length == 0.5, "voice memo: a take is never shorter than half a second"),
    ]
    return checks.filter { !$0.0 }.map(\.1)
}
