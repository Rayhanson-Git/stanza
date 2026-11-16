import AppKit

/// "Drag Position": a small card stands in for the lyrics on the menu-bar display and is dragged to where they should sit.
/// While it is dragged the lyrics' windows simply slide along with it, which costs nothing, so they stay glued to the
/// card; redrawing the style for every step of the mouse could not keep up and made them stutter behind. The position
/// is saved once, as a fraction of the screen, when the card is let go, so the lyrics follow on every display and on
/// the lock screen. The full-screen lyrics layer stays click-through throughout, so the rest of the screen keeps working.
final class LyricPlacement {
    private static let cardSize = NSSize(width: 372, height: 50)

    private let settings: AppSettings
    /// Moves the card into the lyrics' layer; a window level alone cannot get it in front of them.
    private let raiseAboveLyrics: (NSWindow) -> Void
    /// Slides the lyrics' windows by a share of the screen while dragging; nil puts them back in place.
    private let slideLyrics: (CGPoint?) -> Void
    private var panel: NSPanel?
    /// Set while the card is held: where the drag began, and the position it has reached so far.
    private var drag: (screen: NSScreen, mouse: NSPoint, origin: NSPoint, offset: CGPoint, reached: CGPoint)?
    var isActive: Bool { panel != nil }

    init(settings: AppSettings, raiseAboveLyrics: @escaping (NSWindow) -> Void, slideLyrics: @escaping (CGPoint?) -> Void) {
        self.settings = settings
        self.raiseAboveLyrics = raiseAboveLyrics
        self.slideLyrics = slideLyrics
    }

    func begin() {
        // The display with the menu bar, where the menu that started this was clicked.
        guard panel == nil, let screen = NSScreen.screens.first else { return }
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.cardSize), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // One above the lyrics within their layer, so even large lyrics never cover it. That is also above menus,
        // which is fine for a small card that goes away on Done (and on screen lock).
        panel.level = NSWindow.Level(rawValue: OverlayController.level.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = PlacementCard(frame: NSRect(origin: .zero, size: Self.cardSize), scale: settings.textScale,
                                          onScale: { [weak self] in self?.settings.textScale = $0 },
                                          drag: (began: { [weak self] in self?.dragBegan() }, moved: { [weak self] in self?.dragMoved() },
                                                 ended: { [weak self] in self?.dragEnded() }),
                                          done: { [weak self] in self?.end() }, reset: { [weak self] in self?.reset() })
        self.panel = panel
        place(panel, at: settings.lyricOffset, on: screen)
        panel.orderFrontRegardless()
        raiseAboveLyrics(panel)
        log("drag position: on")
    }

    /// Ends moving; the position is already saved.
    func end() {
        guard let panel else { return }
        if drag != nil { dragEnded() }
        panel.orderOut(nil)
        self.panel = nil
        log("drag position: off at \(settings.lyricOffset)")
    }

    /// Back to the middle, with or without the card showing.
    func reset() {
        settings.lyricOffset = .zero
        if let panel, let screen = panel.screen ?? NSScreen.screens.first { place(panel, at: .zero, on: screen) }
    }

    /// Centres the card where the lyrics' centre is on `screen` for a given position.
    private func place(_ panel: NSPanel, at offset: CGPoint, on screen: NSScreen) {
        let frame = screen.frame
        let centre = NSPoint(x: frame.minX + frame.width * (Layout.defaultCentre.x + offset.x),
                             y: frame.maxY - frame.height * (Layout.defaultCentre.y + offset.y))
        panel.setFrameOrigin(NSPoint(x: centre.x - Self.cardSize.width / 2, y: centre.y - Self.cardSize.height / 2))
    }

    private func dragBegan() {
        guard let panel, let screen = panel.screen ?? NSScreen.screens.first else { return }
        drag = (screen, NSEvent.mouseLocation, panel.frame.origin, settings.lyricOffset, settings.lyricOffset)
    }

    /// The card follows the mouse, kept to where the lyrics may go, and the lyrics slide by the same amount.
    private func dragMoved() {
        guard let panel, var drag else { return }
        let mouse = NSEvent.mouseLocation, frame = drag.screen.frame
        let origin = NSPoint(x: drag.origin.x + mouse.x - drag.mouse.x, y: drag.origin.y + mouse.y - drag.mouse.y)
        let wanted = CGPoint(x: (origin.x + Self.cardSize.width / 2 - frame.minX) / frame.width - Layout.defaultCentre.x,
                             y: (frame.maxY - origin.y - Self.cardSize.height / 2) / frame.height - Layout.defaultCentre.y)
        let reached = Layout.clampedOffset(wanted)
        place(panel, at: reached, on: drag.screen)
        // The Map filling the whole display never moves, so its windows must not slide either.
        if !(settings.style == .map && settings.mapFillsDisplay) {
            slideLyrics(CGPoint(x: reached.x - drag.offset.x, y: reached.y - drag.offset.y))
        }
        drag.reached = reached
        self.drag = drag
    }

