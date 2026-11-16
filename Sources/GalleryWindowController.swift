import AppKit
import SwiftUI

/// Owns the Stanza window. The window is made once; its SwiftUI content and model are rebuilt each
/// time it is shown after a close, so a closed window costs nothing. Also reports where the window is,
/// so the lyrics overlay can step aside on that display.
final class GalleryWindowController: NSObject, NSWindowDelegate {
    private enum Metrics {
        static let size = NSSize(width: 1180, height: 740)
        static let minSize = NSSize(width: 940, height: 620)
        static let autosaveName = "StanzaGallery"
    }

    private let makeModel: () -> GalleryModel
    private var window: NSWindow?
    private var model: GalleryModel?
    private var lastDisplay: UInt32?
    /// Called when the display the window is being used on changes (including to or from "none").
    var onPresenceChange: () -> Void = {}
    /// Pushed in by the lock monitor: nothing in the window animates behind the lock screen.
    var locked = false { didSet { if locked != oldValue { refreshPresence() } } }

    init(makeModel: @escaping () -> GalleryModel) {
        self.makeModel = makeModel
        super.init()
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(appActivityChanged), name: name, object: nil)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The display the window is in use on: nil unless Stanza is the active app and the window can
    /// really be seen (an open window on another Space, or fully covered, is not in use).
    var display: UInt32? {
        guard let window, NSApp.isActive, Self.isInView(window) else { return nil }
        return window.screen.flatMap(OverlayController.displayID(of:))
    }

    private static func isInView(_ window: NSWindow) -> Bool {
        window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if model == nil { installContent(in: window) }
        // A menu-bar app has no Dock icon; the window gets one for as long as it is open.
        NSApp.setActivationPolicy(.regular)
        if window.isMiniaturized { window.deminiaturize(nil) }
        // The policy change has to settle before the app can come forward.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            self?.refreshPresence()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Metrics.size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Stanza"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.minSize = Metrics.minSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        // Restores the last position and size when there is one, and saves them from now on.
        window.setFrameAutosaveName(Metrics.autosaveName)
        return window
    }

    private func installContent(in window: NSWindow) {
        let model = makeModel()
        self.model = model
        let hosting = NSHostingView(rootView: GalleryView(model: model))
        // The content runs under the transparent title bar, and must not dictate the window's size limits.
        hosting.safeAreaRegions = []
        hosting.sizingOptions = []
        let container = NSView(frame: window.contentLayoutRect)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
    }

    // MARK: Presence

    /// Recomputes whether the window can be seen (pausing everything in it when not) and where it is.
    func refreshPresence() {
        let inView = window.map(Self.isInView) ?? false
        let suspended = !inView || locked || !NSApp.isActive
        if let model, model.suspended != suspended { model.suspended = suspended }
        let display = self.display
        guard display != lastDisplay else { return }
        lastDisplay = display
        onPresenceChange()
    }

    @objc private func appActivityChanged() { refreshPresence() }

    func windowDidChangeOcclusionState(_ notification: Notification) { refreshPresence() }
    func windowDidChangeScreen(_ notification: Notification) { refreshPresence() }
    func windowDidMiniaturize(_ notification: Notification) { refreshPresence() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPresence() }

    func windowWillClose(_ notification: Notification) {
        // Dropping the content and model stops every preview and frees the stills.
        model?.shutDown()
        model = nil
        window?.contentView = NSView()
        // The window still counts as visible inside this callback; look again once it has gone.
        DispatchQueue.main.async { [weak self] in
            // A show() that got in first has already made a new model and asked for the Dock icon; leave it.
            if self?.model == nil { NSApp.setActivationPolicy(.accessory) }
            self?.refreshPresence()
        }
    }
}
