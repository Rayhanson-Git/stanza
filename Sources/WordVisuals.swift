import AppKit
import NaturalLanguage

enum WordVisual: Equatable {
    case symbol(String)
    case emoji(String)
}

/// Maps lyric words to a small picture (SF Symbol or emoji) for the "Visual" styles.
/// Lookup order: remembered answers, a hand-written table, Apple's own symbol search keywords,
/// then (in the background) words that an on-device language model considers close in meaning.
final class WordVisuals {
    static let shared = WordVisuals()

    private static let minWordLength = 3
    private static let neighbourCount = 20
    private static let maxNeighbourDistance = 0.85
    private static let symbolSearchIndex = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_search.plist"

    static let symbols: [String: String] = [
        "love": "heart.fill", "heart": "heart.fill", "broken": "heart.slash.fill", "pain": "bandage.fill", "hurt": "bandage.fill",
        "fire": "flame.fill", "burn": "flame.fill", "sun": "sun.max.fill", "moon": "moon.fill", "night": "moon.stars.fill",
        "star": "star.fill", "shine": "sparkles", "gold": "sparkles", "magic": "wand.and.stars", "rain": "cloud.rain.fill",
        "storm": "cloud.bolt.rain.fill", "snow": "snowflake", "wind": "wind", "sky": "cloud.fill", "ocean": "water.waves",
        "sea": "water.waves", "wave": "water.waves", "water": "drop.fill", "tear": "drop.fill", "cry": "drop.fill",
        "eye": "eye.fill", "see": "eye.fill", "look": "eye.fill", "hand": "hand.raised.fill", "home": "house.fill",
        "house": "house.fill", "door": "door.left.hand.open", "car": "car.fill", "drive": "car.fill", "road": "road.lanes",
        "fly": "airplane", "plane": "airplane", "phone": "phone.fill", "call": "phone.fill", "time": "clock.fill",
        "clock": "clock.fill", "money": "dollarsign.circle.fill", "cash": "banknote.fill", "crown": "crown.fill",
        "king": "crown.fill", "queen": "crown.fill", "music": "music.note", "song": "music.note", "sing": "music.mic",
        "dance": "figure.dance", "run": "figure.run", "walk": "figure.walk", "world": "globe.americas.fill",
        "earth": "globe.americas.fill", "light": "lightbulb.fill", "lightning": "bolt.fill", "thunder": "bolt.fill",
        "key": "key.fill", "lock": "lock.fill", "book": "book.fill", "letter": "envelope.fill", "camera": "camera.fill",
        "picture": "photo.fill", "tree": "tree.fill", "leaf": "leaf.fill", "bird": "bird.fill", "dog": "dog.fill",
        "cat": "cat.fill", "fish": "fish.fill", "sleep": "bed.double.fill", "dream": "moon.zzz.fill", "bed": "bed.double.fill",
        "drink": "wineglass.fill", "wine": "wineglass.fill", "coffee": "cup.and.saucer.fill", "gift": "gift.fill",
        "party": "party.popper.fill", "game": "gamecontroller.fill", "bell": "bell.fill", "flag": "flag.fill",
        "mountain": "mountain.2.fill", "city": "building.2.fill", "diamond": "diamond.fill",
    ]
    static let emoji: [String: String] = [
        "angel": "👼", "devil": "😈", "ghost": "👻", "kiss": "💋", "rose": "🌹", "rainbow": "🌈", "rocket": "🚀",
        "skull": "💀", "alien": "👽", "butterfly": "🦋", "cherry": "🍒", "champagne": "🍾", "dragon": "🐉",
        "tiger": "🐅", "wolf": "🐺", "snake": "🐍", "pizza": "🍕", "clown": "🤡", "unicorn": "🦄", "honey": "🍯",
    ]
    // Words too common or too vague to deserve a picture.
    static let stopWords: Set<String> = [
        "the", "and", "but", "for", "nor", "not", "you", "your", "yours", "she", "her", "hers", "him", "his", "they", "them",
        "their", "our", "ours", "its", "this", "that", "these", "those", "what", "when", "where", "who", "whom", "why", "how",
        "was", "were", "are", "been", "being", "have", "has", "had", "does", "did", "will", "would", "could", "should", "can",
        "may", "might", "must", "shall", "with", "without", "from", "into", "onto", "over", "under", "about", "after", "before",
        "then", "than", "there", "here", "just", "only", "even", "ever", "never", "still", "also", "very", "too", "much", "many",
        "some", "any", "all", "one", "out", "off", "got", "get", "gets", "let", "lets", "say", "said", "says", "know", "knows",
        "like", "want", "wanna", "gonna", "gotta", "cause", "yeah", "ooh", "ohh", "nah", "hey", "thing", "things", "way", "ways",
        "good", "bad", "new", "now", "back", "down", "more", "most", "make", "made", "take", "took", "come", "came", "goes",
        "going", "gone", "tell", "told", "feel", "feels", "felt", "need", "needs", "keep", "kept", "give", "gave", "yes",
    ]

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "stanza.wordvisuals", qos: .utility)
    private let memoURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stanza/WordVisuals/v1.json")
    // Guarded by `lock`. Memo values: "s:<symbol>", "e:<emoji>" or "" for "no picture".
    private var memo: [String: String] = [:]
    private var searchIndex: [String: String] = [:]
    private var embedding: NLEmbedding?
    private var changes = 0

    /// Goes up whenever `visual(for:)` may start answering differently: the tables have finished loading, or
    /// `prepare` has resolved new words. A caller that keeps answers can tell from it when to ask again.
    var revision: Int { lock.withLock { changes } }

    private init() {
        queue.async { [self] in
            let remembered = (try? Data(contentsOf: memoURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            let index = Self.loadSearchIndex()
            let model = NLEmbedding.wordEmbedding(for: .english)
            lock.withLock {
                memo = remembered
                searchIndex = index
                embedding = model
                changes += 1
            }
            log("word visuals: \(index.count) search terms, language model \(model == nil ? "missing" : "ready"), \(remembered.count) remembered words")
        }
    }

    /// Fast lookup for the render loop: only answers that need no language model.
    func visual(for word: String) -> WordVisual? {
        let key = Self.key(word)
        guard key.count >= Self.minWordLength else { return nil }
        return lock.withLock { memo[key].map(Self.decode) ?? direct(key) }
    }

    /// Resolves a track's words in the background, including the slower "close in meaning" search, and remembers them.
    func prepare(words: [String]) {
        let keys = Set(words.map(Self.key).filter { $0.count >= Self.minWordLength })
        queue.async { [self] in
            let (unknown, hasModel) = lock.withLock { (keys.filter { memo[$0] == nil }, embedding != nil) }
            // Without the language model a miss is not final, so only hits are remembered.
            let resolved = Dictionary(uniqueKeysWithValues: unknown.map { ($0, Self.encode(resolve($0))) })
                .filter { hasModel || !$0.value.isEmpty }
            guard !resolved.isEmpty else { return }
            let snapshot = lock.withLock { () -> [String: String] in
                memo = memo.merging(resolved) { _, new in new }
                changes += 1
                return memo
            }
            do {
                try FileManager.default.createDirectory(at: memoURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: memoURL, options: .atomic)
            } catch {
                log("word visuals: could not save — \(error.localizedDescription)")
            }
            log("word visuals: resolved \(resolved.count) new words")
        }
    }

    // MARK: Resolution

    private func resolve(_ key: String) -> WordVisual? {
        let (found, model) = lock.withLock { (direct(key), embedding) }
        if let found { return found }
        guard !Self.stopWords.contains(key), let model else { return nil }
        for candidate in Self.variants(key) {
            for (neighbour, distance) in model.neighbors(for: candidate, maximumCount: Self.neighbourCount, distanceType: .cosine)
            where distance < Self.maxNeighbourDistance {
                let word = neighbour.lowercased()
                if !Self.stopWords.contains(word), let visual = lock.withLock({ lookup(word) }) { return visual }
            }
        }
        return nil
    }

    /// Call with `lock` held.
    private func direct(_ key: String) -> WordVisual? {
        Self.stopWords.contains(key) ? nil : Self.variants(key).lazy.compactMap(lookup).first
    }

    /// Call with `lock` held.
    private func lookup(_ word: String) -> WordVisual? {
        if let symbol = Self.symbols[word] ?? searchIndex[word] { return .symbol(symbol) }
        return Self.emoji[word].map(WordVisual.emoji)
    }

    // MARK: Pure helpers (covered by SelfCheck.swift)

    static func key(_ word: String) -> String { word.lowercased().filter(\.isLetter) }

    /// The word plus simple stems: "burning" → burn, burne; "eyes" → eye; "stopped" → stopp, stoppe, stop.
    static func variants(_ word: String) -> [String] {
        [word] + ["s", "ing", "ed"].flatMap { suffix -> [String] in
            guard word.hasSuffix(suffix), word.count - suffix.count >= minWordLength else { return [] }
            let stem = String(word.dropLast(suffix.count))
            guard suffix != "s" else { return [stem] }
            let undoubled = stem.count > minWordLength && stem.suffix(2).first == stem.last ? [String(stem.dropLast())] : []
            return [stem, stem + "e"] + undoubled
        }
    }

    private static func encode(_ visual: WordVisual?) -> String {
        switch visual {
        case .symbol(let name): return "s:\(name)"
        case .emoji(let character): return "e:\(character)"
        case nil: return ""
        }
    }

    private static func decode(_ stored: String) -> WordVisual? {
        if stored.hasPrefix("s:") { return .symbol(String(stored.dropFirst(2))) }
        if stored.hasPrefix("e:") { return .emoji(String(stored.dropFirst(2))) }
        return nil
    }

    /// keyword → SF Symbol, from the search keywords macOS ships for its own symbol picker.
    private static func loadSearchIndex() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: symbolSearchIndex),
              let keywordsBySymbol = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
            log("word visuals: system symbol keywords unavailable, using the built-in table only")
            return [:]
        }
        // Shorter symbol names are the plainer ones ("flame" before "flame.circle.fill"), so they claim keywords first.
        let symbolNames = keywordsBySymbol.keys
            .filter { !$0.contains(".ar") && !$0.contains(".hi") && !$0.contains("rtl") }
            .filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            .sorted { ($0.count, $0) < ($1.count, $1) }
        return symbolNames.reduce(into: [String: String]()) { index, symbol in
            for keyword in keywordsBySymbol[symbol] ?? [] where index[keyword.lowercased()] == nil {
                index[keyword.lowercased()] = symbol
            }
        }
    }
}
