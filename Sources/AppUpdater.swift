import AppKit
import Combine
import Sparkle

/// Keeps Stanza up to date with Sparkle. Checks once a day; by default an update downloads quietly and
/// installs when Stanza quits, and the menu and window offer to restart into it straight away.
/// Updates are only accepted when they carry the signature made with the developer's private key.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// An update the user has not looked at yet, or one that is downloaded and waits for a restart.
    enum Pending: Equatable {
        case available(version: String)
        case ready(version: String)
    }

    @Published private(set) var pending: Pending?
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?

    private var controller: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    private var observers: Set<AnyCancellable> = []

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Starts checking. Called once, from a normal launch only, so the command-line tools never go online.
    func start() {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }.store(in: &observers)
        controller.updater.publisher(for: \.lastUpdateCheckDate).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastCheck = $0 }.store(in: &observers)
    }

    var installsAutomatically: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// What the update button says, in the menus and the window alike.
    var actionTitle: String {
        switch pending {
        case .ready(let version): return "Restart to Update to \(version)"
        case .available(let version): return "Update to Stanza \(version)…"
        case nil: return "Check for Updates…"
        }
    }

    var canAct: Bool { pending != nil || canCheck }

    /// The one action behind every update button: restart into a downloaded update, otherwise look now.
    func act() {
        if case .ready = pending, let installNow {
            installNow()
        } else {
            controller?.checkForUpdates(nil)
        }
    }

    // MARK: SPUUpdaterDelegate

    /// A quietly downloaded update: keep it for quit time, and let the menu and window offer a restart.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        pending = .ready(version: item.displayVersionString)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        log("update check stopped: \(error.localizedDescription)")
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Stanza mostly lives in the menu bar, so a background check never throws a window in front of other
    /// work; it waits in the menu and the Stanza window instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { pending = .available(version: update.displayVersionString) }
    }

    /// The reminder stays until the update session ends (installed, skipped or put off), not merely because
    /// Stanza came to the front.
    func standardUserDriverWillFinishUpdateSession() {
        if case .available = pending { pending = nil }
    }
}
