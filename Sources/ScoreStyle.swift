import CoreText
import SwiftUI

/// Score: a five-line staff runs across the band with a treble clef at its left end and a playhead near the centre.
/// The music scrolls left with the song. Every word sits under a note placed at its start time, the note's value
/// follows how long the word is held, and its height follows a gentle melodic contour across the line. The note at
/// the playhead lights up and its word turns bright; notes ahead are faint and notes behind dim. Lines are divided
/// by bar lines. Everything is a closed-form function of the song position, drawn in one Canvas.
struct ScoreStyle: View {
    let context: StyleContext

    var body: some View {
        let scene = ScoreScene(context: context)
        Canvas { graphics, _ in scene.draw(in: &graphics) }
            .frame(width: context.canvas.width, height: scene.height)
            .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
            .opacity(scene.presence)
    }
}

private enum Metrics {
    // Geometry, in staff spaces (the gap between two staff lines) unless noted.
    static let space = 0.052                            // of the band, at Size 100%
    static let staffWidth = 0.7, widestStaff = 0.94     // of the screen width
    static let blockHeight = 10.0                       // clef top to the bottom of the words
    static let staffTopFromCentre = 3.1
    static let clefRoom = 4.4, clefInset = 0.45, clefHeight = 7.1, clefDrop = 1.55  // clef bottom sits this far below the staff
    static let playheadAt = 0.42                        // of the stretch between the clef and the staff's end
    static let fadeLeft = 2.5, fadeRight = 5.0
    static let labelSize = 1.35, labelDrop = 3.2        // label centre below the bottom line
    static let headWidth = 1.3, headHeight = 0.9, headTilt = -0.35   // radians
    static let wholeWidth = 1.75, wholeHeight = 1.0
    static let hollowWidth = 0.92, hollowHeight = 0.42, hollowTilt = -0.62, wholeHoleTilt = 1.05
    static let stemLength = 3.5, stemWidth = 0.1, stemInset = 0.13
    static let staffLineWidth = 0.075, barWidth = 0.11, systemWidth = 0.12
    static let playheadAbove = 2.3, playheadBelow = 2.0, playheadWidth = 0.08, playheadOpacity = 0.6
    static let markerSize = 0.42
    static let flagSize = 0.82

    // Spacing: notes sit at their time, but never closer than their words allow.
    static let speed = 9.0                              // spaces per second
    static let longestTimedGap = 14.0
    static let labelGap = 0.7, minNoteGap = 2.2, barRoom = 2.4

    // Note values, by how long the word is held (seconds).
    static let eighthBelow = 0.3, quarterBelow = 0.62, halfBelow = 1.5

    // Melody: staff positions counted in half spaces up from the bottom line; -1 and 9 need no ledger lines.
    static let lowestPitch = -1, highestPitch = 9, stemsDownFrom = 4
    static let contourCentre = 2.5...5.5, archHeight = 2.2...4.2, wobble = 1.1, step = 1.4

    // Light
    static let minLit = 0.15, litTail = 0.05, settle = 0.25
    static let futureNote = 0.5, passedNote = 0.42, futureWord = 0.3, passedWord = 0.5
    static let staffOpacity = 0.55, barOpacity = 0.5, clefOpacity = 0.85
    static let glowRadius = 0.55, pop = 0.22, popDecay = 0.12

    // Scene
    static let fadeIn = 0.3, fadeOut = 0.5
    static let shadowOpacity = 0.55, shadowRadius = 7.0, shadowY = 2.0
}

private enum Salt {
    static let centre: UInt64 = 0x5C01, arch: UInt64 = 0x5C02, direction: UInt64 = 0x5C03
    static let phase: UInt64 = 0x5C04, step: UInt64 = 0x5C05
}

private func unit(_ value: Double) -> Double { min(1, max(0, value)) }
private func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
private func lerp(_ range: ClosedRange<Double>, _ amount: Double) -> Double { range.lowerBound + (range.upperBound - range.lowerBound) * amount }

