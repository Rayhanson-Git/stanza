import CryptoKit
import Foundation

/// Decides whether a lyrics-database entry is the same song as the playing track.
enum TrackMatch {
    static let durationToleranceSeconds = 3.0

    static func sameSong(title: String, artists: [String], as track: Track) -> Bool {
        let wanted = LyricsParsing.normalize(track.title)
        let found = LyricsParsing.normalize(title)
        guard !wanted.isEmpty, !found.isEmpty else { return false }
        // Whole-word containment either way: "lantern" matches "lantern live", but not "lanternsmith".
        guard " \(found) ".contains(" \(wanted) ") || " \(wanted) ".contains(" \(found) ") else { return false }
        func artistWords(_ names: [String]) -> Set<Substring> {
            let all = Set(names.flatMap { LyricsParsing.normalize($0).split(separator: " ") })
            let distinctive = all.subtracting(LyricsParsing.artistNoiseWords)
            // A name made only of common words has no distinctive words; then every word counts.
            return distinctive.isEmpty ? all : distinctive
        }
        let wantedArtistWords = artistWords([track.artist])
        return wantedArtistWords.isEmpty || !wantedArtistWords.isDisjoint(with: artistWords(artists))
    }

    static func durationMatches(_ seconds: Double, _ track: Track) -> Bool {
        track.duration <= 0 || abs(seconds - track.duration) <= durationToleranceSeconds
    }
}

