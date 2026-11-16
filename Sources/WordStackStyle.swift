import SwiftUI

/// Ship, Visual and the Fisheye styles: a rolling vertical stack of the words just sung, newest at the
/// bottom. Each word springs in, sits at a slight random tilt, and scrolls up as later words arrive.
struct WordStackStyle: View {
    enum Kind {
        case ship
        case visual
        case fisheye(icons: Bool)
    }

    private struct Config {
        let rows: Int
        let springResponse: Double, springDamping: Double
        let entryScale: CGFloat
        let tiltDegrees: Double
        let nudge: CGFloat
        let shadowRadius: CGFloat, shadowY: CGFloat
        let alignment: HorizontalAlignment
    }

    private enum Metrics {
        static let capHeight = 0.075        // of screen height, for a word of average length
        static let emphasisRange = 0.75...1.55
        static let maxWordWidth = 0.62      // of screen width
        static let maxStackHeight = 0.8     // of the band
        static let rowSpacing = -0.012      // of screen height
        static let pillChance = 0.2
        static let iconScale = 0.62, iconSpacing = 0.18
        static let backdropScale = 0.55, backdropOpacity = 0.08
        static let fisheyeCapHeight = 0.147, fisheyeMaxWidth = 0.42, fisheyeSpacing = -0.16
        // Size of each row by how many rows are showing: the middle of three is the "centre of the lens".
        static let fisheyeHeights: [[CGFloat]] = [[], [1], [1, 0.85], [0.68, 1, 0.68]]
        static let fisheyeWidths: [[CGFloat]] = [[], [1], [1, 0.72], [0.58, 1, 0.58]]
        static let fisheyeTiltDegrees = 38.0
    }

    private enum Salt {
        static let side: UInt64 = 0x51DE, tilt: UInt64 = 0x7117, nudge: UInt64 = 0x0FF5
    }

    let context: StyleContext
    let kind: Kind

    private var config: Config {
        switch kind {
        case .ship:
            return Config(rows: 5, springResponse: 0.25, springDamping: 0.7, entryScale: 0.3, tiltDegrees: 4.5, nudge: 0.14,
                          shadowRadius: 16, shadowY: 4, alignment: .leading)
        case .visual:
            return Config(rows: 4, springResponse: 0.25, springDamping: 0.7, entryScale: 0.3, tiltDegrees: 3, nudge: 0.06,
                          shadowRadius: 16, shadowY: 4, alignment: .center)
        case .fisheye:
            return Config(rows: 3, springResponse: 0.28, springDamping: 0.72, entryScale: 0.6, tiltDegrees: 2.5, nudge: 0.045,
                          shadowRadius: 20, shadowY: 5, alignment: .center)
        }
    }

    private var showsIcons: Bool {
        switch kind {
        case .ship: return false
        case .visual: return true
        case .fisheye(let icons): return icons
        }
    }

    private var isFisheye: Bool { if case .fisheye = kind { return true } else { return false } }

    var body: some View {
        let config = config
        let words = Array(context.sung.suffix(config.rows))
        let sizes = fontSizes(for: words)
        // Rows are identified by the word's place in the line: start times can repeat, places cannot.
        let firstPlace = context.line.shown - words.count
        let spacing = isFisheye ? Metrics.fisheyeSpacing * fisheyeBase : Metrics.rowSpacing * context.canvas.height
        ZStack {
            if case .visual = kind, let newest = words.last, let visual = WordVisuals.shared.visual(for: newest.text) {
                backdrop(visual).id(context.line.shown).transition(.opacity)
            }
            VStack(alignment: config.alignment, spacing: spacing) {
                ForEach(words.indices, id: \.self) { index in
                    row(words[index], size: sizes[index], isNewest: index == words.count - 1, slot: index, of: words.count)
                        .transition(.scale(scale: config.entryScale).combined(with: .opacity))
                        .id(firstPlace + index)
                }
            }
            // A new line replaces the whole stack rather than scrolling into it.
            .id(context.line.index)
        }
        .animation(.spring(response: config.springResponse, dampingFraction: config.springDamping), value: context.line.shown)
    }

    // MARK: Rows