/// The treble clef from Apple Symbols (U+1D11E) as an outline, flipped to y-down; empty if the font lacks it.
private let trebleClef: Path = {
    let font = CTFontCreateWithName("Apple Symbols" as CFString, 100, nil)
    var characters = Array("\u{1D11E}".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
          let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return Path() }
    return Path(outline).applying(CGAffineTransform(scaleX: 1, y: -1))
}()

/// How visible the whole score is: it fades in after a silence and out before one, never between joined lines.
private func visibility(_ context: StyleContext) -> Double {
    let lines = context.lyrics.lines, index = context.line.index
    guard let first = context.line.words.first?.start, let lastEnd = context.line.words.last?.end else { return 1 }
    let opensAfterGap = index == 0 || first - (lines[index - 1].last?.end ?? 0) > Timing.lineLinger
    let closesIntoGap = index + 1 >= lines.count || lines[index + 1][0].start - lastEnd > Timing.lineLinger
    let fadeIn = opensAfterGap ? unit((context.position - first) / Metrics.fadeIn) : 1
    let fadeOut = closesIntoGap ? unit((lastEnd + Timing.lineLinger - context.position) / Metrics.fadeOut) : 1
    return smooth(fadeIn) * smooth(fadeOut)
}

private enum NoteValue {
    case eighth, quarter, half, whole

    init(held: Double) {
        switch held {
        case ..<Metrics.eighthBelow: self = .eighth
        case ..<Metrics.quarterBelow: self = .quarter
        case ..<Metrics.halfBelow: self = .half
        default: self = .whole
        }
    }
}

private struct Note {
    let word: TimedWord
    let x: Double           // on screen
    let pitch: Int
    let value: NoteValue
    let lit: Double         // 1 while sung, easing to 0 after
    let reached: Bool
    let fade: Double        // near the ends of the staff
}

private struct ScoreScene {
    let space: Double
    let height: Double
    let left: Double, right: Double, notesLeft: Double
    let staffTop: Double
    let playX: Double
    let notes: [Note]
    let bars: [Double]
    let presence: Double
    let text: Color, accent: Color
    let labelFont: Font
    let position: Double
    let calm: Bool

    var staffBottom: Double { staffTop + 4 * space }

    init(context: StyleContext) {
        let space = context.band * Metrics.space * context.scale
        let width = context.canvas.width * min(Metrics.widestStaff, Metrics.staffWidth * context.scale)
        self.space = space
        height = max(context.band, Metrics.blockHeight * space)
        left = (context.canvas.width - width) / 2
        right = left + width
        notesLeft = left + Metrics.clefRoom * space
        staffTop = height / 2 - Metrics.staffTopFromCentre * space
        playX = notesLeft + (right - notesLeft) * Metrics.playheadAt
        presence = visibility(context)
        text = Color(nsColor: context.settings.textColor)
        accent = Color(nsColor: context.settings.highlightColor)
        labelFont = context.font(Metrics.labelSize * space)
        position = context.position
        calm = context.settings.reduceMotion
        (notes, bars) = Self.layout(context: context, space: space, playX: playX, notesLeft: notesLeft, right: right,
                                    staffWidth: width)
    }

    // MARK: Layout

