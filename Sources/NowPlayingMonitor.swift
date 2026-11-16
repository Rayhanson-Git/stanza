import AppKit
import Combine

enum Artwork {
    case url(URL)
    case data(Data)
}

/// Talks to Spotify / Music over AppleScript. Use only from `queue`: NSAppleScript is not thread-safe.
final class PlayerProbe {
    let queue = DispatchQueue(label: "stanza.applescript")
    // Spotify reports duration in milliseconds, Music in seconds. Replies use whole milliseconds so they
    // never contain a locale-dependent decimal separator.
    private let players = [
        (bundleID: "com.spotify.client", app: "Spotify", durationMS: "(duration of current track)"),
        (bundleID: "com.apple.Music", app: "Music", durationMS: "(((duration of current track) * 1000) as integer)"),
    ]
    // ASCII "unit separator": unlike a tab, it cannot appear in a track title.
    private static let fieldSeparator = "\u{1F}"
    private var compiled: [String: NSAppleScript] = [:]
    private var lastErrors: [String: String] = [:]

    /// The playing player's state, or failing that a paused one's.
    func sample() -> Sample? {
        let samples = players.filter { isRunning($0.bundleID) }.compactMap(sample)
        return samples.first(where: \.isPlaying) ?? samples.first
    }

    private func sample(_ player: (bundleID: String, app: String, durationMS: String)) -> Sample? {
        let before = Date()
        // The "is running" guard stops `tell` from relaunching a player that quit a moment ago, and the
        // timeout stops a hung player from freezing the lyrics for AppleScript's default two minutes.
        let reply = run("sample-\(player.app)", """
            if application "\(player.app)" is not running then return ""
            set sep to (ASCII character 31)
            with timeout of 2 seconds
                tell application "\(player.app)"
                    if player state is stopped then return ""
                    return (name of current track) & sep & (artist of current track) & sep & \(player.durationMS) & sep & ¬
                        (((player position) * 1000) as integer) & sep & (player state is playing)
                end tell
            end timeout
            """)?.stringValue ?? ""
        let after = Date()
        let fields = reply.components(separatedBy: Self.fieldSeparator)
        guard fields.count == 5, let durationMS = Double(fields[2]), let positionMS = Double(fields[3]) else { return nil }
        // Timestamp the sample at the middle of the round trip: the player answered somewhere in between.
        let sampledAt = before.addingTimeInterval(after.timeIntervalSince(before) / 2)
        return Sample(player: player.app, track: Track(title: fields[0], artist: fields[1], duration: durationMS / 1000),
                      position: positionMS / 1000, isPlaying: fields[4] == "true", sampledAt: sampledAt)
    }

    func artwork(player: String) -> Artwork? {
        switch player {
        case "Spotify":
            let reply = run("artwork-Spotify", """
                if application "Spotify" is not running then return ""
                with timeout of 2 seconds
                    tell application "Spotify" to return artwork url of current track
                end timeout
                """)
            return reply?.stringValue.flatMap(URL.init(string:)).map(Artwork.url)
        case "Music":
            let reply = run("artwork-Music", """
                if application "Music" is not running then return ""
                with timeout of 5 seconds
                    tell application "Music"
                        if (count of artworks of current track) is 0 then return ""
                        return raw data of artwork 1 of current track
                    end tell
                end timeout
                """)
            return reply.flatMap { $0.data.isEmpty ? nil : Artwork.data($0.data) }
        default:
            return nil
        }
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Scripts are compiled lazily and only for a running player: one naming an app that is not installed fails to compile.
    private func run(_ key: String, _ source: String) -> NSAppleEventDescriptor? {
        let script = compiled[key] ?? NSAppleScript(source: source)
        compiled[key] = script
        var error: NSDictionary?
        let reply = script?.executeAndReturnError(&error)
        let message = error.map { "\($0[NSAppleScript.errorNumber] ?? "?"): \($0[NSAppleScript.errorMessage] ?? "unknown error")" }
        // Log each script's error once per streak, not twice a second.
        if let message, message != lastErrors[key] {
            let hint = message.hasPrefix("-1743") ? " Allow Stanza under System Settings > Privacy & Security > Automation." : ""
            log("player query failed (\(message)).\(hint)")
        }
        lastErrors[key] = message
        return reply
    }
}

/// Polls the players and keeps a playback anchor that the overlay extrapolates from every frame.
final class NowPlayingMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    private(set) var anchor = Anchor.idle
    private(set) var player: String?
    let probe = PlayerProbe()
    private var timer: Timer?
    private var pollInFlight = false

    func start() {
        let timer = Timer(timeInterval: Timing.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    private func poll() {
        // A player that stops answering must not queue up a backlog of queries.
        guard !pollInFlight else { return }
        pollInFlight = true
        probe.queue.async { [weak self, probe] in
            let sample = probe.sample()
            DispatchQueue.main.async {
                self?.pollInFlight = false
                self?.apply(sample)
            }
        }
    }

    private func apply(_ sample: Sample?) {
        guard let sample else {
            if track != nil {
                log("nothing playing")
                track = nil
                player = nil
                anchor = .idle
            }
            if isPlaying { isPlaying = false }
            return
        }
        let sameTrack = track == sample.track
        if !sameTrack {
            log("now playing (\(sample.player)): \(sample.track.artist) — \(sample.track.title) (\(Int(sample.track.duration))s)")
            player = sample.player
            track = sample.track
        }
        if isPlaying != sample.isPlaying { isPlaying = sample.isPlaying }
        let fresh = Anchor(position: sample.position, date: sample.sampledAt, rate: sample.isPlaying ? 1 : 0)
        let now = Date()
        let drift = abs(fresh.position(at: now) - anchor.position(at: now))
        // Keeping the old anchor while it still agrees avoids visible jitter; a seek or pause replaces it at once.
        if !sameTrack || fresh.rate != anchor.rate || drift > Timing.resyncThreshold { anchor = fresh }
    }
}
