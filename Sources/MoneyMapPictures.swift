import AppKit
import Combine
import MapKit

/// Money, part 4: the pictures on the feed's map rows. Each map item shows one of a dozen well-known
/// landmarks as a dark MapKit still. Stills are fetched one at a time, a little before they are needed, and
/// only a handful are kept. Nothing but MapKit touches the network, and the user's location is never asked for.

private enum Shots {
    static let size = CGSize(width: 1000, height: 562)
    static let pitch = 50.0
    static let maxCached = 6
    /// Seconds of song around the playhead whose map items get their pictures.
    static let lookBehind = 30.0, lookAhead = 90.0
    static let retryAfter = 120.0
    // Seconds since any view last asked: a landmark's place in the cache may then go to another, and
    // once nobody has asked for anything for the longer time every picture is let go.
    static let wantedFor = 2.0, releaseAfter = 10.0, releaseCheck = 2.0
    static let salt: UInt64 = 0xD0A1
}

struct MoneyLandmark {
    let name: String
    let latitude: Double
    let longitude: Double
    /// Camera distance in metres.
    let distance: Double

    static let all: [MoneyLandmark] = [
        MoneyLandmark(name: "Eiffel Tower", latitude: 48.8584, longitude: 2.2945, distance: 1400),
        MoneyLandmark(name: "Golden Gate Bridge", latitude: 37.8199, longitude: -122.4783, distance: 3600),
        MoneyLandmark(name: "Colosseum", latitude: 41.8902, longitude: 12.4922, distance: 1100),
        MoneyLandmark(name: "Sydney Harbour", latitude: -33.8568, longitude: 151.2153, distance: 2400),
        MoneyLandmark(name: "Tower Bridge", latitude: 51.5055, longitude: -0.0754, distance: 1500),
        MoneyLandmark(name: "Central Park", latitude: 40.7812, longitude: -73.9665, distance: 5200),
        MoneyLandmark(name: "Shibuya Crossing", latitude: 35.6595, longitude: 139.7005, distance: 900),
        MoneyLandmark(name: "Brandenburg Gate", latitude: 52.5163, longitude: 13.3777, distance: 1200),
        MoneyLandmark(name: "Sagrada Família", latitude: 41.4036, longitude: 2.1744, distance: 1200),
        MoneyLandmark(name: "Sugarloaf Mountain", latitude: -22.9492, longitude: -43.1546, distance: 4200),
        MoneyLandmark(name: "Taj Mahal", latitude: 27.1751, longitude: 78.0421, distance: 1600),
        MoneyLandmark(name: "Table Mountain", latitude: -33.9628, longitude: 18.4098, distance: 9000),
    ]

    /// The landmark of the map item that starts at `seed`.
    static func index(for seed: Double) -> Int {
        Int(seededUnit(seed, salt: Shots.salt) * Double(all.count)) % all.count
    }
}

struct MoneyMapPicture {
    let image: CGImage
    let place: String
}

/// Whether each map row came up as a picture row or as an island. Settled the moment a row (or the pill
/// announcing it) first shows, and kept for as long as it is on screen: a picture that turns up late, a
/// pause or a seek must never turn one kind of row into the other in front of the viewer.
struct MoneyPictureLatch {
    /// One map row as one view draws it. The view is told apart by its canvas: the overlay, the Gallery's
    /// preview and its tiles all draw the same song at different moments.
    struct Row: Hashable {
        let start: Double
        let width: CGFloat
        let height: CGFloat

        init(start: Double, canvas: CGSize) {
            self.start = start
            width = canvas.width
            height = canvas.height
        }
    }

    private static let maxRows = 64

    private var verdicts: [Row: Bool] = [:]

    /// - Parameter isOnScreen: false while the row is still to come, which leaves its verdict open (again).
    /// - Parameter isReady: whether the row's picture is there right now.
    mutating func holds(_ row: Row, isOnScreen: Bool, isReady: Bool) -> Bool {
        guard isOnScreen else {
            verdicts[row] = nil
            return isReady
        }
        if let settled = verdicts[row] { return settled }
        // Only a dozen rows are ever on screen: the one farthest away in the song scrolled off long ago.
        if verdicts.count >= Self.maxRows, let farthest = verdicts.keys.max(by: { abs($0.start - row.start) < abs($1.start - row.start) }) {
            verdicts[farthest] = nil
        }
        verdicts[row] = isReady
        return isReady
    }
}

/// Views watch this to redraw a paused frame when a picture arrives.
@MainActor
final class MoneyMapPictures: ObservableObject {
    static let shared = MoneyMapPictures()

    /// Keyed by landmark index; never more than `Shots.maxCached` entries.
    private var ready: [Int: MoneyMapPicture] = [:]
    /// When each landmark was last near some view's playhead, on the `MapHousekeeping` clock. Several views
    /// can show different songs at once, so no single view's list says what is wanted.
    private var askedAt: [Int: Double] = [:]
    private var running: MKMapSnapshotter?
    /// Counts the snapshots started, so that an answer can be matched to the snapshot it is for.
    private var ticket = 0
    private var isFailing = false
    private var pausedUntil = -Double.infinity
    private let housekeeping = MapHousekeeping()