    /// Places the words around the newest one. Spacing between two neighbours depends only on those two words, so
    /// the score scrolls without anything reflowing, whichever word is the anchor.
    private static func layout(context: StyleContext, space: Double, playX: Double, notesLeft: Double, right: Double,
                               staffWidth: Double) -> ([Note], [Double]) {
        let words = context.lyrics.words
        guard !words.isEmpty else { return ([], []) }
        let anchor = min(max(0, context.newestWordIndex), words.count - 1)
        let measuring = context.settings.font.font(size: Metrics.labelSize * space)
        var widths: [Int: Double] = [:]
        func width(_ index: Int) -> Double {
            if let known = widths[index] { return known }
            let measured = Double((words[index].text as NSString).size(withAttributes: [.font: measuring]).width)
            widths[index] = measured
            return measured
        }
        func spacing(_ a: Int, _ b: Int) -> Double {
            let timed = min(Metrics.longestTimedGap, max(0, words[b].start - words[a].start) * Metrics.speed) * space
            let room = (width(a) + width(b)) / 2 + Metrics.labelGap * space
            let bar = words[a].line != words[b].line ? Metrics.barRoom * space : 0
            return max(timed, room, Metrics.minNoteGap * space) + bar
        }
        // Score positions relative to the anchor, reaching a staff's width either way.
        var placed: [(index: Int, x: Double)] = [(anchor, 0)]
        while let first = placed.first, first.index > 0, first.x > -staffWidth {
            placed.insert((first.index - 1, first.x - spacing(first.index - 1, first.index)), at: 0)
        }
        while let last = placed.last, last.index < words.count - 1, last.x < staffWidth {
            placed.append((last.index + 1, last.x + spacing(last.index, last.index + 1)))
        }
        // Where the playhead is in score positions: travelling from the anchor's note to the next one.
        let time = context.position, current = words[anchor]
        let head: Double
        if anchor + 1 < words.count, let next = placed.first(where: { $0.index == anchor + 1 }) {
            let span = words[anchor + 1].start - current.start
            head = span > 0 ? next.x * unit((time - current.start) / span) : 0
        } else {
            head = min(Metrics.minNoteGap * space, max(0, time - current.start) * Metrics.speed * space)
        }
        let shift = playX - head
        let melody = Melody(words: words)
        let notes = placed.map { entry -> Note in
            let word = words[entry.index], x = entry.x + shift
            // A note hands the light on to the next one rather than sharing it.
            let nextStart = entry.index + 1 < words.count ? max(word.start, words[entry.index + 1].start) : .infinity
            let litUntil = min(max(word.end, word.start + Metrics.minLit) + Metrics.litTail, nextStart)
            let lit = time < word.start ? 0 : (time < litUntil ? 1 : unit(1 - (time - litUntil) / Metrics.settle))
            let fade = smooth(unit((x - notesLeft) / (Metrics.fadeLeft * space))) * smooth(unit((right - x) / (Metrics.fadeRight * space)))
            return Note(word: word, x: x, pitch: melody.pitch(of: entry.index), value: NoteValue(held: word.end - word.start),
                        lit: lit, reached: time >= word.start, fade: fade)
        }
        // A bar line in the middle of the free space between the last word of one line and the first of the next.
        let bars = zip(placed, placed.dropFirst()).compactMap { a, b -> Double? in
            guard words[a.index].line != words[b.index].line else { return nil }
            let leftEdge = a.x + width(a.index) / 2, rightEdge = b.x - width(b.index) / 2
            return (leftEdge + rightEdge) / 2 + shift
        }
        return (notes, bars)
    }

    // MARK: Drawing

    func y(of pitch: Int) -> Double { staffBottom - Double(pitch) * space / 2 }

    func draw(in graphics: inout GraphicsContext) {
        drawStaff(in: &graphics)
        drawClef(in: &graphics)
        for x in bars where x > notesLeft && x < right {
            let fade = smooth(unit((x - notesLeft) / (Metrics.fadeLeft * space))) * smooth(unit((right - x) / (Metrics.fadeRight * space)))
            graphics.stroke(Path { $0.move(to: CGPoint(x: x, y: staffTop)); $0.addLine(to: CGPoint(x: x, y: staffBottom)) },
                            with: .color(text.opacity(Metrics.barOpacity * fade)), lineWidth: Metrics.barWidth * space)
        }
        drawPlayhead(in: &graphics)
        let visible = notes.filter { $0.fade > 0 }
        for note in visible { drawNote(note, in: &graphics) }
        for note in visible { drawLabel(note, in: &graphics) }
    }