    /// Saves the position and puts the windows back in the same step, the lyrics already drawn there.
    private func dragEnded() {
        guard let drag else { return }
        self.drag = nil
        if drag.reached != settings.lyricOffset { settings.lyricOffset = drag.reached }
        slideLyrics(nil)
    }
}

/// The card: one slim Liquid Glass pill, so it covers as little as possible. From left to right: the move symbol, the
/// size slider with its percentage, a reset icon and a round Done button. Everything but the controls drags it, and
/// the controls act on the first click, even while Stanza is not the active app.
private final class PlacementCard: NSView {
    typealias Drag = (began: () -> Void, moved: () -> Void, ended: () -> Void)

    private enum Metrics {
        static let height: CGFloat = 50
        static let sliderWidth: CGFloat = 170
        static let doneSize: CGFloat = 32
    }

    private let done: () -> Void
    private let reset: () -> Void
    private let drag: Drag
    private let percent = NSTextField(labelWithString: "")

    init(frame: NSRect, scale: Double, onScale: @escaping (Double) -> Void, drag: Drag,
         done: @escaping () -> Void, reset: @escaping () -> Void) {
        self.drag = drag
        self.done = done
        self.reset = reset
        super.init(frame: frame)

        let move = NSImageView(image: Self.symbol("arrow.up.and.down.and.arrow.left.and.right", "Drag to move the lyrics"))
        move.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        move.contentTintColor = NSColor(white: 1, alpha: 0.9)
        move.toolTip = "Drag to move the lyrics"
        let slider = SizeSlider(frame: NSRect(x: 0, y: 0, width: Metrics.sliderWidth, height: 22), value: scale,
                                range: AppSettings.textScaleRange) { [weak self] value in
            self?.showPercent(value)
            onScale(value)
        }
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: Metrics.sliderWidth).isActive = true
        percent.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        percent.textColor = NSColor(white: 1, alpha: 0.8)
        percent.alignment = .right
        percent.translatesAutoresizingMaskIntoConstraints = false
        percent.widthAnchor.constraint(equalToConstant: 38).isActive = true
        showPercent(scale)

        let resetButton = Self.iconButton("arrow.counterclockwise", label: "Reset Position", target: self, action: #selector(resetClicked))
        resetButton.contentTintColor = NSColor(white: 1, alpha: 0.85)
        let doneButton = Self.iconButton("checkmark", label: "Done", target: self, action: #selector(doneClicked))
        doneButton.contentTintColor = .white
        doneButton.wantsLayer = true
        doneButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        doneButton.layer?.cornerRadius = Metrics.doneSize / 2
        NSLayoutConstraint.activate([doneButton.widthAnchor.constraint(equalToConstant: Metrics.doneSize),
                                     doneButton.heightAnchor.constraint(equalToConstant: Metrics.doneSize)])

        let row = NSStackView(views: [move, slider, percent, Self.divider(), resetButton, doneButton])
        row.spacing = 12
        row.setCustomSpacing(8, after: resetButton)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 9)
        let pill = Self.glass(row, cornerRadius: Metrics.height / 2)
        pill.frame = bounds
        pill.autoresizingMask = [.width, .height]
        addSubview(pill)
        setAccessibilityLabel("Lyrics position and size. Drag to move.")
    }

    required init?(coder: NSCoder) { nil }

    private func showPercent(_ value: Double) { percent.stringValue = "\(Int((value * 100).rounded()))%" }

    private static func symbol(_ name: String, _ label: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: label) ?? NSImage()
    }

    private static func iconButton(_ symbol: String, label: String, target: AnyObject, action: Selector) -> NSButton {
        let button = FirstClickButton(image: Self.symbol(symbol, label), target: target, action: action)
        button.isBordered = false
        button.symbolConfiguration = .init(pointSize: 14, weight: .bold)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private static func divider() -> NSView {
        let line = NSBox()
        line.boxType = .custom
        line.fillColor = NSColor(white: 1, alpha: 0.18)
        line.borderWidth = 0
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: 1), line.heightAnchor.constraint(equalToConstant: 22)])
        return line
    }

    /// Liquid Glass where the system has it (macOS 26), a dark frosted pill before that.
    private static func glass(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.tintColor = NSColor(white: 0, alpha: 0.3)
            glass.contentView = content
            return glass
        }
        let frosted = NSVisualEffectView()
        frosted.material = .hudWindow
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.wantsLayer = true
        frosted.layer?.cornerRadius = cornerRadius
        frosted.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        frosted.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: frosted.leadingAnchor),
                                     content.trailingAnchor.constraint(equalTo: frosted.trailingAnchor),
                                     content.centerYAnchor.constraint(equalTo: frosted.centerYAnchor)])
        return frosted
    }

    /// Everything but the buttons and the slider drags the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton || hit is SizeSlider ? hit : (hit == nil ? nil : self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { drag.began() }
    override func mouseDragged(with event: NSEvent) { drag.moved() }
    override func mouseUp(with event: NSEvent) { drag.ended() }

    @objc private func doneClicked() { done() }
    @objc private func resetClicked() { reset() }
}

private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
