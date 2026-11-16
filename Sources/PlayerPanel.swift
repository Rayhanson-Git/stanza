import SwiftUI

/// The player's own app icon, or a music note when the player is not installed.
struct PlayerIcon: View {
    // Looked up once: an app icon does not change while Stanza runs.
    private static let icons: [Player: NSImage] = Dictionary(uniqueKeysWithValues: Player.allCases.compactMap { player in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID).map { (player, NSWorkspace.shared.icon(forFile: $0.path)) }
    })

    let player: Player
    let size: CGFloat

    var body: some View {
        if let icon = Self.icons[player] {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "music.note").font(.system(size: size * 0.6, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                .frame(width: size, height: size)
        }
    }
}

/// Green when lyrics can follow the player, amber when a step is waiting, red when macOS blocks it.
struct StatusDot: View {
    static let size: CGFloat = 9

    let health: PlayerHealth

    var body: some View {
        Circle().fill(color).frame(width: Self.size, height: Self.size).overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
    }

    private var color: Color {
        switch health {
        case .idle, .paused, .playing: return Color(red: 0.2, green: 0.84, blue: 0.4)
        case .notAsked, .unverified: return Color(red: 1, green: 0.76, blue: 0.2)
        case .denied: return Color(red: 1, green: 0.33, blue: 0.3)
        case .checking, .notInstalled, .closed: return Color(white: 0.55)
        }
    }
}

/// The two round buttons at the right of the top bar; each opens its player's panel.
struct PlayerButtons: View {
    private enum Metrics {
        static let button: CGFloat = 36
        static let icon: CGFloat = 22
        static let dotOffset: CGFloat = 3
    }

    @ObservedObject var model: GalleryModel
    @ObservedObject var link: PlayerLink
    @ObservedObject var monitor: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Player.allCases, id: \.self) { player in
                button(player, health: link.health(of: player, source: monitor.player, isPlaying: monitor.isPlaying))
            }
        }
    }

    private func button(_ player: Player, health: PlayerHealth) -> some View {
        let menu = GalleryMenu(player: player)
        let isOpen = model.menu == menu
        return Hoverable(id: "player.\(player.rawValue)", hover: model.hover) { hovered in
            Button { model.toggle(menu) } label: {
                PlayerIcon(player: player, size: Metrics.icon)
                    .overlay(alignment: .bottomTrailing) { StatusDot(health: health).offset(x: Metrics.dotOffset, y: Metrics.dotOffset) }
                    .frame(width: Metrics.button, height: Metrics.button)
                    .background(Color.white.opacity(isOpen ? 0.18 : hovered ? 0.08 : 0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("\(player.displayName): \(health.label)")
            .accessibilityLabel("\(player.displayName), \(health.label)")
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        }
    }
}

private let stepBadgeSize: CGFloat = 20

/// One numbered line of the walkthrough, with its fix button and anything extra under it.
struct PlayerStepRow<Extra: View>: View {
    let step: PlayerStep
    var fixLabel: String?
    var fixDisabled = false
    var onFix: () -> Void = {}
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(step.state == .later ? 0.5 : 1))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = step.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                }
                if let fixLabel {
                    Button(fixLabel, action: onFix).buttonStyle(QuietButtonStyle()).disabled(fixDisabled).padding(.top, 3)
                }
                extra()
            }
            .padding(.top, 1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var badge: some View {
        let number = Text("\(step.number)").font(.system(size: 11, weight: .semibold).monospacedDigit())
        Group {
            switch step.state {
            case .done:
                Circle().fill(.white).overlay(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black))
            case .next:
                Circle().strokeBorder(.white, lineWidth: 1.5).overlay(number.foregroundStyle(.white))
            case .later:
                Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1).overlay(number.foregroundStyle(.white.opacity(0.4)))
            case .blocked:
                Circle().fill(Color(red: 1, green: 0.62, blue: 0.2))
                    .overlay(Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black))
            }
        }
        .frame(width: stepBadgeSize, height: stepBadgeSize)
        .accessibilityHidden(true)
    }
}

/// Is this player connected, and if not, what is the next thing to do about it. The full panel adds the
/// lyric status with both timing controls; `compact` (first run) stops at "play a song".
struct PlayerPanel: View {
    let player: Player
    @ObservedObject var link: PlayerLink
    @ObservedObject var monitor: NowPlayingMonitor
    @ObservedObject var engine: LyricEngine
    @ObservedObject var settings: AppSettings
    var compact = false