    private func drawStaff(in graphics: inout GraphicsContext) {
        let lines = Path { path in
            for line in 0..<5 {
                let y = staffTop + Double(line) * space
                path.move(to: CGPoint(x: left, y: y))
                path.addLine(to: CGPoint(x: right, y: y))
            }
        }
        // The lines thin away at the right instead of stopping dead.
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [.init(color: text.opacity(Metrics.staffOpacity), location: 0),
                             .init(color: text.opacity(Metrics.staffOpacity), location: max(0, 1 - Metrics.fadeRight * space / (right - left))),
                             .init(color: text.opacity(0), location: 1)]),
            startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0))
        graphics.stroke(lines, with: shading, lineWidth: max(0.8, Metrics.staffLineWidth * space))
        graphics.stroke(Path { $0.move(to: CGPoint(x: left, y: staffTop)); $0.addLine(to: CGPoint(x: left, y: staffBottom)) },
                        with: .color(text.opacity(Metrics.staffOpacity)), lineWidth: Metrics.systemWidth * space)
    }

    private func drawClef(in graphics: inout GraphicsContext) {
        let bounds = trebleClef.boundingRect
        guard bounds.height > 0 else { return }
        let size = Metrics.clefHeight * space / bounds.height
        let transform = CGAffineTransform(translationX: left + Metrics.clefInset * space, y: staffBottom + Metrics.clefDrop * space)
            .scaledBy(x: size, y: size)
            .translatedBy(x: -bounds.minX, y: -bounds.maxY)
        graphics.fill(trebleClef.applying(transform), with: .color(text.opacity(Metrics.clefOpacity)))
    }

    private func drawPlayhead(in graphics: inout GraphicsContext) {
        let top = staffTop - Metrics.playheadAbove * space, bottom = staffBottom + Metrics.playheadBelow * space
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [accent.opacity(0), accent.opacity(Metrics.playheadOpacity), accent.opacity(Metrics.playheadOpacity), accent.opacity(0)]),
            startPoint: CGPoint(x: playX, y: top), endPoint: CGPoint(x: playX, y: bottom))
        graphics.stroke(Path { $0.move(to: CGPoint(x: playX, y: top)); $0.addLine(to: CGPoint(x: playX, y: bottom)) },
                        with: shading, lineWidth: Metrics.playheadWidth * space)
        let marker = Metrics.markerSize * space, markerTop = top - marker
        graphics.fill(Path { path in
            path.move(to: CGPoint(x: playX - marker, y: markerTop))
            path.addLine(to: CGPoint(x: playX + marker, y: markerTop))
            path.addLine(to: CGPoint(x: playX, y: markerTop + marker * 1.3))
            path.closeSubpath()
        }, with: .color(accent.opacity(Metrics.playheadOpacity)))
    }

    private func drawNote(_ note: Note, in graphics: inout GraphicsContext) {
        let base = note.reached ? Metrics.passedNote : Metrics.futureNote
        let colour = text.opacity(base * (1 - note.lit)).mix(with: accent, by: note.lit)
        let age = position - note.word.start
        let pop = calm || note.lit == 0 ? 1 : 1 + Metrics.pop * exp(-max(0, age) / Metrics.popDecay)
        let shape = notePath(note, pop: pop)
        guard note.lit > 0 else {
            graphics.fill(shape, with: .color(colour.opacity(note.fade)))
            return
        }
        graphics.drawLayer { layer in
            layer.opacity = note.fade
            layer.addFilter(.shadow(color: accent.opacity(note.lit), radius: Metrics.glowRadius * space))
            layer.fill(shape, with: .color(colour))
        }
    }

    /// Head, stem and flag as one non-zero path, so overlaps merge; a hollow head's hole is wound the other way.
    private func notePath(_ note: Note, pop: Double) -> Path {
        let centre = CGPoint(x: note.x, y: y(of: note.pitch))
        func ellipse(_ width: Double, _ height: Double, tilt: Double, hole: Bool = false) -> Path {
            // Mirroring a symmetric ellipse leaves its shape alone but reverses its winding.
            Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                .applying(CGAffineTransform(scaleX: hole ? -1 : 1, y: 1).rotated(by: hole ? -tilt : tilt)
                    .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y)))
        }
        let s = space * pop
        var path = Path()
        switch note.value {
        case .whole:
            path.addPath(ellipse(Metrics.wholeWidth * s, Metrics.wholeHeight * s, tilt: 0))
            path.addPath(ellipse(Metrics.hollowWidth * s, Metrics.hollowHeight * 1.3 * s, tilt: Metrics.wholeHoleTilt, hole: true))
            return path
        case .half:
            path.addPath(ellipse(Metrics.headWidth * s, Metrics.headHeight * s, tilt: Metrics.headTilt))
            path.addPath(ellipse(Metrics.hollowWidth * s, Metrics.hollowHeight * s, tilt: Metrics.hollowTilt, hole: true))
        case .quarter, .eighth:
            path.addPath(ellipse(Metrics.headWidth * s, Metrics.headHeight * s, tilt: Metrics.headTilt))
        }
        // Stems go down on the left from the middle line up, otherwise up on the right; flags always point right.
        let down = note.pitch >= Metrics.stemsDownFrom
        let stemWidth = Metrics.stemWidth * space
        let stemX = centre.x + (down ? -1 : 1) * (Metrics.headWidth / 2 - Metrics.stemInset) * s - (down ? 0 : stemWidth)
        let tipY = centre.y + (down ? 1 : -1) * Metrics.stemLength * space
        path.addRect(CGRect(x: stemX, y: min(centre.y, tipY), width: stemWidth, height: abs(tipY - centre.y)))
        if note.value == .eighth { path.addPath(flag(stemX: stemX + stemWidth, tipY: tipY, down: down)) }
        return path
    }

    private func flag(stemX: Double, tipY: Double, down: Bool) -> Path {
        let g = space * Metrics.flagSize, toward: Double = down ? -1 : 1   // the flag curls back toward the head
        func point(_ dx: Double, _ dy: Double) -> CGPoint { CGPoint(x: stemX + dx * g, y: tipY + toward * dy * g) }
        return Path { path in
            path.move(to: point(0, 0))
            path.addCurve(to: point(0.95, 2.4), control1: point(0.15, 1.0), control2: point(1.35, 1.3))
            path.addCurve(to: point(0.75, 3.0), control1: point(0.95, 2.65), control2: point(0.88, 2.85))
            path.addCurve(to: point(0, 1.1), control1: point(0.95, 2.1), control2: point(0.4, 1.5))
            path.closeSubpath()
        }
    }

    private func drawLabel(_ note: Note, in graphics: inout GraphicsContext) {
        let base = note.reached ? Metrics.passedWord : Metrics.futureWord
        let opacity = (base + (1 - base) * note.lit) * note.fade
        let label = Text(note.word.text).font(labelFont).foregroundColor(text.opacity(opacity))
        graphics.draw(label, at: CGPoint(x: note.x, y: staffBottom + Metrics.labelDrop * space), anchor: .center)
    }
}