    private init() {}

    /// The picture for the map item starting at `seed`, if it is there.
    func picture(for seed: Double) -> MoneyMapPicture? { ready[MoneyLandmark.index(for: seed)] }

    /// Called every frame with the start times of a song's map items; cheap unless a picture is missing.
    func prepare(mapStarts: [Double], position: Double) {
        let now = MapHousekeeping.now
        let near = mapStarts.lazy.filter { $0 > position - Shots.lookBehind && $0 < position + Shots.lookAhead }
        // In song order: the rows already on screen come before the ones still ahead.
        let wanted = near.reduce(into: [Int]()) { indices, start in
            let index = MoneyLandmark.index(for: start)
            if indices.count < Shots.maxCached, !indices.contains(index) { indices.append(index) }
        }
        askedAt = askedAt.merging(wanted.map { ($0, now) }) { _, latest in latest }
        startNext(preferring: wanted)
    }

    private func isWanted(_ index: Int, at now: Double) -> Bool { now - askedAt[index, default: -.infinity] < Shots.wantedFor }

    private func startNext(preferring urgent: [Int] = []) {
        let now = MapHousekeeping.now
        guard running == nil, now >= pausedUntil else { return }
        let others = askedAt.keys.filter { isWanted($0, at: now) }.sorted()
        guard let index = (urgent + others).first(where: { ready[$0] == nil }) else { return }
        // A full cache takes a new picture only in place of one that has fallen out of use: two views
        // that between them want more than fit must not evict each other's pictures in turn.
        guard ready.count < Shots.maxCached || ready.keys.contains(where: { !isWanted($0, at: now) }) else { return }
        let snapshotter = MKMapSnapshotter(options: Self.options(for: MoneyLandmark.all[index]))
        ticket += 1
        running = snapshotter
        snapshotter.start(with: .main) { [ticket] snapshot, error in
            let image = snapshot?.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            let failure = (error as NSError?).map { "\($0.domain) \($0.code): \($0.localizedDescription)" }
            MainActor.assumeIsolated { self.finish(ticket, index: index, image: image, failure: failure) }
        }
        // MapKit does not promise to answer; a snapshot that never did would block every later one.
        DispatchQueue.main.asyncAfter(deadline: .now() + MapPatience.seconds) { [ticket] in
            MainActor.assumeIsolated {
                guard ticket == self.ticket else { return }
                self.running?.cancel()
                self.finish(ticket, index: index, image: nil, failure: "no answer within \(Int(MapPatience.seconds)) s")
            }
        }
    }

    private func finish(_ ticket: Int, index: Int, image: CGImage?, failure: String?) {
        // Only the running snapshot counts: one that was given up on may still answer much later, and
        // the wait for one that answered in time still runs out.
        guard running != nil, ticket == self.ticket else { return }
        let now = MapHousekeeping.now
        running = nil
        if let image {
            if isFailing { log("money maps: pictures are arriving again") }
            isFailing = false
            objectWillChange.send()
            ready = Self.fitting(ready.merging([index: MoneyMapPicture(image: image, place: MoneyLandmark.all[index].name)]) { _, new in new },
                                 newest: index, askedAt: askedAt)
            housekeeping.arm(every: Shots.releaseCheck) { [weak self] in self?.releaseIfIdle() ?? false }
        } else {
            // Logged once per outage; until it clears every map row is drawn as an island.
            if !isFailing {
                log("money maps: MapKit gave no picture (\(failure ?? "no image, no error")); map rows fall back to islands, "
                    + "retrying every \(Int(Shots.retryAfter)) s")
            }
            isFailing = true
            pausedUntil = now + Shots.retryAfter
        }
        startNext()
    }

    /// `pictures` cut back to the limit: the one asked for longest ago goes, never the newest.
    private static func fitting(_ pictures: [Int: MoneyMapPicture], newest: Int, askedAt: [Int: Double]) -> [Int: MoneyMapPicture] {
        guard pictures.count > Shots.maxCached else { return pictures }
        let stalest = pictures.keys.filter { $0 != newest }.min { askedAt[$0, default: -.infinity] < askedAt[$1, default: -.infinity] }
        return pictures.filter { $0.key != stalest }
    }

    /// Lets every picture go once no view has asked for a while; answers whether any are left to watch over.
    /// Rows that were showing a picture keep their shape and get it back when a view asks again.
    private func releaseIfIdle() -> Bool {
        guard MapHousekeeping.now - (askedAt.values.max() ?? -.infinity) >= Shots.releaseAfter else { return !ready.isEmpty }
        ready = [:]
        askedAt = [:]
        return false
    }

    private static func options(for landmark: MoneyLandmark) -> MKMapSnapshotter.Options {
        let centre = CLLocationCoordinate2D(latitude: landmark.latitude, longitude: landmark.longitude)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: centre, fromDistance: landmark.distance, pitch: Shots.pitch, heading: 0)
        options.size = Shots.size
        options.appearance = NSAppearance(named: .darkAqua)
        options.preferredConfiguration = configuration
        return options
    }
}
