import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Tag {
        static let stylesHeader = 699
        static let style = 700
        static let displayHeader = 701
        static let display = 702
    }

    private let settings = AppSettings.shared
    private let monitor = NowPlayingMonitor()
    private let screenAwake = ScreenAwake()
    private let presence = OverlayPresence()
    private let playerLink = PlayerLink()
    private let updater = AppUpdater()
    // Created in buildMenu, after the single-instance check, so a second launch never flashes an icon.
    private var statusItem: NSStatusItem?
    private lazy var engine = LyricEngine(monitor: monitor, settings: settings)
    private lazy var colorSync = ArtworkColorSync(monitor: monitor, settings: settings)
    private lazy var overlays = OverlayController(settings: settings) { [engine, monitor, settings, colorSync, presence] display in
        AnyView(LyricOverlayView(engine: engine, monitor: monitor, settings: settings, artwork: colorSync,
                                 presence: presence, display: display))
    }
    private lazy var gallery = GalleryWindowController { [settings, engine, monitor, playerLink, updater] in
        GalleryModel(settings: settings, engine: engine, monitor: monitor, playerLink: playerLink, updater: updater)
    }
    private var lockMonitor: LockMonitor?
    private lazy var placement = LyricPlacement(settings: settings)
    /// Puts the lyrics away once nothing has played for `idleDelay` seconds.
    private var idleTimer: DispatchWorkItem?
    private static let idleDelay = 10.0
    private var observers: Set<AnyCancellable> = []
    private weak var textScaleSlider: SizeSlider?

    private var isLocked: Bool { lockMonitor?.isLocked ?? LockMonitor.currentlyLocked() }

    /// When a copy started, and as which process.
    typealias Launch = (date: Date?, pid: pid_t)

    /// Whether this copy gives way to `other`. The earlier launch stays; when the times tie or are not
    /// known the lower process number does, so two copies started together never both exit.
    static func yields(_ mine: Launch, to other: Launch) -> Bool {
        if let mineDate = mine.date, let otherDate = other.date, mineDate != otherDate { return otherDate < mineDate }
        return other.pid < mine.pid
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let current = NSRunningApplication.current
        let mine: Launch = (current.launchDate, current.processIdentifier)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != current }
        guard !others.contains(where: { Self.yields(mine, to: ($0.launchDate, $0.processIdentifier)) }) else {
            log("another Stanza instance is running — exiting this one")
            return NSApp.terminate(nil)
        }
        buildMenu()
        buildMainMenu()
        updater.start()
        lockMonitor = LockMonitor { [weak self] locked in
            if locked { self?.placement.end() }
            self?.gallery.locked = locked
            self?.applyPresence()
            self?.refreshScreenAwake()
        }
        overlays.rebuild(locked: isLocked)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .merge(with: settings.$disabledDisplays.dropFirst().map { _ in Notification(name: .init("displays")) })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                placement.end()
                overlays.rebuild(locked: isLocked)
            }
            .store(in: &observers)
        settings.$showWhenUnlocked.dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self.map { $0.overlays.applyVisibility(locked: $0.isLocked) } }
            .store(in: &observers)
        monitor.$isPlaying.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] playing in self?.playingChanged(playing) }
            .store(in: &observers)
        monitor.$isPlaying.combineLatest(settings.$keepScreenAwake, settings.$showWhenUnlocked).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshScreenAwake() }
            .store(in: &observers)

        _ = colorSync
        monitor.start()

        gallery.onPresenceChange = { [weak self] in self?.applyPresence() }
        gallery.locked = isLocked
        gallery.show()
    }

    /// Clicking the Dock icon brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        gallery.show()
        return false
    }

    /// The overlay steps aside on the display where the Stanza window is in use, so lyrics never play
    /// over their own previews. Never on the lock screen, where the window cannot be seen anyway.
    private func applyPresence() {
        let locked = isLocked
        let yielding = locked ? nil : gallery.display
        let displays = Set([yielding].compactMap { $0 })
        if presence.yielding != displays { presence.yielding = displays }
        overlays.yieldingDisplay = yielding
        overlays.applyVisibility(locked: locked)
    }

    /// Music stopped: put the lyrics away after a while instead of leaving the paused line on screen. Playing
    /// again brings them back at once.
    private func playingChanged(_ playing: Bool) {
        idleTimer?.cancel()
        guard !playing else {
            if presence.idle { presence.idle = false }
            return
        }
        let timer = DispatchWorkItem { [weak self] in self?.presence.idle = true }
        idleTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: timer)
    }

    /// The display is only kept awake while lyrics can actually be seen.
    private func refreshScreenAwake() {
        let lyricsVisible = isLocked || settings.showWhenUnlocked
        screenAwake.update(playing: monitor.isPlaying && lyricsVisible, enabled: settings.keepScreenAwake)
    }

    // MARK: Menu

    /// The logo's one-colour mark, tinted by macOS to suit a light or dark menu bar; a stock symbol if the file is missing.
    private static let menuBarImage: NSImage? = {
        guard let mark = NSImage(named: "StanzaMenuBar") else {
            log("menu bar: logo mark not found in the app bundle, using a stock symbol")
            return NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "Stanza")
        }
        mark.isTemplate = true
        mark.accessibilityDescription = "Stanza"
        return mark
    }()

    private func buildMenu() {
        // Variable length: the logo mark is wider than it is tall and would be squeezed into a square slot.
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        statusItem.button?.image = Self.menuBarImage
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        menu.addItem(item("Open Stanza", #selector(showGallery)))
        menu.addItem(.separator())
        // Styles and displays are filled in each time the menu opens (menuNeedsUpdate).
        let stylesHeader = header("Styles")
        stylesHeader.tag = Tag.stylesHeader
        menu.addItem(stylesHeader)
        menu.addItem(.separator())
        menu.addItem(item("Keep Screen Awake", #selector(toggleKeepAwake)))
        menu.addItem(item("Show When Unlocked", #selector(toggleShowWhenUnlocked)))
        menu.addItem(.separator())

        // Where the lyrics sit and how big the whole style is, together in one place.
        menu.addItem(header("Position and Size"))
        menu.addItem(item("Drag Position", #selector(toggleMoveLyrics)))
        menu.addItem(item("Reset Position", #selector(resetLyricsPosition)))
        let textScale = sliderItem(settings.textScale, AppSettings.textScaleRange, #selector(resetTextScale))
        textScaleSlider = textScale.slider
        menu.addItem(textScale.item)
        menu.addItem(.separator())

        let displayHeader = header("Displays")
        displayHeader.tag = Tag.displayHeader
        menu.addItem(displayHeader)
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(runUpdater)))
        menu.addItem(NSMenuItem(title: "Quit Stanza", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    /// While its window is open Stanza is a regular app, and ⌘Q, ⌘H, ⌘W and ⌘M only work through a main menu.
    private func buildMainMenu() {
        let appMenu = NSMenu()
        // Retitled in menuNeedsUpdate, like the status menu, so it says "Restart to Update" when that is what it does.
        appMenu.delegate = self
        appMenu.autoenablesItems = false
        appMenu.addItem(item("Check for Updates…", #selector(runUpdater)))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Stanza", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Stanza", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let mainMenu = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let holder = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            holder.submenu = submenu
            mainMenu.addItem(holder)
        }
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        textScaleSlider?.value = settings.textScale
        menu.items.filter { $0.tag == Tag.style || $0.tag == Tag.display }.forEach(menu.removeItem)
        if let headerIndex = menu.items.firstIndex(where: { $0.tag == Tag.stylesHeader }) {
            for (offset, styleItem) in styleItems().enumerated() { menu.insertItem(styleItem, at: headerIndex + 1 + offset) }
        }
        if let headerIndex = menu.items.firstIndex(where: { $0.tag == Tag.displayHeader }) {
            for (offset, screen) in NSScreen.screens.enumerated() {
                guard let id = OverlayController.displayID(of: screen) else { continue }
                let displayItem = item(screen.localizedName, #selector(toggleDisplay(_:)), represented: NSNumber(value: id))
                displayItem.tag = Tag.display
                displayItem.state = settings.disabledDisplays.contains(id) ? .off : .on
                menu.insertItem(displayItem, at: headerIndex + 1 + offset)
            }
        }
        for menuItem in menu.items {
            switch menuItem.action {
            case #selector(toggleKeepAwake): menuItem.state = settings.keepScreenAwake ? .on : .off
            case #selector(toggleShowWhenUnlocked): menuItem.state = settings.showWhenUnlocked ? .on : .off
            case #selector(toggleMoveLyrics): menuItem.state = placement.isActive ? .on : .off
            case #selector(resetLyricsPosition): menuItem.isEnabled = settings.lyricOffset != .zero
            case #selector(runUpdater):
                menuItem.title = updater.actionTitle
                menuItem.isEnabled = updater.canAct
            default: break
            }
        }
    }

    /// Every style, grouped as in the window, the one in use ticked; pinned styles also lead in their own group.
    private func styleItems() -> [NSMenuItem] {
        let items = AppSettings.menuGroups(pinned: settings.pinnedStyles).flatMap { group -> [NSMenuItem] in
            let styles = group.styles.map { style -> NSMenuItem in
                let styleItem = item(style.rawValue, #selector(pickStyle(_:)), represented: style.rawValue)
                styleItem.state = style == settings.style ? .on : .off
                styleItem.indentationLevel = 1
                return styleItem
            }
            return [header(group.title)] + styles
        }
        items.forEach { $0.tag = Tag.style }
        return items
    }

    private func header(_ title: String) -> NSMenuItem {
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        return header
    }

    private func item(_ title: String, _ action: Selector, represented: Any? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = represented
        return menuItem
    }

    private func sliderItem(_ value: Double, _ range: ClosedRange<Double>, _ reset: Selector) -> (item: NSMenuItem, slider: SizeSlider) {
        let slider = SizeSlider(frame: NSRect(x: 14, y: 4, width: 140, height: 22), value: value, range: range) { [weak self] scale in
            self?.settings.textScale = scale
        }
        let resetButton = NSButton(title: "Reset Size", target: self, action: reset)
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        resetButton.frame = NSRect(x: 160, y: 3, width: 80, height: 24)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 30))
        container.addSubview(slider)
        container.addSubview(resetButton)
        let menuItem = NSMenuItem()
        menuItem.view = container
        return (menuItem, slider)
    }

    // MARK: Actions

    @objc private func pickStyle(_ sender: NSMenuItem) {
        (sender.representedObject as? String).flatMap(LyricStyle.init(rawValue:)).map { settings.style = $0 }
    }

    @objc private func showGallery() { gallery.show() }
    @objc private func runUpdater() { updater.act() }
    @objc private func toggleMoveLyrics() { placement.isActive ? placement.end() : placement.begin() }
    @objc private func resetLyricsPosition() { placement.reset() }
    @objc private func toggleKeepAwake() { settings.keepScreenAwake.toggle() }
    @objc private func toggleShowWhenUnlocked() { settings.showWhenUnlocked.toggle() }

    @objc private func resetTextScale() {
        settings.textScale = 1
        textScaleSlider?.value = 1
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        (sender.representedObject as? NSNumber).map { settings.toggleDisplay($0.uint32Value) }
    }
}
