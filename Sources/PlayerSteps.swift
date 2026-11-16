import Foundation

/// A one-click remedy offered next to a step.
enum PlayerFix: Equatable {
    case open, allow, checkNow, openSettings

    func label(for player: Player) -> String {
        switch self {
        case .open: return "Open \(player.displayName)"
        case .allow: return "Allow"
        case .checkNow: return "Check now"
        case .openSettings: return "Open Settings"
        }
    }
}

/// One line of the "get this player connected" walkthrough.
struct PlayerStep: Equatable {
    enum State {
        case done, next, later, blocked
    }

    let number: Int
    let state: State
    let title: String
    var detail: String?
    var fix: PlayerFix?
}

/// Turns what is known about a player into the walkthrough: open it, let Stanza read it, play a song,
/// get lyrics. Pure, so the wording for every situation can be checked without a player.
enum PlayerSteps {
    static let lyricsStepNumber = 4

    /// Steps 1–3. `otherIsSource` is true when Stanza is currently following the other player.
    static func connection(player: Player, health: PlayerHealth, trackTitle: String?, otherIsSource: Bool) -> [PlayerStep] {
        [openStep(player, health), accessStep(player, health), songStep(player, health, trackTitle, otherIsSource)]
    }

    private static func isOpen(_ health: PlayerHealth) -> Bool { health != .checking && health != .notInstalled && health != .closed }

    private static func isReadable(_ health: PlayerHealth) -> Bool { health == .idle || health == .paused || health == .playing }

    private static func openStep(_ player: Player, _ health: PlayerHealth) -> PlayerStep {
        if isOpen(health) { return PlayerStep(number: 1, state: .done, title: "\(player.displayName) is open") }
        // Until the first check is back there is nothing to ask of the user, so every step waits.
        guard health != .checking else { return PlayerStep(number: 1, state: .later, title: "Open \(player.displayName)") }
        return PlayerStep(number: 1, state: .next, title: "Open \(player.displayName)", fix: .open)
    }

    private static func accessStep(_ player: Player, _ health: PlayerHealth) -> PlayerStep {
        let asking = "Let Stanza see what is playing"
        switch health {
        case .checking, .notInstalled, .closed:
            return PlayerStep(number: 2, state: .later, title: asking)
        case .notAsked:
            return PlayerStep(number: 2, state: .next, title: asking, detail: "macOS asks a single time. Pick Allow.", fix: .allow)
        case .unverified:
            return PlayerStep(number: 2, state: .next, title: asking,
                              detail: "Not confirmed yet. Stanza learns the answer the first time it reads \(player.displayName).",
                              fix: .checkNow)
        case .denied:
            return PlayerStep(number: 2, state: .blocked, title: asking,
                              detail: "Switch on \(player.displayName) under Stanza in Privacy & Security › Automation.",
                              fix: .openSettings)
        case .idle, .paused, .playing:
            return PlayerStep(number: 2, state: .done, title: "Stanza can see what is playing")
        }
    }

    private static func songStep(_ player: Player, _ health: PlayerHealth, _ trackTitle: String?, _ otherIsSource: Bool) -> PlayerStep {
        let quoted = trackTitle.map { "“\($0)”" } ?? "a song"
        switch health {
        case .playing: return PlayerStep(number: 3, state: .done, title: "Playing \(quoted)")
        case .paused: return PlayerStep(number: 3, state: .done, title: "Paused on \(quoted)")
        default:
            let following = health == .idle && otherIsSource
            return PlayerStep(number: 3, state: isReadable(health) ? .next : .later, title: "Play a song in \(player.displayName)",
                              detail: following ? "Stanza follows the player that is playing, and picks Spotify when both are." : nil)
        }
    }

    /// Step 4, for the player Stanza is following.
    static func lyrics(tier: LyricTier?, isFetching: Bool) -> PlayerStep {
        switch (tier, isFetching) {
        case (.wordLevel?, _):
            return PlayerStep(number: lyricsStepNumber, state: .done, title: "Lyrics found, timed to each word")
        case (.interpolated?, _):
            return PlayerStep(number: lyricsStepNumber, state: .done, title: "Lyrics found, timed to each line")
        case (nil, true):
            return PlayerStep(number: lyricsStepNumber, state: .next, title: "Searching for lyrics…")
        case (nil, false):
            return PlayerStep(number: lyricsStepNumber, state: .blocked, title: "No lyrics for this song",
                              detail: "The overlay stays empty until a song that has them.")
        }
    }

    /// Step 4 while this player has no song for Stanza to follow.
    static let lyricsLater = PlayerStep(number: lyricsStepNumber, state: .later, title: "Lyrics appear in time with the song")

    /// "0 s", "+3 s" or "−2 s" (a true minus sign, so the digits line up with the plus).
    static func delayReadout(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return whole == 0 ? "0 s" : "\(whole > 0 ? "+" : "−")\(abs(whole)) s"
    }

    /// Same, to a hundredth of a second, for the standing offset.
    static func offsetReadout(_ seconds: Double) -> String {
        abs(seconds) < 0.005 ? "0.00 s" : String(format: "%@%.2f s", seconds > 0 ? "+" : "−", abs(seconds))
    }
}
