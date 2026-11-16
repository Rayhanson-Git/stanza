import AppKit
import IOKit.pwr_mgt

/// Reports screen lock / unlock. Notifications are the fast path; the poll catches any that are missed.
final class LockMonitor {
    private static let pollSeconds = 1.0
    private(set) var isLocked = LockMonitor.currentlyLocked()
    private let onChange: (Bool) -> Void
    private var timer: Timer?

    static func currentlyLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            center.addObserver(self, selector: #selector(refresh), name: Notification.Name(name), object: nil)
        }
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func refresh() {
        let locked = Self.currentlyLocked()
        guard locked != isLocked else { return }
        isLocked = locked
        log(locked ? "screen locked" : "screen unlocked")
        onChange(locked)
    }
}

/// Keeps the display from sleeping while music plays, so lyrics stay visible on the lock screen.
final class ScreenAwake {
    private var assertionID = IOPMAssertionID(0)
    private var held = false

    func update(playing: Bool, enabled: Bool) {
        let wanted = playing && enabled
        guard wanted != held else { return }
        if wanted {
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "Stanza is showing lyrics for playing music" as CFString, &assertionID)
            held = result == kIOReturnSuccess
            log(held ? "screen awake: assertion held" : "screen awake: assertion FAILED (\(result))")
        } else {
            IOPMAssertionRelease(assertionID)
            held = false
            log("screen awake: assertion released")
        }
    }
}
