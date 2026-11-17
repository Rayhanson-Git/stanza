import AppKit

/// Assert-style checks of the pure logic, run by `Stanza --self-check` (build.sh does this after every build).
func runSelfCheck() {
    var failures = 0
    func check(_ condition: Bool, _ what: String) {
        guard !condition else { return }
        failures += 1
        print("FAILED: \(what)")
    }
    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }
    let track = Track(title: "Lanterns (Remastered 2011)", artist: "Harbour Lights & Friends", duration: 266.8)

    // Word-level lyrics
    let wordLevel = LyricsParsing.parseWordLevel("""
        {"t":0,"c":[{"tx":"作词: "},{"tx":"Someone"}]}
        [1000,900](1000,300,0)Paint (1300,200,0)the (1500,400,0)(quiet) (1900,100,0)!
        [5000,500](5000,500,0)Producer: (5500,100,0)Nobody
        [9000,500](9000,500,0)harbour
        """)
    check(wordLevel.map(\.text) == ["Paint", "the", "(quiet)!", "harbour"], "word-level: metadata and credit lines dropped, punctuation glued, brackets kept")
    check(wordLevel.map(\.line) == [0, 0, 0, 1], "word-level: lines numbered without gaps")
    check(near(wordLevel[0].start, 1) && near(wordLevel[0].end, 1.3) && near(wordLevel[2].end, 2.0), "word-level: milliseconds become seconds")

    // Line-level lyrics and interpolation
    let lineLevel = LyricsParsing.parseLineLevel("[00:10.50]hello world\n[00:12.00]\n[01:05.250][00:20.00]bye\n[00:01.00]Lyrics by: X\nplain")
    check(lineLevel.map(\.text) == ["hello world", "bye", "bye"] && near(lineLevel[0].time, 10.5) && near(lineLevel[2].time, 65.25),
          "line-level: tags parsed, repeats expanded, blank/credit/untagged lines dropped")
    let spread = LyricsParsing.interpolate([(time: 10, text: "hello world"), (time: 30, text: "bye")])
    // "hello world": 10 letters → span = min(20, 10 × 0.18 + 1.2) = 3.0 s, split 5:5.
    check(near(spread[0].start, 10) && near(spread[1].start, 11.5) && near(spread[1].end, 13), "interpolation: capped span split by letter count")
    check(near(spread[2].end - spread[2].start, 3 * 0.18 + 1.2), "interpolation: last line uses the default length cap")

    // Matching
    check(LyricsParsing.normalize("Lanterns (feat. Someone) [Live] - 2011 Remaster") == "lanterns", "normalize strips title noise")
    check(LyricsParsing.isCredit("作曲 : Chris") && !LyricsParsing.isCredit("I said: stay"), "credit detection")
    check(TrackMatch.sameSong(title: "Lanterns", artists: ["Harbour Lights"], as: track), "match: same title, shared artist word")
    check(!TrackMatch.sameSong(title: "Lanternsmith", artists: ["Harbour Lights"], as: track), "match: whole words only")
    check(!TrackMatch.sameSong(title: "Lanterns", artists: ["Someone Else"], as: track), "match: artist must overlap")
    check(TrackMatch.durationMatches(268, track) && !TrackMatch.durationMatches(411, track), "match: duration tolerance")
    let mixed = [TimedWord(text: "hello", start: 0, end: 1, line: 0), TimedWord(text: "你好", start: 0.1, end: 1, line: 1),
                 TimedWord(text: "彩虹", start: 5, end: 6, line: 2)]
    check(LyricsParsing.dropTranslationLines(mixed, track: track).map(\.text) == ["hello", "彩虹"],
          "a Chinese line paired in time with an original line is a translation; one standing alone is lyrics")
    let duet = LyricsParsing.parseWordLevel("[1000,3000](1000,500,0)a (2000,500,0)b (3000,500,0)c\n[1800,1000](1800,400,0)x (2300,400,0)y")
    check(TimedLyrics(tier: .wordLevel, words: duet).lines.map { $0.map(\.text) } == [["a", "b", "c"], ["x", "y"]], "overlapping lines stay whole")
    let odd = LyricsParsing.parseLineLevel("[00:12.5]half\n[００:２０.００]fullwidth digits\n[00:30.00]<00:30.00>tagged <00:30.50>words")
    check(odd.map(\.text) == ["half", "tagged words"] && near(odd[0].time, 12.5), "line-level: short fractions, non-ASCII digits ignored, inline word tags stripped")
    check(LyricsParsing.normalize("(Say It Twice)") == "say it twice", "a title that is all 'noise' keeps its words")
    check(!TrackMatch.sameSong(title: "Harbour", artists: ["The Lamplights"], as: Track(title: "Harbour", artist: "The Tidewaters", duration: 0)),
          "match: sharing only 'the' is not the same artist")

    // Timeline
    let lyrics = TimedLyrics(tier: .wordLevel, words: wordLevel)
    check(lyrics.lines.count == 2 && lyrics.activeLine(at: 0.5) == nil, "timeline: nothing before the first word")
    check(lyrics.activeLine(at: 1.4)?.shown == 2 && lyrics.activeLine(at: 2.5)?.index == 0, "timeline: shown count and linger")
    check(lyrics.activeLine(at: 2.0 + Timing.lineLinger + 0.01) == nil && lyrics.activeLine(at: 9.1)?.index == 1, "timeline: gap, then next line")
    check(near(wordLevel[0].progress(at: 1.15), 0.5), "timeline: progress within a word")
    let decoded = try? JSONDecoder().decode(TimedLyrics.self, from: JSONEncoder().encode(lyrics))
    check(decoded == lyrics, "cache format round-trips")
    let anchor = Anchor(position: 10, date: Date(timeIntervalSince1970: 100), rate: 1)
    check(near(anchor.position(at: Date(timeIntervalSince1970: 102.5)), 12.5) && near(Anchor.idle.position(at: Date()), 0), "anchor extrapolation")

    // Colours
    check(NSColor(hex: "#FF8000B3")?.hexString == "#FF8000B3" && NSColor(hex: "#12345") == nil, "hex colours round-trip, bad input rejected")
    let artwork = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
        NSColor.darkGray.setFill()
        rect.fill()
        NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 3, height: 8).fill()
        return true
    }
    let accent = artwork.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap(AccentExtractor.accent(of:))
    check((accent?.redComponent ?? 0) > 0.7 && (accent?.greenComponent ?? 1) < 0.3, "accent prefers the vivid colour over the larger grey area")

    // Word pictures
    check(WordVisuals.key("Burnin'") == "burnin" && WordVisuals.variants("burning").contains("burn") && WordVisuals.variants("eyes").contains("eye")
          && WordVisuals.variants("stopped").contains("stop"), "word stems")

    // Styles
    for failure in webStyleSelfCheck() + messagesStyleSelfCheck() + notificationsStyleSelfCheck() + mapStyleSelfCheck()
        + moneyStyleSelfCheck() + calendarStyleSelfCheck() + voiceMemoStyleSelfCheck() {
        check(false, failure)
    }
    let duetLyrics = TimedLyrics(tier: .wordLevel, words: duet)
    if let second = duetLyrics.activeLine(at: 2.35) {
        let context = StyleContext(line: second, lyrics: duetLyrics, position: 2.35, clock: 0, canvas: CGSize(width: 1440, height: 900),
                                   band: 504, settings: AppSettings.shared)
        check(second.index == 1 && duetLyrics.words[context.newestWordIndex].text == "y", "newest word is found inside the active line of a duet")
    } else {
        check(false, "duet: second line should be active at 2.35 s")
    }
    // Cards kept up through gaps dim like Messages (sample lines start at 1, 5, 9, 13, 15.5 and 30 s).
    func gapPresence(at time: Double) -> Double? {
        Diagnostics.sampleLyrics.line(at: time, alwaysDrawn: true).map {
            StyleContext(line: $0, lyrics: Diagnostics.sampleLyrics, position: time, clock: 0, canvas: CGSize(width: 1440, height: 900),
                         band: 504, settings: AppSettings.shared).gapPresence
        }
    }
    check(gapPresence(at: 16).map { near($0, 1) } == true && gapPresence(at: 25).map { near($0, 0.55) } == true
          && gapPresence(at: 28.5).map { near($0, 1) } == true && gapPresence(at: 45).map { near($0, 0) } == true,
          "gap dimming: full while sung, 55% deep in a gap, awake before the next line, gone after the last")
    let sky = ConstellationMap(seed: 1, width: 1440, band: 504, textScale: 1)
    check(sky.stars.count == 14 && sky.stars == ConstellationMap(seed: 1, width: 1440, band: 504, textScale: 1).stars
          && sky.edges.filter { $0.to - $0.from == 1 }.count == 13, "constellation layout: 14 stars, chained, the same every time")

    for style in LyricStyle.allCases { check(LyricStyle(rawValue: style.rawValue) == style, "style \(style.rawValue) round-trips") }

    for failure in gallerySelfCheck() { check(false, failure) }

    // Lettering: South Asian scripts and Urdu are recognised, Arabic, Chinese and English are not; Roman means Latin.
    check(LyricsScript.isSouthAsian("तुम ही हो") && LyricsScript.isSouthAsian("আমার সোনার বাংলা") && LyricsScript.isSouthAsian("دل ہے")
          && !LyricsScript.isSouthAsian("قلبي") && !LyricsScript.isSouthAsian("我爱你") && !LyricsScript.isSouthAsian("tum hi ho"),
          "lyrics script: South Asian scripts and Urdu are told apart from the rest")
    check(LyricsScript.isRoman("[00:19.00] Kevain tenu mei dikhaawan") && LyricsScript.isRoman("Dil hai, chhota sa")
          && !LyricsScript.isRoman("तुम ही हो") && !LyricsScript.isRoman("আমার সোনার") && !LyricsScript.isRoman("[00:01.00]"),
          "lyrics script: English-letter versions are recognised")
    check(LyricsScript.joinsLetters("আমার") && LyricsScript.joinsLetters("तुम") && LyricsScript.joinsLetters("دل")
          && !LyricsScript.joinsLetters("harbour") && !LyricsScript.joinsLetters("我爱你"),
          "lyrics script: joined scripts are kept whole, separate letters are not")

    // Moving the lyrics: any move on screen or a little past an edge is kept, a wild one stops half a screen out, and
    // zero stays the middle.
    let corner = Layout.clampedOffset(CGPoint(x: -0.55, y: -0.6))
    check(near(corner.x, -0.55) && near(corner.y, -0.6), "lyric offset: a move into a corner, even a little past it, is kept")
    let wild = Layout.clampedOffset(CGPoint(x: 5, y: -5))
    check(near(Layout.defaultCentre.x + wild.x, 1 + Layout.overshoot) && near(Layout.defaultCentre.y + wild.y, -Layout.overshoot),
          "lyric offset: a wild move stops half a screen past the edge")
    check(Layout.clampedOffset(.zero) == .zero, "lyric offset: zero is the middle")

    // Login launch: only the open-app event flagged as a login item keeps the window closed.
    let openEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
    check(!LoginItem.launchedAtLogin(openEvent), "launch: an ordinary open still shows the window")
    check(!LoginItem.launchedAtLogin(nil), "launch: no event means the window shows")
    let asProperty = openEvent.copy() as! NSAppleEventDescriptor
    asProperty.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: keyAEPropData)
    check(LoginItem.launchedAtLogin(asProperty), "launch: a login-item open (flag as the property) keeps the window closed")
    openEvent.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(keyAELaunchedAsLogInItem))
    check(LoginItem.launchedAtLogin(openEvent), "launch: a login-item open (flag as a parameter) keeps the window closed")

    guard failures == 0 else {
        print("self-check: \(failures) failure(s)")
        exit(1)
    }
    print("self-check passed")
}
