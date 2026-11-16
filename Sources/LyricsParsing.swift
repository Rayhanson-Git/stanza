import Foundation

/// Pure text-to-timing functions: no network, no state. Covered by SelfCheck.swift.
enum LyricsParsing {
    static let lastLineSeconds = 5.0
    static let minLineSeconds = 0.2
    static let secondsPerCharacter = 0.18
    static let lineBaseSeconds = 1.2
    static let maxCreditHeadLength = 13
    static let translationPairingSeconds = 0.5
    // Artist words too common to prove two artists are the same one.
    static let artistNoiseWords: Set<Substring> = ["the", "and", "dj", "feat", "ft", "with", "band", "orchestra"]

    // Credit lines look like "Producer: Someone" / "作词: 某人"; they are metadata, not lyrics.
    private static let creditKeywords = [
        "作词", "作曲", "编曲", "制作", "出品", "混音", "母带", "监制", "录音", "和声", "吉他", "贝斯", "键盘", "鼓", "发行", "词", "曲",
        "producer", "composed", "lyrics by", "written by", "arranged", "mixed by", "mastered by",
    ]

    // Title noise that stops a store title matching a lyrics-database title.
    // Applied to already-lowercased text. The patterns are constants, so a failure to compile is a programmer error.
    private static let titleNoise: [Regex<AnyRegexOutput>] = [
        #"\((feat|ft|with|featuring)[.\s][^)]*\)"#,
        #"\[[^\]]*\]"#,
        #"\((from|theme from|music from)[^)]*\)"#,
        #"\((\d{4} )?(re-?master(ed)?|deluxe|bonus|explicit|single|album|radio)[^)]*\)"#,
        #"\s-\s.*(remix|version|edit|mix|remaster|acoustic|live|instrumental).*$"#,
    ].map { try! Regex($0) }