    var body: some View {
        let health = link.health(of: player, source: monitor.player, isPlaying: monitor.isPlaying)
        VStack(alignment: .leading, spacing: 14) {
            header(health)
            if health == .notInstalled {
                Text("\(player.displayName) isn't installed on this Mac. Once it is installed and open, the remaining steps show up here.")
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            } else {
                steps(health)
            }
            if !compact {
                askAgain(health)
                PanelRule()
                StandingTimingControl(settings: settings)
            }
        }
    }

    private func header(_ health: PlayerHealth) -> some View {
        HStack(spacing: 10) {
            PlayerIcon(player: player, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 5) {
                    StatusDot(health: health)
                    Text(health.label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func steps(_ health: PlayerHealth) -> some View {
        let isSource = monitor.player == player.rawValue && monitor.track != nil
        let connection = PlayerSteps.connection(player: player, health: health, trackTitle: isSource ? monitor.track?.title : nil,
                                                otherIsSource: monitor.track != nil && !isSource)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(connection, id: \.number) { step in
                PlayerStepRow(step: step, fixLabel: step.fix.map(fixLabel), fixDisabled: link.asking != nil && step.fix != .openSettings,
                              onFix: { step.fix.map(run) }) { EmptyView() }
            }
            if !compact {
                PlayerStepRow(step: isSource ? PlayerSteps.lyrics(tier: engine.lyrics?.tier, isFetching: engine.isFetching)
                                             : PlayerSteps.lyricsLater) {
                    if isSource, engine.lyrics != nil { LyricTimingControl(engine: engine) }
                }
            }
        }
    }

    private func fixLabel(_ fix: PlayerFix) -> String {
        link.asking == player && (fix == .allow || fix == .checkNow) ? "Waiting for your answer…" : fix.label(for: player)
    }

    private func run(_ fix: PlayerFix) {
        switch fix {
        case .open: link.open(player)
        case .allow, .checkNow: link.ask(player)
        case .openSettings: link.openAutomationSettings()
        }
    }

    private func askAgain(_ health: PlayerHealth) -> some View {
        Button(link.asking == player ? "Waiting for your answer…" : "Ask for permission again") { link.resetAndAsk(player) }
            .buttonStyle(QuietButtonStyle())
            .disabled(link.asking != nil || health == .notInstalled || health == .checking)
            .help("Wipes Stanza's saved answers for both players, then has macOS ask about \(player.displayName) from scratch.")
    }
}

/// Earlier / later for the song that is playing. Forgotten when the next song starts.
struct LyricTimingControl: View {
    @ObservedObject var engine: LyricEngine

    var body: some View {
        let delay = engine.lyricDelay
        let step = LyricEngine.lyricDelayStep
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                nudge("gobackward", "Lyrics \(Int(step)) second sooner", by: -step).disabled(delay <= -LyricEngine.lyricDelayLimit)
                Text(PlayerSteps.delayReadout(delay))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(minWidth: 46)
                    .accessibilityLabel(delay == 0 ? "Lyrics at their normal timing"
                                                   : "Lyrics \(Int(abs(delay))) seconds \(delay > 0 ? "later" : "sooner")")
                nudge("goforward", "Lyrics \(Int(step)) second later", by: step).disabled(delay >= LyricEngine.lyricDelayLimit)
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: delay)
            HStack {
                Text("Goes back to normal with the next song.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                if Int(delay) != 0 {
                    Button("Reset") { engine.resetLyricDelay() }.buttonStyle(QuietButtonStyle())
                }
            }
            .frame(minHeight: 26)
        }
        .padding(.top, 6)
    }

    private func nudge(_ symbol: String, _ label: String, by seconds: Double) -> some View {
        Button { engine.shiftLyrics(by: seconds) } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(DimWhenDisabledStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The saved offset that applies to every song, for a player or speakers that always run early or late.
struct StandingTimingControl: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        // The setting counts "earlier" as positive; the slider reads left = earlier, right = later.
        let later = Binding(get: { -settings.syncOffset }, set: { settings.syncOffset = -$0 })
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timing for all songs").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                Spacer()
                Text(PlayerSteps.offsetReadout(later.wrappedValue))
                    .font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(.white)
            }
            HStack(spacing: 10) {
                edgeLabel("Earlier")
                Slider(value: later, in: AppSettings.syncOffsetRange) { Text("Timing for all songs") }.labelsHidden().tint(.white)
                    .adjustsWithScroll(later, in: AppSettings.syncOffsetRange)
                edgeLabel("Later")
            }
            HStack {
                Text("Saved, and applied to every song.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 6)
                Button("Reset") { settings.syncOffset = 0 }.buttonStyle(QuietButtonStyle()).disabled(settings.syncOffset == 0)
            }
        }
    }

    private func edgeLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
    }
}