    private func row(_ word: TimedWord, size: CGFloat, isNewest: Bool, slot: Int, of count: Int) -> some View {
        let config = config
        let side = seededUnit(word.start, salt: Salt.side)
        let tilt = (2 * seededUnit(word.start, salt: Salt.tilt) - 1) * config.tiltDegrees
        let nudge = seededUnit(word.start, salt: Salt.nudge)
        let visual = showsIcons ? WordVisuals.shared.visual(for: word.text) : nil
        let icon = visual.map {
            WordIcon(visual: $0, size: size * Metrics.iconScale, color: Color(nsColor: context.settings.highlightColor),
                     age: context.position - word.start)
        }
        return HStack(spacing: size * Metrics.iconSpacing) {
            if side < 0.5 { icon }
            wordText(word, size: size, isNewest: isNewest, pill: side < Metrics.pillChance)
            if side >= 0.5 { icon }
        }
        .shadow(color: .black.opacity(0.55), radius: config.shadowRadius, y: config.shadowY)
        .lineLimit(1)
        .fixedSize()
        .rotationEffect(.degrees(tilt))
        .modifier(Placement(kind: kind, nudge: nudge, strength: config.nudge, width: context.canvas.width))
        // shortcut: the lens is approximated by tipping the outer rows back in 3D; true glyph-bending
        // distortion needs a Metal shader, upgrade once Xcode's Metal compiler is installed.
        .rotation3DEffect(.degrees(isFisheye && count == 3 ? Double(1 - slot) * Metrics.fisheyeTiltDegrees : 0),
                          axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }

    @ViewBuilder
    private func wordText(_ word: TimedWord, size: CGFloat, isNewest: Bool, pill: Bool) -> some View {
        let settings = context.settings
        let text = Text(word.text).font(context.font(size))
        switch kind {
        case .ship:
            if pill {
                text.foregroundStyle(contrastColor(on: settings.highlightColor))
                    .padding(.horizontal, size * 0.14).padding(.vertical, size * 0.02)
                    .background(Color(nsColor: settings.highlightColor))
            } else {
                text.foregroundStyle(Color(nsColor: settings.textColor)).opacity(isNewest ? 1 : 0.7)
            }
        case .visual, .fisheye:
            if isNewest {
                // A solid box hugging the glyph ink (not the line box), with contrasting text on top.
                let ink = inkRect(word.text, size: size)
                ZStack(alignment: .topLeading) {
                    Color(nsColor: settings.highlightColor)
                        .frame(width: ink.width, height: ink.height)
                        .offset(x: ink.minX, y: ink.minY)
                    text.foregroundStyle(contrastColor(on: settings.highlightColor))
                }
            } else {
                text.foregroundStyle(Color(nsColor: settings.secondaryColor))
            }
        }
    }

    private func backdrop(_ visual: WordVisual) -> some View {
        let size = context.band * Metrics.backdropScale
        return Group {
            switch visual {
            case .emoji(let character): Text(character)
            case .symbol(let name): Image(systemName: name).foregroundStyle(Color(nsColor: context.settings.textColor))
            }
        }
        .font(.system(size: size))
        .opacity(Metrics.backdropOpacity)
    }

    private struct Placement: ViewModifier {
        let kind: Kind
        let nudge: Double
        let strength: CGFloat
        let width: CGFloat

        func body(content: Content) -> some View {
            if case .ship = kind {
                // Ship is left-aligned with a ragged indent, like lines of a logbook.
                content.padding(.leading, width * strength * nudge)
            } else {
                content.offset(x: width * strength * (2 * nudge - 1))
            }
        }
    }

    // MARK: Sizing

    private var fisheyeBase: CGFloat { context.canvas.height * Metrics.fisheyeCapHeight * context.settings.textScale }

    /// Point size per word. Longer-held words are drawn bigger; nothing may exceed its width or the band.
    private func fontSizes(for words: [TimedWord]) -> [CGFloat] {
        guard !words.isEmpty else { return [] }
        let settings = context.settings
        let reference = settings.font.font(size: 100)
        let capRatio = max(1, reference.capHeight) / 100
        func widthAt100(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: reference]).width }
        func fitted(_ text: String, capHeight: CGFloat, maxWidth: CGFloat) -> CGFloat {
            let width = widthAt100(text)
            return width > 0 ? min(capHeight / capRatio, maxWidth * 100 / width) : capHeight / capRatio
        }
        if isFisheye {
            let slots = min(words.count, 3)
            return words.indices.map { index in
                fitted(words[index].text, capHeight: fisheyeBase * Metrics.fisheyeHeights[slots][index],
                       maxWidth: context.canvas.width * Metrics.fisheyeMaxWidth * settings.textScale * Metrics.fisheyeWidths[slots][index])
            }
        }
        // Emphasis is relative to the whole line, so a word keeps its size while it scrolls up the stack.
        let durations = context.line.words.map { max(0.01, $0.end - $0.start) }
        let mean = durations.reduce(0, +) / Double(durations.count)
        let sizes = words.map { word -> CGFloat in
            let emphasis = min(max(sqrt(max(0.01, word.end - word.start) / mean), Metrics.emphasisRange.lowerBound), Metrics.emphasisRange.upperBound)
            return fitted(word.text, capHeight: context.canvas.height * Metrics.capHeight * emphasis * settings.textScale,
                          maxWidth: context.canvas.width * Metrics.maxWordWidth)
        }
        let stackHeight = sizes.reduce(0) { $0 + $1 * capRatio }
        let limit = context.band * Metrics.maxStackHeight
        return stackHeight > limit ? sizes.map { $0 * limit / stackHeight } : sizes
    }

    /// Where the visible ink of `text` sits inside its Text view, measured from the view's top-left corner.
    private func inkRect(_ text: String, size: CGFloat) -> CGRect {
        let font = context.settings.font.font(size: size)
        let ink = (text as NSString).boundingRect(with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                                  options: [.usesFontLeading, .usesDeviceMetrics], attributes: [.font: font])
        // boundingRect is baseline-relative with y up; a Text view's top edge is one ascender above the baseline.
        return CGRect(x: ink.minX, y: font.ascender - ink.maxY, width: ink.width, height: ink.height)
    }
}