/// The note heights: a smooth contour per line (an arch up or down around a centre, with a slow wave), plus a small
/// step of its own for each word. It depends only on the word and its own line, so a note never changes height.
private struct Melody {
    let words: [TimedWord]

    func pitch(of index: Int) -> Int {
        let line = words[index].line
        var first = index, last = index
        while first > 0, words[first - 1].line == line { first -= 1 }
        while last < words.count - 1, words[last + 1].line == line { last += 1 }
        let seed = words[first].start
        let along = last > first ? Double(index - first) / Double(last - first) : 0.5
        let centre = lerp(Metrics.contourCentre, seededUnit(seed, salt: Salt.centre))
        let arch = lerp(Metrics.archHeight, seededUnit(seed, salt: Salt.arch)) * (seededUnit(seed, salt: Salt.direction) < 0.5 ? 1 : -1)
        let phase = 2 * .pi * seededUnit(seed, salt: Salt.phase)
        let step = (seededUnit(words[index].start, salt: Salt.step) - 0.5) * Metrics.step
        let wave = Metrics.wobble * sin(3 * .pi * along + phase)
        let pitch = centre + arch * (sin(.pi * along) - 0.5) + wave + step
        return min(Metrics.highestPitch, max(Metrics.lowestPitch, Int(pitch.rounded())))
    }
}
