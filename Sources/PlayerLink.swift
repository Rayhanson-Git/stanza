import AppKit
import Combine

enum Player: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
}

/// Whether macOS lets Stanza read a player (Automation permission).
enum PlayerAccess {
    case unknown, allowed, denied, notAsked
}

struct PlayerStatus: Equatable {
    let installed: Bool
    let running: Bool
    let access: PlayerAccess
}

/// What the player panel shows for one player: not known yet, then worst to best.
enum PlayerHealth {
    case checking, notInstalled, closed, notAsked, denied, unverified, idle, paused, playing

    var label: String {
        switch self {
        case .checking: return "Checking…"
        case .notInstalled: return "Not installed"
        case .closed: return "Not open"
        case .notAsked: return "Needs your permission"
        case .denied: return "Blocked in System Settings"
        case .unverified: return "Open"
        case .idle: return "Connected"
        case .paused: return "Synced, paused"
        case .playing: return "Synced"
        }
    }
}

/// Checks whether each player is installed, open and readable, and offers the fixes. Only polls while
/// something is showing the result (`isWatched`), since the answer does not matter otherwise.
final class PlayerLink: ObservableObject {
    private static let pollSeconds = 2.0
    private static let recheckAfterOpenSeconds = 1.0
    private static let waitForLaunchSeconds = 10.0
    /// A consent prompt left unanswered this long stops holding the buttons.
    private static let askTimeoutSeconds = 120.0
    private static let automationSettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    // Apple Event Manager result codes.
    private static let notPermitted: OSStatus = -1743
    private static let wouldRequireConsent: OSStatus = -1744

    @Published private(set) var status: [Player: PlayerStatus] = [:]
    /// The player macOS is currently asking the user about, if any.
    @Published private(set) var asking: Player?
    var isWatched = false { didSet { if isWatched != oldValue { reschedule() } } }

    private let queue = DispatchQueue(label: "stanza.playerlink", qos: .utility)
    private let askQueue = DispatchQueue(label: "stanza.playerlink.ask", qos: .userInitiated)
    private var timer: Timer?
    private var isChecking = false
    /// Numbers each ask, so one that ended (answered or timed out) cannot end the next one early.
    private var askNumber = 0

    func health(of player: Player, source: String?, isPlaying: Bool) -> PlayerHealth {
        // No status means the first check has not come back, which says nothing about the player.
        guard let status = status[player] else { return .checking }
        guard status.installed else { return .notInstalled }
        guard status.running else { return .closed }
        // Actually reading the player beats any permission answer.
        if source == player.rawValue { return isPlaying ? .playing : .paused }
        switch status.access {
        case .unknown: return .unverified
        case .allowed: return .idle
        case .denied: return .denied
        case .notAsked: return .notAsked
        }
    }

    // MARK: Checking

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard isWatched else { return }
        let timer = Timer(timeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func check() {
        guard isWatched, !isChecking else { return }
        isChecking = true
        let skipped = asking
        let previous = status
        queue.async { [weak self] in
            let fresh = Dictionary(uniqueKeysWithValues: Player.allCases.compactMap { player -> (Player, PlayerStatus)? in
                // While macOS is asking about a player, probing it again would only race the prompt.
                if player == skipped { return previous[player].map { (player, $0) } }
                return (player, Self.probe(player))
            })
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                guard fresh != self.status else { return }
                self.status = fresh
                log("players: " + Player.allCases.map { "\($0.rawValue.lowercased()) \(Self.describe(fresh[$0]))" }.joined(separator: ", "))
            }
        }
    }

    private static func probe(_ player: Player) -> PlayerStatus {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) != nil
        let running = isRunning(player)
        return PlayerStatus(installed: installed, running: running, access: running ? access(to: player, asking: false) : .unknown)
    }

    private static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// Asks macOS whether Stanza may send Apple Events to the player. With `asking` it shows the consent
    /// prompt and blocks until the user answers, so call it off the main thread.
    private static func access(to player: Player, asking: Bool) -> PlayerAccess {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.bundleID)
        guard let descriptor = target.aeDesc else { return .unknown }
        switch AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, asking) {
        case noErr: return .allowed
        case notPermitted: return .denied
        case wouldRequireConsent: return .notAsked
        default: return .unknown
        }
    }

    private static func describe(_ status: PlayerStatus?) -> String {
        guard let status, status.installed else { return "not installed" }
        return status.running ? "\(status.access)" : "closed"
    }

    // MARK: Fixes

    func open(_ player: Player) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error { log("could not open \(player.displayName): \(error.localizedDescription)") }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.recheckAfterOpenSeconds) { self?.check() }
        }
    }

    /// Shows the macOS consent prompt for a running player.
    func ask(_ player: Player) {
        guard asking == nil else { return }
        let number = beginAsking(player)
        askQueue.async { [weak self] in
            if Self.isRunning(player) { _ = Self.access(to: player, asking: true) }
            DispatchQueue.main.async { self?.endAsking(number) }
        }
    }

    /// Marks `player` as being asked about, and gives up waiting after `askTimeoutSeconds`: the macOS
    /// call cannot be cancelled, but a prompt nobody answers must not keep the buttons off for good.
    private func beginAsking(_ player: Player) -> Int {
        askNumber += 1
        asking = player
        let number = askNumber
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.askTimeoutSeconds) { [weak self] in self?.endAsking(number, timedOut: true) }
        return number
    }

    /// Main thread only. Runs once when ask `number` is answered and once when its time is up; whichever
    /// comes second finds the flag already cleared, or a newer ask in place, and leaves it alone.
    private func endAsking(_ number: Int, timedOut: Bool = false) {
        if number == askNumber, let player = asking {
            asking = nil
            if timedOut { log("no answer about \(player.displayName) after \(Int(Self.askTimeoutSeconds)) s — no longer waiting for one") }
        }
        check()
    }

    func openAutomationSettings() {
        URL(string: Self.automationSettings).map { _ = NSWorkspace.shared.open($0) }
    }

    /// For when the user once chose "Don't Allow": clears Stanza's saved Automation answers (for both
    /// players; macOS cannot reset just one) and has macOS ask about this player afresh.
    func resetAndAsk(_ player: Player) {
        guard asking == nil else { return }
        let number = beginAsking(player)
        if !Self.isRunning(player) { open(player) }
        askQueue.async { [weak self] in
            let outcome = Self.resetAutomationAnswers()
            let deadline = Date().addingTimeInterval(Self.waitForLaunchSeconds)
            while !Self.isRunning(player), Date() < deadline { Thread.sleep(forTimeInterval: 0.5) }
            let running = Self.isRunning(player)
            if running { _ = Self.access(to: player, asking: true) }
            log("automation answers reset (\(outcome)); " + (running ? "asked again about \(player.displayName)"
                                                                      : "\(player.displayName) is not open, so macOS asks when it next is"))
            DispatchQueue.main.async { self?.endAsking(number) }
        }
    }

    private static func resetAutomationAnswers() -> String {
        guard let bundleID = Bundle.main.bundleIdentifier else { return "no bundle id" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "AppleEvents", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return "tccutil exit \(process.terminationStatus)"
        } catch {
            return "tccutil failed: \(error.localizedDescription)"
        }
    }
}