    /// Lowercased, accent-folded, noise-stripped, alphanumerics-only form used to compare titles and artists.
    static func normalize(_ text: String) -> String {
        func words(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? $0 : " " }))
                .split(separator: " ").joined(separator: " ")
        }
        let folded = text.lowercased().folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        let stripped = words(titleNoise.reduce(folded) { $0.replacing($1, with: " ") })
        // A title that is nothing but "noise", like "(Say It Twice)" or "[Untitled]", keeps its words.
        return stripped.isEmpty ? words(folded) : stripped
    }

    static func isCredit(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let colon = lowered.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let head = lowered[..<colon].trimmingCharacters(in: .whitespaces)
        return head.count < maxCreditHeadLength && creditKeywords.contains { head.contains($0) }
    }

    // MARK: Word-level ("yrc"): [lineStart,lineDur](wordStart,wordDur,0)word (wordStart,wordDur,0)word …

    static func parseWordLevel(_ text: String) -> [TimedWord] {
        let tag = #/\((\d+),(\d+)(?:,-?\d+)?\)/#
        let lines: [[TimedWord]] = text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("{"), let header = line.firstIndex(of: "]") else { return nil }
            let body = line[line.index(after: header)...]
            let tags = body.matches(of: tag)
            // Text for a tag runs to the next tag, so words containing "(" survive.
            let words: [TimedWord] = tags.indices.compactMap { index in
                let textEnd = index + 1 < tags.count ? tags[index + 1].range.lowerBound : body.endIndex
                let word = body[tags[index].range.upperBound..<textEnd].trimmingCharacters(in: .whitespaces)
                guard !word.isEmpty, let startMS = Double(tags[index].1), let durationMS = Double(tags[index].2) else { return nil }
                return TimedWord(text: word, start: startMS / 1000, end: (startMS + durationMS) / 1000, line: 0)
            }
            return words.isEmpty || isCredit(words.map(\.text).joined(separator: " ")) ? nil : words
        }
        return clean(numbered(lines))
    }

    // MARK: Line-level (LRC): [mm:ss.xx]text, possibly several time tags per line

    static func parseLineLevel(_ text: String) -> [(time: Double, text: String)] {
        // [0-9], not \d: \d also matches full-width and other Unicode digits, which Double() cannot read.
        let tag = #/\[([0-9]+):([0-9]+)(?:[.:]([0-9]+))?\]/#
        let inlineWordTag = #/<[0-9]+:[0-9]+(?:[.:][0-9]+)?>/#
        let entries: [(time: Double, text: String)] = text.split(whereSeparator: \.isNewline).flatMap { raw -> [(time: Double, text: String)] in
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while let match = rest.prefixMatch(of: tag) {
                if let minutes = Double(match.1), let seconds = Double("\(match.2).\(match.3 ?? "0")") {
                    times.append(minutes * 60 + seconds)
                }
                rest = rest[match.range.upperBound...]
            }
            let lyric = rest.replacing(inlineWordTag, with: "").trimmingCharacters(in: .whitespaces)
            return lyric.isEmpty || isCredit(lyric) ? [] : times.map { ($0, lyric) }
        }
        return entries.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    /// Spreads word times across each line by letter count, capped so a line before a long gap does not crawl.
    static func interpolate(_ lines: [(time: Double, text: String)]) -> [TimedWord] {
        let perLine: [[TimedWord]] = lines.indices.map { index in
            let start = lines[index].time
            let next = index + 1 < lines.count ? lines[index + 1].time : start + lastLineSeconds
            let tokens = lines[index].text.split(separator: " ")
            let weights = tokens.map { max(1.0, Double($0.filter { $0.isLetter || $0.isNumber }.count)) }
            let total = weights.reduce(0, +)
            let span = max(minLineSeconds, min(next - start, total * secondsPerCharacter + lineBaseSeconds))
            return tokens.indices.map { word in
                let before = weights[..<word].reduce(0, +)
                return TimedWord(text: String(tokens[word]), start: start + span * before / total,
                                 end: start + span * (before + weights[word]) / total, line: 0)
            }
        }
        return clean(numbered(perLine))
    }

    /// Drops Chinese lines that are a translation printed alongside a non-Chinese original line.
    /// A translation shares its timestamp with the line it translates; a Chinese line that stands alone
    /// in time is real lyrics (a Mandarin song with Latin metadata, or kanji-only Japanese) and is kept.
    static func dropTranslationLines(_ words: [TimedWord], track: Track) -> [TimedWord] {
        func isHan(_ scalar: Unicode.Scalar) -> Bool {
            (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) || (0xF900...0xFAFF).contains(scalar.value)
        }
        func isKana(_ scalar: Unicode.Scalar) -> Bool { (0x3040...0x30FF).contains(scalar.value) }
        guard !(track.title + track.artist).unicodeScalars.contains(where: isHan) else { return words }
        let lines = Dictionary(grouping: words, by: \.line)
        func isHanLine(_ lineWords: [TimedWord]) -> Bool {
            let scalars = lineWords.flatMap { $0.text.unicodeScalars }.filter { CharacterSet.alphanumerics.contains($0) }
            return !scalars.isEmpty && !scalars.contains(where: isKana) && scalars.filter(isHan).count * 2 > scalars.count
        }
        let originalStarts = lines.values.filter { !isHanLine($0) }.compactMap { $0.map(\.start).min() }
        let translated = Set(lines.compactMap { line, lineWords -> Int? in
            guard isHanLine(lineWords), let start = lineWords.map(\.start).min() else { return nil }
            return originalStarts.contains { abs($0 - start) <= translationPairingSeconds } ? line : nil
        })
        return translated.isEmpty ? words : words.filter { !translated.contains($0.line) }
    }

    // MARK: Helpers

    /// Numbers lines in start order. Words stay grouped by line, so overlapping lines (duets) do not interleave.
    private static func numbered(_ lines: [[TimedWord]]) -> [TimedWord] {
        lines.filter { !$0.isEmpty }.enumerated()
            .sorted { ($0.element[0].start, $0.offset) < ($1.element[0].start, $1.offset) }
            .enumerated().flatMap { index, line in
                line.element.map { TimedWord(text: $0.text, start: $0.start, end: $0.end, line: index) }
            }
    }

    /// Removes full-width brackets and glues punctuation-only tokens onto the word before them.
    private static func clean(_ words: [TimedWord]) -> [TimedWord] {
        words.reduce(into: [TimedWord]()) { cleaned, word in
            let text = word.text.replacingOccurrences(of: "（", with: "").replacingOccurrences(of: "）", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return }
            let hasAlphanumeric = text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
            if hasAlphanumeric {
                cleaned.append(TimedWord(text: text, start: word.start, end: word.end, line: word.line))
            } else if let previous = cleaned.last, previous.line == word.line {
                cleaned[cleaned.count - 1] = TimedWord(text: previous.text + text, start: previous.start,
                                                       end: max(previous.end, word.end), line: previous.line)
            }
        }
    }
}