/// Finds timed lyrics for a track: disk cache, then NetEase (word-level when it has it), then LRCLIB (line-level).
actor LyricsProvider {
    private static let maxCandidateProbes = 4
    private static let netEaseSearch = "https://music.163.com/api/search/get"
    private static let netEaseLyric = "https://music.163.com/api/song/lyric/v1"
    private static let lrcLibSearch = "https://lrclib.net/api/search"

    private struct NetEaseSearch: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        struct Song: Decodable {
            struct Artist: Decodable { let name: String? }
            let id: Int
            let name: String?
            let artists: [Artist]?
            let duration: Double?
            var seconds: Double { (duration ?? 0) / 1000 }
        }
        let result: Result?
    }
    private struct NetEaseLyric: Decodable {
        struct Body: Decodable { let lyric: String? }
        let yrc: Body?
        let lrc: Body?
    }
    private struct LRCLibEntry: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let syncedLyrics: String?
    }

    private let session: URLSession
    private let cacheDirectory: URL

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = ["User-Agent": "Stanza/0.2"]
        session = URLSession(configuration: configuration)
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stanza/Lyrics/v1", isDirectory: true)
    }

    func lyrics(for track: Track) async -> TimedLyrics? {
        if let cached = readCache(track) {
            log("lyrics: cache hit (\(cached.tier.rawValue), \(cached.words.count) words)")
            return cached
        }
        let netEase = await fromNetEase(track)
        var found = netEase.lyrics
        if found == nil { found = await fromLRCLib(track) }
        guard let found else {
            log("lyrics: nothing usable for \(track.artist) — \(track.title)")
            return nil
        }
        // Estimated timing that was only used because NetEase was unreachable is not kept, so the
        // next play gets another chance at true word-level lyrics.
        if found.tier == .wordLevel || netEase.reachable { writeCache(found, track) }
        return found
    }

    // MARK: Sources

    /// `reachable` is false when any request failed, as opposed to NetEase answering "no such song".
    private func fromNetEase(_ track: Track) async -> (lyrics: TimedLyrics?, reachable: Bool) {
        let primaryArtist = track.artist.components(separatedBy: CharacterSet(charactersIn: ",&")).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let wantedTitle = LyricsParsing.normalize(track.title)
        let query = ["s": "\(primaryArtist) \(wantedTitle)", "type": "1", "limit": "30", "offset": "0"]
        guard let response = await get(Self.netEaseSearch, query, as: NetEaseSearch.self) else { return (nil, false) }
        let candidates = (response.result?.songs ?? [])
            .filter { song in
                TrackMatch.durationMatches(song.seconds, track)
                    && TrackMatch.sameSong(title: song.name ?? "", artists: (song.artists ?? []).compactMap(\.name), as: track)
            }
            .sorted { first, second in
                let firstExact = LyricsParsing.normalize(first.name ?? "") == wantedTitle
                let secondExact = LyricsParsing.normalize(second.name ?? "") == wantedTitle
                if firstExact != secondExact { return firstExact }
                return abs(first.seconds - track.duration) < abs(second.seconds - track.duration)
            }
        guard !candidates.isEmpty else {
            log("lyrics: no NetEase candidate for \(track.artist) — \(track.title)")
            return (nil, true)
        }
        var lineLevelFallback: String?
        var reachable = true
        for song in candidates.prefix(Self.maxCandidateProbes) {
            let lyricQuery = ["id": String(song.id), "cp": "false", "lv": "0", "kv": "0", "tv": "0", "rv": "0",
                              "yv": "0", "ytv": "0", "yrv": "0"]
            guard let lyric = await get(Self.netEaseLyric, lyricQuery, as: NetEaseLyric.self) else {
                reachable = false
                continue
            }
            let words = LyricsParsing.dropTranslationLines(LyricsParsing.parseWordLevel(lyric.yrc?.lyric ?? ""), track: track)
            if !words.isEmpty {
                log("lyrics: word-level via NetEase \(song.id) (\(words.count) words)")
                return (TimedLyrics(tier: .wordLevel, words: words), true)
            }
            if lineLevelFallback == nil, let lrc = lyric.lrc?.lyric, !lrc.isEmpty { lineLevelFallback = lrc }
        }
        return (lineLevelFallback.flatMap { interpolated($0, track: track, source: "NetEase") }, reachable)
    }

    private func fromLRCLib(_ track: Track) async -> TimedLyrics? {
        let query = ["track_name": track.title, "artist_name": track.artist]
        guard let entries = await get(Self.lrcLibSearch, query, as: [LRCLibEntry].self) else { return nil }
        let best = entries
            .filter { entry in
                entry.syncedLyrics != nil && TrackMatch.durationMatches(entry.duration ?? 0, track)
                    && TrackMatch.sameSong(title: entry.trackName ?? "", artists: [entry.artistName ?? ""], as: track)
            }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }
        return best?.syncedLyrics.flatMap { interpolated($0, track: track, source: "LRCLIB") }
    }

    private func interpolated(_ lrc: String, track: Track, source: String) -> TimedLyrics? {
        let words = LyricsParsing.dropTranslationLines(LyricsParsing.interpolate(LyricsParsing.parseLineLevel(lrc)), track: track)
        guard !words.isEmpty else { return nil }
        log("lyrics: interpolated from \(source) line-level (\(words.count) words)")
        return TimedLyrics(tier: .interpolated, words: words)
    }

    private func get<Response: Decodable>(_ url: String, _ query: [String: String], as type: Response.Type) async -> Response? {
        guard var components = URLComponents(string: url) else { return nil }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let requestURL = components.url else { return nil }
        do {
            let (data, response) = try await session.data(from: requestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                log("lyrics: HTTP failure from \(components.host ?? url)")
                return nil
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            // A cancelled request just means the track changed mid-fetch.
            if (error as? URLError)?.code != .cancelled { log("lyrics: request to \(components.host ?? url) failed — \(error.localizedDescription)") }
            return nil
        }
    }

    // MARK: Cache

    private func cacheFile(_ track: Track) -> URL {
        let key = "\(track.artist)|\(track.title)|\(Int(track.duration.rounded()))"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(digest).json")
    }

    private func readCache(_ track: Track) -> TimedLyrics? {
        guard let data = try? Data(contentsOf: cacheFile(track)) else { return nil }
        // An unreadable entry (for example from an older format) is simply a miss and gets rewritten.
        return try? JSONDecoder().decode(TimedLyrics.self, from: data)
    }

    private func writeCache(_ lyrics: TimedLyrics, _ track: Track) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(lyrics).write(to: cacheFile(track), options: .atomic)
        } catch {
            log("lyrics: could not write cache — \(error.localizedDescription)")
        }
    }
}
