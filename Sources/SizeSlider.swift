import AppKit

/// The size slider of the menu bar menu and the Move Lyrics card, drawn by hand. A standard slider in a menu or a
/// panel of an app that is not active is drawn greyed out and can swallow the first click, so it seemed to work only
/// sometimes; this one always looks live and takes the first click.
final class SizeSlider: NSView {
    /// While dragging, changes are passed on at most this far apart (each one redraws every visible style); the exact
    /// value always follows on release.
    private static let step = 0.05
    private static let knob: CGFloat = 16
    private static let track: CGFloat = 4

    let range: ClosedRange<Double>
    var value: Double { didSet { needsDisplay = true; setAccessibilityValue(value) } }
    var onChange: (Double) -> Void
    private var lastSent = Date.distantPast
    private var settle: DispatchWorkItem?

    init(frame: NSRect, value: Double, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) {
        self.range = range
        self.value = value
        self.onChange = onChange
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Size of the style")
        setAccessibilityValue(value)
        toolTip = "Scales the whole style: words, cards and pictures"
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.knob + 6) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var usable: ClosedRange<CGFloat> { (bounds.minX + Self.knob / 2)...(bounds.maxX - Self.knob / 2) }

    private var fraction: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let knobX = usable.lowerBound + fraction * (usable.upperBound - usable.lowerBound)
        let full = NSRect(x: usable.lowerBound, y: midY - Self.track / 2, width: usable.upperBound - usable.lowerBound, height: Self.track)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: full, xRadius: Self.track / 2, yRadius: Self.track / 2).fill()
        NSColor.controlAccentColor.setFill()
        let filled = NSRect(x: full.minX, y: full.minY, width: knobX - full.minX, height: Self.track)
        NSBezierPath(roundedRect: filled, xRadius: Self.track / 2, yRadius: Self.track / 2).fill()
        let knob = NSRect(x: knobX - Self.knob / 2, y: midY - Self.knob / 2, width: Self.knob, height: Self.knob)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSColor(white: 0, alpha: 0.25).setStroke()
        NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    /// The mouse wheel or a two-finger swipe moves it too; the exact value follows once the scrolling stops.
    override func scrollWheel(with event: NSEvent) {
        let change = ScrollAdjust.change(for: event, span: range.upperBound - range.lowerBound)
        guard change != 0 else { return }
        value = min(max(value + change, range.lowerBound), range.upperBound)
        settle?.cancel()
        let now = Date()
        if now.timeIntervalSince(lastSent) >= Self.step {
            lastSent = now
            onChange(value)
        }
        let finish = DispatchWorkItem { [weak self] in self.map { $0.onChange($0.value) } }
        settle = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.step * 2, execute: finish)
    }

    override func mouseDown(with event: NSEvent) { track(event, final: false) }
    override func mouseDragged(with event: NSEvent) { track(event, final: false) }
    override func mouseUp(with event: NSEvent) { track(event, final: true) }

    private func track(_ event: NSEvent, final: Bool) {
        let x = convert(event.locationInWindow, from: nil).x
        let share = Double((min(max(x, usable.lowerBound), usable.upperBound) - usable.lowerBound) / (usable.upperBound - usable.lowerBound))
        value = range.lowerBound + share * (range.upperBound - range.lowerBound)
        let now = Date()
        guard final || now.timeIntervalSince(lastSent) >= Self.step else { return }
        lastSent = now
        onChange(value)
    }
}
