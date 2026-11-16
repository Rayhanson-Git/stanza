import AppKit

/// "Drag Position": a small card stands in for the lyrics on the menu-bar display and is dragged to where they should sit.
/// Each move is saved at once, as a fraction of the screen, so the lyrics follow on every display and on the lock
/// screen. The full-screen lyrics layer stays click-through throughout, so the rest of the screen keeps working.
final class LyricPlacement: NSObject, NSWindowDelegate {
    private static let cardSize = NSSize(width: 340, height: 150)

    private let settings: AppSettings
    /// Moves the card into the lyrics' layer; a window level alone cannot get it in front of them.
    private let raiseAboveLyrics: (NSWindow) -> Void
    private var panel: NSPanel?
    /// True while the card is being moved by code, so that move is not read back as a drag (rounding would leave a
    /// tiny offset behind, and Reset would never quite reach the middle).
    private var placingByCode = false
    var isActive: Bool { panel != nil }

    init(settings: AppSettings, raiseAboveLyrics: @escaping (NSWindow) -> Void) {
        self.settings = settings
        self.raiseAboveLyrics = raiseAboveLyrics
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
                                          done: { [weak self] in self?.end() }, reset: { [weak self] in self?.reset() })
        self.panel = panel
        place(panel, on: screen)
        panel.delegate = self
        panel.orderFrontRegardless()
        raiseAboveLyrics(panel)
        log("drag position: on")
    }

    /// Ends moving; the position is already saved.
    func end() {
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        self.panel = nil
        log("drag position: off at \(settings.lyricOffset)")
    }

    /// Back to the middle, with or without the card showing.
    func reset() {
        settings.lyricOffset = .zero
        if let panel, let screen = panel.screen ?? NSScreen.screens.first { place(panel, on: screen) }
    }

    /// Centres the card where the lyrics' centre is on `screen`.
    private func place(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.frame
        let centre = NSPoint(x: frame.minX + frame.width * (Layout.defaultCentre.x + settings.lyricOffset.x),
                             y: frame.maxY - frame.height * (Layout.defaultCentre.y + settings.lyricOffset.y))
        placingByCode = true
        panel.setFrameOrigin(NSPoint(x: centre.x - Self.cardSize.width / 2, y: centre.y - Self.cardSize.height / 2))
        placingByCode = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !placingByCode, let panel, let screen = panel.screen ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let offset = CGPoint(x: (panel.frame.midX - frame.minX) / frame.width - Layout.defaultCentre.x,
                             y: (frame.maxY - panel.frame.midY) / frame.height - Layout.defaultCentre.y)
        let clamped = Layout.clampedOffset(offset)
        if clamped != settings.lyricOffset { settings.lyricOffset = clamped }
    }
}

/// The card: drag it anywhere by its body; the size slider, Done and Reset Position act on the first click, even while
/// Stanza is not the active app.
private final class PlacementCard: NSView {
    private let done: () -> Void
    private let reset: () -> Void

    init(frame: NSRect, scale: Double, onScale: @escaping (Double) -> Void, done: @escaping () -> Void, reset: @escaping () -> Void) {
        self.done = done
        self.reset = reset
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.85).cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor(white: 1, alpha: 0.45).cgColor

        let title = Self.label("Drag to place the lyrics", size: 15, weight: .semibold, alpha: 1)
        let hint = Self.label("They sit where the middle of this card is.", size: 12, weight: .regular, alpha: 0.6)
        let buttons = NSStackView(views: [FirstClickButton(title: "Reset Position", target: self, action: #selector(resetClicked)),
                                          FirstClickButton(title: "Done", target: self, action: #selector(doneClicked))])
        buttons.spacing = 8
        let slider = SizeSlider(frame: NSRect(x: 0, y: 0, width: 200, height: 22), value: scale, range: AppSettings.textScaleRange,
                                onChange: onScale)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let sizeRow = NSStackView(views: [Self.label("Size", size: 12, weight: .medium, alpha: 0.85), slider])
        sizeRow.spacing = 10
        let stack = NSStackView(views: [title, hint, sizeRow, buttons])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(12, after: hint)
        stack.setCustomSpacing(12, after: sizeRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                                     stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        setAccessibilityLabel("Lyrics position. Drag to move.")
    }

    required init?(coder: NSCoder) { nil }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor(white: 1, alpha: alpha)
        return label
    }

    /// Everything but the buttons and the slider drags the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton || hit is SizeSlider ? hit : (hit == nil ? nil : self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }

    @objc private func doneClicked() { done() }
    @objc private func resetClicked() { reset() }
}

private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
