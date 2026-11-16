import AppKit

/// Checks of the pure logic of the window and of the app shell around it, run as part of `--self-check`.
/// Returns what failed.
func gallerySelfCheck() -> [String] {
    (demoSongChecks() + demoLoopChecks() + pinAndLayoutChecks() + playerChecks() + stillPassChecks()).map { "gallery: " + $0 }
        + shellChecks().map { "shell: " + $0 }
}

private struct Checks {
    private(set) var failures: [String] = []

    mutating func check(_ condition: Bool, _ what: String) {
        if !condition { failures.append(what) }
    }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

private func demoSongChecks() -> [String] {
    var checks = Checks()
    let lines = DemoTrack.lyrics.lines
    checks.check(lines.count == 10 && DemoTrack.lines.contains { $0.hasSuffix("?") }, "ten demo lines, one of them a question")
    checks.check(lines.enumerated().allSatisfy { near($1[0].start, 0.8 + 1.75 * Double($0)) }, "demo lines start 1.75 s apart from 0.8 s")
    checks.check(lines.allSatisfy { near(($0.last?.end ?? 0) - $0[0].start, 1.5) }, "every demo line is sung in 1.5 s")
    checks.check(lines.allSatisfy { line in zip(line, line.dropFirst()).allSatisfy { near($0.end, $1.start) } },
                 "demo words follow on without gaps")
    // "Who taught the rain to keep time?": weights 5 8 5 6 4 6 and (4 + 2) × 1.7 = 10.2, total 44.2.
    checks.check(near(lines[4][0].end - lines[4][0].start, 5 * 1.5 / 44.2) && near(lines[4][6].end - lines[4][6].start, 10.2 * 1.5 / 44.2),
                 "demo words are weighted by letters + 2, the last one stretched")
    // A style without history gets its two lines only, so nothing lingers from the line before.
    checks.check(DemoTrack.lyrics(for: .fisheye).lines.map { $0[0].line } == [2, 3]
                 && DemoTrack.lyrics(for: .messages).lines.map { $0[0].line } == [0, 1, 2, 3], "each style is given its own part of the demo song")
    return checks.failures
}

private func demoLoopChecks() -> [String] {
    var checks = Checks()
    let lines = DemoTrack.lyrics.lines
    for style in LyricStyle.allCases {
        let demo = StyleDemo(style: style)
        let first = style.demoFirstLine
        checks.check(first % 2 == 0 && first + 1 < lines.count, "\(style.rawValue) plays a pair of demo lines")
        checks.check(near(demo.window.upperBound - demo.window.lowerBound, 3.95), "\(style.rawValue) loops over 3.95 s")
        checks.check(near(demo.window.lowerBound, lines[first][0].start - 0.2) && near(demo.still, lines[first + 1][0].start + 1.23),
                     "\(style.rawValue) loop starts 0.2 s early and its still is 1.23 s into the second line")
        checks.check(!style.summary.isEmpty && style.palette.count == 4, "\(style.rawValue) has a description and four colours")
    }
    let since = Date(timeIntervalSinceReferenceDate: 1000)
    func at(_ seconds: Double) -> Date { since.addingTimeInterval(seconds) }
    let playing = StyleDemo(style: .ship, playingSince: since)
    checks.check(near(playing.position(at: at(1)), playing.window.lowerBound + 1)
                 && near(playing.position(at: at(3.95 + 1)), playing.window.lowerBound + 1), "a playing demo wraps around its window")
    checks.check(near(playing.opacity(at: at(0.08)), 0.5) && near(playing.opacity(at: at(2)), 1) && near(playing.opacity(at: at(3.95 - 0.12)), 0.5),
                 "the loop fades in over 0.16 s and out over 0.24 s")
    let still = StyleDemo(style: .ship)
    checks.check(near(still.position(at: at(7)), still.still) && still.opacity(at: at(7)) == 1, "a demo that is not playing sits on its still frame")
    return checks.failures
}

private func pinAndLayoutChecks() -> [String] {
    var checks = Checks()
    // Pins: the pure logic only. The setter would write to the real preferences.
    let pins = AppSettings.togglingPin(.web, in: AppSettings.togglingPin(.ship, in: []))
    checks.check(pins == [.ship, .web] && AppSettings.togglingPin(.ship, in: pins) == [.web], "pinning toggles one style in and out")
    checks.check(AppSettings.rawPins(pins) == ["Ship", "Web"] && AppSettings.pins(from: AppSettings.rawPins(pins) + ["No Such Style"]) == pins,
                 "pins round-trip through their stored names, unknown names dropped")
    checks.check(AppSettings.pins(from: []).isEmpty, "nothing is pinned by default")
    let favouriteMenu = AppSettings.menuGroups(favourites: pins, current: .web)
    let otherInUse = AppSettings.menuGroups(favourites: pins, current: .map)
    let plainMenu = AppSettings.menuGroups(favourites: [], current: .ship)
    checks.check(favouriteMenu.map(\.title) == ["Favourites"] && favouriteMenu[0].styles == [.ship, .web]
                 && otherInUse.map(\.title) == ["Favourites", "In Use"] && otherInUse[1].styles == [.map]
                 && plainMenu.map(\.title) == ["Kinetic type", "Motion scenes", "Phone screens"]
                 && plainMenu.flatMap(\.styles) == LyricStyle.allCases,
                 "the menu lists only favourites (and the style in use) when there are any, else every style by category")

    let styles = LyricStyle.allCases
    checks.check(GalleryModel.stepped(from: .ship, by: -1) == styles.last && GalleryModel.stepped(from: styles.last!, by: 1) == .ship
                 && GalleryModel.stepped(from: .fisheye, by: 1) == .visual, "stepping wraps around all the styles")
    // Each category is one unbroken run in gallery order, and the phone screens close it.
    let runs = styles.map(\.category).reduce(into: [String]()) { runs, category in if runs.last != category { runs.append(category) } }
    checks.check(runs == ["Kinetic type", "Motion scenes", "Phone screens"]
                 && styles.filter { $0.category == "Phone screens" }.allSatisfy(\.isPhoneScreen), "categories follow gallery order")
    // Free area 592 − 52 − 156 − 24 − 86 = 274: the lyric band (28 %…84 % of the virtual screen) must land exactly on it.
    let hero = HeroGeometry(heroHeight: 592, style: .ship, mapFillsDisplay: false)
    checks.check(near(hero.offsetY + 0.28 * hero.screenHeight, 86) && near(0.56 * hero.screenHeight, 274) && !hero.framed,
                 "hero: the lyric band fills the free area")
    let fullMap = HeroGeometry(heroHeight: 592, style: .map, mapFillsDisplay: true)
    checks.check(fullMap.framed && near(fullMap.screenHeight, 274) && near(fullMap.offsetY, 86),
                 "hero: a display-filling map is shown as a whole framed screen")
    checks.check(Diagnostics.size(from: "940x620") == CGSize(width: 940, height: 620) && Diagnostics.size(from: "wide") == nil,
                 "render size parsing")
    return checks.failures
}

private func playerChecks() -> [String] {
    var checks = Checks()
    func states(_ health: PlayerHealth) -> [PlayerStep.State] {
        PlayerSteps.connection(player: .spotify, health: health, trackTitle: "Song", otherIsSource: false).map(\.state)
    }
    checks.check(states(.closed) == [.next, .later, .later] && states(.notAsked) == [.done, .next, .later]
                 && states(.denied) == [.done, .blocked, .later] && states(.idle) == [.done, .done, .next]
                 && states(.playing) == [.done, .done, .done], "player steps progress with health")
    let fixes = [PlayerHealth.closed, .notAsked, .unverified, .denied].map {
        PlayerSteps.connection(player: .music, health: $0, trackTitle: nil, otherIsSource: false).compactMap(\.fix)
    }
    checks.check(fixes == [[.open], [.allow], [.checkNow], [.openSettings]], "each player problem offers exactly its own fix")
    // A link nobody watches never probes, so this one stays as it is before its first answer.
    let unprobed = PlayerLink().health(of: .spotify, source: nil, isPlaying: false)
    checks.check(unprobed == .checking && unprobed.label != PlayerHealth.notInstalled.label,
                 "a player that has not been checked yet is not called missing")
    checks.check(states(.checking) == [.later, .later, .later]
                 && PlayerSteps.connection(player: .spotify, health: .checking, trackTitle: nil, otherIsSource: false).allSatisfy { $0.fix == nil },
                 "nothing is asked of the user before the first player check is back")
    checks.check(PlayerSteps.connection(player: .music, health: .idle, trackTitle: nil, otherIsSource: true)[2].detail != nil
                 && PlayerSteps.connection(player: .music, health: .idle, trackTitle: nil, otherIsSource: false)[2].detail == nil,
                 "an idle player explains itself only while the other one is being followed")
    checks.check(PlayerSteps.lyrics(tier: nil, isFetching: true).state == .next && PlayerSteps.lyrics(tier: nil, isFetching: false).state == .blocked
                 && PlayerSteps.lyrics(tier: .wordLevel, isFetching: false).state == .done, "lyric status tells looking, found and none apart")
    checks.check(PlayerSteps.delayReadout(0) == "0 s" && PlayerSteps.delayReadout(3) == "+3 s" && PlayerSteps.delayReadout(-2) == "−2 s"
                 && PlayerSteps.offsetReadout(-0.0) == "0.00 s" && PlayerSteps.offsetReadout(0.25) == "+0.25 s", "timing readouts")
    return checks.failures
}

private func stillPassChecks() -> [String] {
    var checks = Checks()
    let late = StyleStills.lateDataStyles(wordIconsChanged: true)
    checks.check(late == [.visual, .fisheyeVisual, .codestyleVisual, .branches, .money, .notifications, .map],
                 "only the styles with word pictures or map pictures get a later still pass")
    checks.check(StyleStills.lateDataStyles(wordIconsChanged: false) == [.money, .map],
                 "with no new word pictures a later still pass redoes the map-backed styles only")
    checks.check(StyleStills.queue([.map, .ship], adding: [.money, .map]) == [.map, .ship, .money]
                 && StyleStills.queue([], adding: late) == late && StyleStills.queue(LyricStyle.allCases, adding: late) == LyricStyle.allCases,
                 "a later still pass joins the queue without dropping or doubling a style")
    return checks.failures
}

private func shellChecks() -> [String] {
    var checks = Checks()
    let early = Date(timeIntervalSinceReferenceDate: 1000), late = early.addingTimeInterval(0.2)
    checks.check(AppDelegate.yields((late, 10), to: (early, 20)) && !AppDelegate.yields((early, 20), to: (late, 10)),
                 "of two copies the one launched later exits, whatever their process numbers")
    checks.check(AppDelegate.yields((early, 20), to: (early, 10)) != AppDelegate.yields((early, 10), to: (early, 20))
                 && AppDelegate.yields((nil, 20), to: (early, 10)) != AppDelegate.yields((early, 10), to: (nil, 20))
                 && !AppDelegate.yields((nil, 10), to: (nil, 20)), "copies launched at the same instant: exactly one exits, the higher process number")
    let fetchable = ["https://i.scdn.co/image/abc", "HTTPS://i.scdn.co/image/abc"].compactMap(URL.init(string:))
    let refused = ["http://i.scdn.co/image/abc", "file:///etc/hosts", "/etc/hosts", "data:text/plain,x"].compactMap(URL.init(string:))
    checks.check(fetchable.count == 2 && fetchable.allSatisfy(ArtworkColorSync.isFetchable)
                 && refused.count == 4 && !refused.contains(where: ArtworkColorSync.isFetchable), "album art is fetched over https only")
    return checks.failures
}
