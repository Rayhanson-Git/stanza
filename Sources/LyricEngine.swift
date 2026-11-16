import Combine
import Foundation

/// Owns the lyrics for the current track and answers "where are we in the song" for every frame.
final class LyricEngine: ObservableObject {
    static let lyricDelayStep = 1.0
    static let lyricDelayLimit = 20.0

    @Published private(set) var lyrics: TimedLyrics?
    /// True from a track change until its lyrics lookup finishes, so the UI can tell "looking" from "none found".
    @Published private(set) var isFetching = false
    /// Seconds the lyrics are held back for the current song only (negative = earlier). Not saved.
    @Published private(set) var lyricDelay = 0.0
    private var delayedTrack: Track?
    let monitor: NowPlayingMonitor
    private let settings: AppSettings
    private let provider = LyricsProvider()
    private var trackObserver: AnyCancellable?
    private var fetchTask: Task<Void, Never>?

    init(monitor: NowPlayingMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
        trackObserver = monitor.$track.removeDuplicates().sink { [weak self] in self?.load($0) }
    }

    /// Song position for a frame drawn at `date`: the display lead, the user's standing sync offset,
    /// and this song's own nudge.
    func position(at date: Date) -> Double {
        monitor.anchor.position(at: date) + Timing.displayLead + settings.syncOffset - lyricDelay
    }

    /// Moves this song's lyrics later (positive) or earlier (negative), within ±`lyricDelayLimit`.
    func shiftLyrics(by seconds: Double) {
        let shifted = min(Self.lyricDelayLimit, max(-Self.lyricDelayLimit, lyricDelay + seconds))
        guard shifted != lyricDelay else { return }
        lyricDelay = shifted
        log(String(format: "lyric timing for this song %+.0fs", shifted))
    }

    func resetLyricDelay() {
        guard lyricDelay != 0 else { return }
        lyricDelay = 0
        log("lyric timing for this song → default")
    }

    private func load(_ track: Track?) {
        fetchTask?.cancel()
        lyrics = nil
        isFetching = track != nil
        guard let track else { return }
        // The nudge belongs to one song: it survives pause and seek, and ends when a different track starts.
        if delayedTrack != track {
            delayedTrack = track
            if lyricDelay != 0 { lyricDelay = 0 }
        }
        fetchTask = Task { @MainActor [weak self, provider] in
            let found = await provider.lyrics(for: track)
            // The track may have changed while the request was in flight.
            guard !Task.isCancelled, let self else { return }
            if let found { WordVisuals.shared.prepare(words: found.words.map(\.text)) }
            self.lyrics = found
            self.isFetching = false
        }
    }
}
