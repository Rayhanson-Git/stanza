import AppKit
import SwiftUI

/// The private window-server space that sits above the lock screen. Undocumented API: every call is
/// looked up at runtime, and the overlay simply stays below the lock screen if a symbol is missing.
final class LockScreenSpace {
    // kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock
    private static let lockScreenLevel: Int32 = 400
    private static let moveWindowFlags: Int32 = 7

    // The functions are undocumented, so there is no header to check these signatures against.
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let showSpaces: ShowSpaces
    private let addWindows: AddWindows

    init?() {
        guard let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let mainConnection = dlsym(skyLight, "SLSMainConnectionID"),
              let spaceCreate = dlsym(skyLight, "SLSSpaceCreate"),
              let spaceSetLevel = dlsym(skyLight, "SLSSpaceSetAbsoluteLevel"),
              let showSpaces = dlsym(skyLight, "SLSShowSpaces"),
              let addWindows = dlsym(skyLight, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return nil }
        connection = unsafeBitCast(mainConnection, to: MainConnection.self)()
        space = unsafeBitCast(spaceCreate, to: SpaceCreate.self)(connection, 1, 0)
        guard space != 0 else { return nil }
        _ = unsafeBitCast(spaceSetLevel, to: SpaceSetLevel.self)(connection, space, Self.lockScreenLevel)
        self.showSpaces = unsafeBitCast(showSpaces, to: ShowSpaces.self)
        self.addWindows = unsafeBitCast(addWindows, to: AddWindows.self)
    }

    func adopt(_ window: NSWindow) {
        _ = showSpaces(connection, [space] as CFArray)
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, Self.moveWindowFlags)
    }
}

/// One transparent, click-through, full-screen lyrics window per enabled display.
final class OverlayController {
    /// Just under the very top, so lyrics show over other apps and, through `LockScreenSpace`, the lock screen.
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 2)

    private let settings: AppSettings
    private let makeContent: (UInt32) -> AnyView
    private let lockScreenSpace = LockScreenSpace()
    private var windows: [UInt32: NSWindow] = [:]
    /// The display whose overlay steps aside while the Stanza window is in use on it.
    var yieldingDisplay: UInt32?

    init(settings: AppSettings, makeContent: @escaping (UInt32) -> AnyView) {
        self.settings = settings
        self.makeContent = makeContent
        if lockScreenSpace == nil { log("lock screen: private window-server calls unavailable, overlay will only show when unlocked") }
    }

    static func displayID(of screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Creates, removes and re-frames windows to match the connected, enabled displays.
    func rebuild(locked: Bool) {
        let wanted = NSScreen.screens.reduce(into: [UInt32: NSScreen]()) { wanted, screen in
            if let id = Self.displayID(of: screen), !settings.disabledDisplays.contains(id) { wanted[id] = screen }
        }
        for (id, window) in windows where wanted[id] == nil {
            window.orderOut(nil)
            windows[id] = nil
        }
        for (id, screen) in wanted {
            if let window = windows[id] {
                window.setFrame(screen.frame, display: true)
            } else {
                windows[id] = makeWindow(on: screen, id: id)
                log("overlay created for display \(id) (\(screen.localizedName))")
            }
        }
        applyVisibility(locked: locked)
    }

    /// Puts `window` in the lyrics' own window-server layer, the one above the lock screen. Nothing outside that layer
    /// can sit in front of the lyrics, whatever its window level, so the Drag Position card joins it.
    func raiseAboveLyrics(_ window: NSWindow) {
        lockScreenSpace?.adopt(window)
        window.orderFrontRegardless()
    }

    func applyVisibility(locked: Bool) {
        for (id, window) in windows {
            guard locked || settings.showWhenUnlocked, id != yieldingDisplay else {
                window.orderOut(nil)
                continue
            }
            lockScreenSpace?.adopt(window)
            window.orderFrontRegardless()
        }
    }

    private func makeWindow(on screen: NSScreen, id: UInt32) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.canBecomeVisibleWithoutLogin = true
        window.level = Self.level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: makeContent(id))
        window.setFrame(screen.frame, display: true)
        return window
    }
}
