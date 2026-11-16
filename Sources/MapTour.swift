import AppKit
import Combine
import MapKit
import simd

/// Ground positions are local metres: x east and y north of the city centre.
typealias MapPoint = SIMD2<Double>

// MARK: City and maths

enum MapCity {
    static let centre = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    static let metresPerLatitude = 110_574.0, metresPerLongitude = 87_989.937
    static let name = "San Francisco"
    /// Outside this box a leg turns back toward the centre instead of wandering on.
    static let box = CGRect(x: -5600, y: -3600, width: 6900, height: 6000)
    /// Places a walk may begin, each with the compass heading it sets off on.
    static let starts: [(latitude: Double, longitude: Double, heading: Double)] = [
        (37.7936, -122.3965, 225), (37.7880, -122.4075, 270), (37.7650, -122.4197, 180), (37.7699, -122.4469, 270),
        (37.7626, -122.4352, 90), (37.7763, -122.4328, 0), (37.8009, -122.4244, 180), (37.7807, -122.4721, 90),
        (37.7989, -122.4099, 200), (37.7786, -122.3893, 250),
    ]

    static func metres(_ coordinate: CLLocationCoordinate2D) -> MapPoint {
        MapPoint((coordinate.longitude - centre.longitude) * metresPerLongitude,
                 (coordinate.latitude - centre.latitude) * metresPerLatitude)
    }

    static func coordinate(_ point: MapPoint) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centre.latitude + point.y / metresPerLatitude,
                               longitude: centre.longitude + point.x / metresPerLongitude)
    }
}

enum MapMath {
    static func smoothstep(_ value: Double) -> Double {
        let unit = min(1, max(0, value))
        return unit * unit * (3 - 2 * unit)
    }

    /// Compass bearing in degrees (0 north, 90 east).
    static func bearing(from start: MapPoint, to end: MapPoint) -> Double {
        atan2(end.x - start.x, end.y - start.y) * 180 / .pi
    }

    /// The signed change from one bearing to another, within -180...180; positive is a right turn.
    static func turn(from start: Double, to end: Double) -> Double {
        let change = (end - start).truncatingRemainder(dividingBy: 360)
        return change > 180 ? change - 360 : (change < -180 ? change + 360 : change)
    }

    static func step(from start: MapPoint, bearing: Double, metres: Double) -> MapPoint {
        let radians = bearing * .pi / 180
        return start + metres * MapPoint(sin(radians), cos(radians))
    }

    /// An underdamped spring settling from 0 to 1.
    static func spring(_ time: Double, decay: Double, rate: Double) -> Double {
        time <= 0 ? 0 : 1 - exp(-decay * time) * (cos(rate * time) + decay / rate * sin(rate * time))
    }
}

/// A song's random source: FNV-1a of its key, then one SplitMix-style draw per salt.
struct MapSeed: Equatable {
    let value: UInt64

    init(key: String) {
        value = key.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }

    func unit(_ salt: UInt64) -> Double {
        let mixed = value &+ salt &* 0x9E37_79B9_7F4A_7C15
        let folded = (mixed ^ (mixed >> 31)) &* 0x94D0_49BB_1331_11EB
        return Double((folded ^ (folded >> 29)) % 100_000) / 100_000
    }
}

// MARK: Roads

/// One leg's walking route.
struct MapRoad: Equatable {
    struct Bend: Equatable {
        /// Metres from the start of the road.
        let at: Double
        /// Degrees; positive turns right.
        let angle: Double
        let street: String?
    }

    /// A named manoeuvre from the directions, used to label nearby bends.
    struct Signpost {
        let at: MapPoint
        let street: String
    }

    private enum Rules {
        static let bendFromStart = 20.0, bendFromEnd = 15.0, bendSpacing = 25.0
        static let bendDegrees = 40.0, bearingWindow = 16.0, signpostReach = 50.0
    }

    let points: [MapPoint]
    /// The share of the road's length reached at each point.
    let shares: [Double]
    let metres: Double
    let bends: [Bend]
    /// The street the road starts on.
    let street: String?

    init?(points raw: [MapPoint], signposts: [Signpost]) {
        let points = raw.reduce(into: [MapPoint]()) { kept, point in
            if kept.last != point { kept.append(point) }
        }
        let along = points.indices.reduce(into: [Double]()) { sums, index in
            sums.append(index == 0 ? 0 : sums[index - 1] + simd_distance(points[index - 1], points[index]))
        }
        guard points.count >= 2, let metres = along.last, metres > 0 else { return nil }
        self.points = points
        self.metres = metres
        shares = along.map { $0 / metres }
        street = signposts.first?.street
        bends = Self.bends(points: points, along: along, signposts: signposts)
    }

    var heading: Double { MapMath.bearing(from: points[0], to: points[points.count - 1]) }

    func point(at share: Double) -> MapPoint { Self.locate(points, marks: shares, at: share) }

    /// The part of the road between two shares of its length.
    func stretch(from start: Double, to end: Double) -> [MapPoint] {
        [point(at: start)] + zip(points, shares).filter { $0.1 > start && $0.1 < end }.map(\.0) + [point(at: end)]
    }

    /// The point where the running total `marks` reaches `mark`.
    private static func locate(_ points: [MapPoint], marks: [Double], at mark: Double) -> MapPoint {
        guard let next = marks.firstIndex(where: { $0 >= mark }) else { return points[points.count - 1] }
        guard next > 0 else { return points[0] }
        let progress = (mark - marks[next - 1]) / (marks[next] - marks[next - 1])
        return simd_mix(points[next - 1], points[next], MapPoint(repeating: progress))
    }

    private static func bends(points: [MapPoint], along: [Double], signposts: [Signpost]) -> [Bend] {
        let metres = along[along.count - 1]
        return points.indices.dropFirst().dropLast().reduce(into: [Bend]()) { bends, index in
            let at = along[index], corner = points[index]
            guard at >= Rules.bendFromStart, metres - at > Rules.bendFromEnd,
                  at - (bends.last?.at ?? -.infinity) >= Rules.bendSpacing else { return }
            // Bearings over a stretch of road, not between neighbouring vertices, so a corner drawn
            // with several close points still counts as one turn.
            let before = locate(points, marks: along, at: at - Rules.bearingWindow)
            let after = locate(points, marks: along, at: at + Rules.bearingWindow)
            let angle = MapMath.turn(from: MapMath.bearing(from: before, to: corner), to: MapMath.bearing(from: corner, to: after))
            guard abs(angle) >= Rules.bendDegrees else { return }
            let nearest = signposts.min { simd_distance($0.at, corner) < simd_distance($1.at, corner) }
            let street = nearest.flatMap { simd_distance($0.at, corner) <= Rules.signpostReach ? $0.street : nil }
            bends.append(Bend(at: at, angle: angle, street: street))
        }
    }

    /// The street an instruction such as "Turn right onto Fell St toward Gough St" leads to.
    static func streetName(in instruction: String) -> String? {
        guard let marker = [" onto ", " on "].compactMap({ instruction.range(of: $0) }).first else { return nil }
        let tail = instruction[marker.upperBound...]
        let name = tail.range(of: " toward ").map { tail[..<$0.lowerBound] } ?? tail
        let lowered = name.lowercased()
        // "The destination is on your left", "Continue on the path": directions, not streets.
        guard !name.isEmpty, !lowered.hasPrefix("your "), !lowered.hasPrefix("the ") else { return nil }
        return String(name)
    }
}

/// Where a leg sets off from and which way it turns. Pure, so a song always takes the same walk.
struct MapLegPlan {
    private enum Rules {
        static let smallestTurn = 30.0, turnRange = 70.0
        static let steepestWayHome = 120.0
        static let retryGentler = 0.3, retryWiderOutside = 25.0
        static let nudge = 45.0
    }

    private enum Salt {
        static let startSpot: UInt64 = 5
        static func turnSize(_ leg: Int) -> UInt64 { UInt64(8 * leg + 2) }
        static func turnSide(_ leg: Int) -> UInt64 { UInt64(8 * leg + 3) }
    }

    let start: MapPoint
    let heading: Double
    let turn: Double
    let outside: Bool
    let span: Double

    /// - Parameter previous: the road this leg continues from; nil starts at a seeded place.
    /// - Parameter nudge: how often this leg has already come up empty; each time swings the turn further,
    ///   so a walker boxed in by water or a park finds a way out instead of asking the same thing again.
    init(leg: Int, seed: MapSeed, span: Double, previous: MapRoad?, nudge: Int) {
        if let previous, let last = previous.points.last {
            start = last
            heading = previous.heading
        } else {
            let spot = MapCity.starts[(Int(seed.unit(Salt.startSpot) * Double(MapCity.starts.count)) + leg) % MapCity.starts.count]
            start = MapCity.metres(CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude))
            heading = spot.heading
        }
        let size = seed.unit(Salt.turnSize(leg)) * Rules.turnRange + Rules.smallestTurn
        let wander = seed.unit(Salt.turnSide(leg)) >= 0.5 ? size : -size
        let home = MapMath.turn(from: heading, to: MapMath.bearing(from: start, to: .zero))
        outside = !MapCity.box.contains(CGPoint(x: start.x, y: start.y))
        turn = (outside ? min(max(home, -Rules.steepestWayHome), Rules.steepestWayHome) : wander) + Double(nudge) * Rules.nudge
        self.span = span
    }

    /// Where to ask directions to; later attempts try the other side, then a gentler turn.
    func destination(attempt: Int) -> MapPoint {
        let variant: Double
        switch (outside, attempt) {
        case (true, _): variant = turn + Double(attempt) * Rules.retryWiderOutside
        case (false, 1): variant = -turn
        case (false, 2): variant = turn * Rules.retryGentler
        default: variant = turn
        }
        return MapMath.step(from: start, bearing: heading + variant, metres: span)
    }
}

// MARK: Stills

/// A plane-to-plane projection, used to lay ground positions onto a (possibly tilted) map picture.
struct MapLens {
    /// Ground corners, as multiples of the reach, in the order `init(reach:corners:)` expects their images.
    static let square: [MapPoint] = [MapPoint(-1, -1), MapPoint(1, -1), MapPoint(1, 1), MapPoint(-1, 1)]
    /// The sine of the slimmest angle two sides of the pictured square may meet at: flatter than this and
    /// the corners are as good as on one line, which would solve to an enormous, useless projection.
    private static let slimmestCorner = 0.001
    /// Depth at or below this is at or behind the camera.
    private static let nearestDepth = 1e-6

    let matrix: simd_double3x3

    init(matrix: simd_double3x3) { self.matrix = matrix }

    /// The projection that carries a ground square of half-side `reach`, centred on the origin, onto
    /// four picture points (unit-square-to-quadrilateral mapping, after Heckbert).
    init?(reach: Double, corners: [MapPoint]) {
        guard corners.count == Self.square.count, reach > 0, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let first = corners[0], second = corners[1], third = corners[2], fourth = corners[3]
        let sideA = second - third, sideB = fourth - third, skew = first - second + third - fourth
        let determinant = sideA.x * sideB.y - sideB.x * sideA.y
        guard abs(determinant) > Self.slimmestCorner * simd_length(sideA) * simd_length(sideB) else { return nil }
        let g = (skew.x * sideB.y - sideB.x * skew.y) / determinant
        let h = (sideA.x * skew.y - skew.x * sideA.y) / determinant
        let fromUnitSquare = simd_double3x3(rows: [
            SIMD3(second.x - first.x + g * second.x, fourth.x - first.x + h * fourth.x, first.x),
            SIMD3(second.y - first.y + g * second.y, fourth.y - first.y + h * fourth.y, first.y),
            SIMD3(g, h, 1),
        ])
        let toUnitSquare = simd_double3x3(rows: [SIMD3(0.5 / reach, 0, 0.5), SIMD3(0, 0.5 / reach, 0.5), SIMD3(0, 0, 1)])
        let solved = fromUnitSquare * toUnitSquare
        // Pictures are laid out through the inverse, so the projection has to have one.
        guard solved.determinant.isFinite, solved.determinant != 0 else { return nil }
        matrix = solved
    }

    static func translation(_ offset: MapPoint) -> MapLens {
        MapLens(matrix: simd_double3x3(rows: [SIMD3(1, 0, offset.x), SIMD3(0, 1, offset.y), SIMD3(0, 0, 1)]))
    }

    static func scale(_ factor: Double) -> MapLens {
        MapLens(matrix: simd_double3x3(diagonal: SIMD3(factor, factor, 1)))
    }

    static func * (outer: MapLens, inner: MapLens) -> MapLens { MapLens(matrix: outer.matrix * inner.matrix) }

    var inverse: MapLens { MapLens(matrix: matrix.inverse) }

    /// Nil for a point at or behind the camera: dividing by its depth would mirror it into the picture.
    func callAsFunction(_ point: MapPoint) -> MapPoint? {
        let image = matrix * SIMD3(point.x, point.y, 1)
        return image.z > Self.nearestDepth ? MapPoint(image.x, image.y) / image.z : nil
    }

    /// The same projection for Core Animation, which multiplies row vectors and keeps depth in the third row.
    var transform3D: CATransform3D {
        var transform = CATransform3DIdentity
        transform.m11 = matrix[0][0]; transform.m12 = matrix[0][1]; transform.m14 = matrix[0][2]
        transform.m21 = matrix[1][0]; transform.m22 = matrix[1][1]; transform.m24 = matrix[1][2]
        transform.m41 = matrix[2][0]; transform.m42 = matrix[2][1]; transform.m44 = matrix[2][2]
        return transform
    }
}

/// A crossing of the grid that map pictures are taken on.
struct MapNode: Hashable {
    static let spacing = 300.0
    let x: Int
    let y: Int

    var centre: MapPoint { MapPoint(Double(x), Double(y)) * Self.spacing }

    static func nearest(to point: MapPoint) -> MapNode {
        MapNode(x: Int((point.x / spacing).rounded()), y: Int((point.y / spacing).rounded()))
    }

    /// The four crossings around a point.
    static func around(_ point: MapPoint) -> [MapNode] {
        let x = Int((point.x / spacing).rounded(.down)), y = Int((point.y / spacing).rounded(.down))
        return [MapNode(x: x, y: y), MapNode(x: x + 1, y: y), MapNode(x: x, y: y + 1), MapNode(x: x + 1, y: y + 1)]
    }
}

/// How the map pictures are taken. Pictures made for one look are useless for another.
struct MapLook: Equatable {
    private enum Rules {
        static let windowStill = CGSize(width: 1643, height: 977), windowUnit = 1.1
        static let displayStill = CGSize(width: 1989, height: 1228), displayUnit = 1.0
        static let pointsPerMetre = 1.2                         // per still unit, at the picture's centre
        static let halfFieldOfView = 15.0 * Double.pi / 180     // MapKit's camera
        static let tiltDegrees = 50.0
        // Pixels kept per still point, however sharp the screen. A window still is 26 MB at 2; the
        // whole-display look is a backdrop behind the lock screen's clock and is kept at 1 (10 MB, not 39).
        static let windowSharpness = 2.0, displaySharpness = 1.0
        /// Pixels that the pictures of every tour may take together: about 120 MB at four bytes each.
        static let pictureBudget = 30_000_000.0
        static let mostStills = 9
    }

    /// Picture size in points; larger than the map on screen so the camera can drift between grid crossings.
    let still: CGSize
    /// Screen units per still point, before the display's own scale.
    let stillUnit: Double
    /// The most pixels per still point a picture is kept at.
    let sharpest: Double
    let tilted: Bool

    init(fillsDisplay: Bool, tilted: Bool) {
        still = fillsDisplay ? Rules.displayStill : Rules.windowStill
        stillUnit = fillsDisplay ? Rules.displayUnit : Rules.windowUnit
        sharpest = fillsDisplay ? Rules.displaySharpness : Rules.windowSharpness
        self.tilted = tilted
    }

    var distance: Double { still.height / 2 / tan(Rules.halfFieldOfView) / (stillUnit * Rules.pointsPerMetre) }
    var pitch: Double { tilted ? Rules.tiltDegrees : 0 }

    /// The pixels one picture takes at its sharpest.
    var stillPixels: Double { still.width * still.height * sharpest * sharpest }

    /// How many pictures one tour may hold while `tours` of them are being drawn and the pictures of resting
    /// tours take `taken` pixels: an equal share of what is left of the budget. Bigger pictures, fewer of them.
    func stillLimit(sharedBy tours: Int, besides taken: Double = 0) -> Int {
        min(Rules.mostStills, max(1, Int((Rules.pictureBudget - taken) / stillPixels) / max(tours, 1)))
    }
}

struct MapStill {
    let picture: CGImage
    /// Ground metres relative to the still's grid crossing → still points, y down.
    let lens: MapLens
}

enum MapFailure: Error, CustomStringConvertible {
    case noRoute, noPicture, noLens, noReply, timedOut

    var description: String {
        switch self {
        case .noReply: return "MapKit returned neither a result nor an error"
        case .timedOut: return "MapKit did not answer within \(Int(MapPatience.seconds)) s"
        case .noRoute: return "no walkable route of about the right length"
        case .noPicture: return "the snapshot had no picture"
        case .noLens: return "the snapshot's corners do not span a plane"
        }
    }
}

// MARK: MapKit requests

/// How long any MapKit request (directions or a snapshot) is waited for before it counts as failed.
enum MapPatience {
    static let seconds = 45.0
}

/// Runs a check every few seconds for as long as the check answers true. Views stop asking for map
/// pictures without saying goodbye, so idle pictures can only be found by looking now and then.
@MainActor
final class MapHousekeeping {
    /// Seconds since boot: idleness is measured on a clock that the user cannot set.
    static var now: Double { ProcessInfo.processInfo.systemUptime }

    private var isArmed = false

    func arm(every interval: Double, while check: @escaping @MainActor () -> Bool) {
        guard !isArmed else { return }
        isArmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            MainActor.assumeIsolated {
                self?.isArmed = false
                if check() { self?.arm(every: interval, while: check) }
            }
        }
    }
}

/// Waits for one MapKit callback. MapKit does not promise to call back after cancel() (the snapshotter
/// never does) or at all, so cancelling and running out of patience both end the wait here; the lock lets
/// only the first result through, and a late callback is dropped.
private final class MapReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var waiter: CheckedContinuation<Result<Value, Error>, Never>?

    func settle(_ value: Value?, _ error: Error?) {
        settle(value.map(Result.success) ?? .failure(error ?? MapFailure.noReply))
    }

    private func settle(_ outcome: Result<Value, Error>) {
        let waiting: CheckedContinuation<Result<Value, Error>, Never>? = lock.withLock {
            guard result == nil else { return nil }
            result = outcome
            defer { waiter = nil }
            return waiter
        }
        waiting?.resume(returning: outcome)
    }

    func value(start: () -> Void, cancel: @escaping @Sendable () -> Void) async throws -> Value {
        // Without this, one request that MapKit never answers would hold up every later one.
        let patience = Task {
            try? await Task.sleep(for: .seconds(MapPatience.seconds))
            guard !Task.isCancelled else { return }
            cancel()
            self.settle(.failure(MapFailure.timedOut))
        }
        defer { patience.cancel() }
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let early = lock.withLock { () -> Result<Value, Error>? in
                    if result == nil { waiter = continuation }
                    return result
                }
                if let early { return continuation.resume(returning: early) }
                start()
                // A cancel that landed just before start() had nothing to stop yet.
                if Task.isCancelled { cancel() }
            }
        } onCancel: {
            cancel()
            settle(.failure(CancellationError()))
        }
        return try outcome.get()
    }
}

@MainActor
private enum MapService {
    private enum Rules {
        static let longestDetour = 2.4, detourSlack = 80.0       // a leg may be this much longer than planned
        static let lensReach = 320.0
    }

    /// Walking directions, or nil when there are none short enough to pass for the planned stroll.
    static func walk(from start: MapPoint, to end: MapPoint, span: Double) async throws -> MapRoad? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: MapCity.coordinate(start)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: MapCity.coordinate(end)))
        request.transportType = .walking
        let directions = MKDirections(request: request)
        let reply = MapReply<MKDirections.Response>()
        do {
            let response = try await reply.value(start: { directions.calculate { reply.settle($0, $1) } },
                                                 cancel: { directions.cancel() })
            guard let route = response.routes.first, route.distance < span * Rules.longestDetour + Rules.detourSlack,
                  route.polyline.pointCount >= 2 else { return nil }
            return road(from: route)
        } catch let error as MKError where error.code == .directionsNotFound {
            return nil
        }
    }

    private static func road(from route: MKRoute) -> MapRoad? {
        func points(_ line: MKPolyline) -> [MapPoint] {
            (0..<line.pointCount).map { MapCity.metres(line.points()[$0].coordinate) }
        }
        // A step's instruction is carried out where its own stretch of road ends.
        let signposts = route.steps.compactMap { step -> MapRoad.Signpost? in
            guard let name = MapRoad.streetName(in: step.instructions), let at = points(step.polyline).last else { return nil }
            return MapRoad.Signpost(at: at, street: name)
        }
        return MapRoad(points: points(route.polyline), signposts: signposts)
    }

    /// A dark picture of the streets around a grid crossing, with the lens that locates ground points on it.
    static func still(at node: MapNode, look: MapLook, heading: Double) async throws -> MapStill {
        let options = MKMapSnapshotter.Options()
        options.camera = MKMapCamera(lookingAtCenter: MapCity.coordinate(node.centre), fromDistance: look.distance,
                                     pitch: look.pitch, heading: heading)
        options.size = look.still
        options.appearance = NSAppearance(named: .darkAqua)
        let streets = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
        streets.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = streets
        let snapshotter = MKMapSnapshotter(options: options)
        let reply = MapReply<MKMapSnapshotter.Snapshot>()
        let snapshot = try await reply.value(start: { snapshotter.start { reply.settle($0, $1) } },
                                             cancel: { snapshotter.cancel() })
        let corners = MapLens.square.map { corner -> MapPoint in
            let spot = snapshot.point(for: MapCity.coordinate(node.centre + corner * Rules.lensReach))
            return MapPoint(spot.x, look.still.height - spot.y)     // AppKit measures y upward
        }
        guard let lens = MapLens(reach: Rules.lensReach, corners: corners) else { throw MapFailure.noLens }
        let sharpness = min(look.sharpest, NSScreen.screens.map(\.backingScaleFactor).max() ?? 1)
        guard let picture = picture(from: snapshot.image, size: look.still, sharpness: sharpness) else { throw MapFailure.noPicture }
        return MapStill(picture: picture, lens: lens)
    }

    /// The snapshot as a bitmap of `sharpness` pixels per point. AppKit draws it at the size asked for;
    /// should it ever hand back more pixels than that, they are scaled down so the picture budget holds.
    private static func picture(from image: NSImage, size: CGSize, sharpness: Double) -> CGImage? {
        let width = Int((size.width * sharpness).rounded()), height = Int((size.height * sharpness).rounded())
        let pixels = CGRect(x: 0, y: 0, width: width, height: height)
        var proposed = pixels
        guard let drawn = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        guard drawn.width > width, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return drawn }
        canvas.interpolationQuality = .high
        canvas.draw(drawn, in: pixels)
        return canvas.makeImage() ?? drawn
    }
}

// MARK: Tour

/// One song's roads and map pictures, fetched a little ahead of the music. The style reads it every frame
/// and tells it which leg is playing and which grid crossings the camera is heading for; the tour tells the
/// style's views when a road or picture has arrived, so that a paused frame fills in as well.
@MainActor
final class MapTour: ObservableObject {
    private enum Rules {
        static let remembered = 2
        static let legsAhead = 5, legsBack = 3
        static let attempts = 3
        static let bendWorthSpan = 200.0        // on legs this long a route with a turn is worth one more try
        static let failuresBeforePause = 6
        static let backOff = 1.2, pause = 20.0
        static let headingSalt: UInt64 = 9
        // Seconds since a view last asked for the tour: first it stops fetching, then it lets its pictures go.
        static let idleStop = 2.0, idleRelease = 10.0, releaseCheck = 2.0
    }

    private enum Need {
        case road(Int), still(MapNode)

        var label: String {
            switch self {
            case .road(let leg): return "directions for leg \(leg)"
            case .still(let node): return "picture \(node.x),\(node.y)"
            }
        }
    }

    private enum Outcome {
        case fetched, failed, throttled
    }

    private static var recent: [MapTour] = []
    private static let housekeeping = MapHousekeeping()

    /// The tour for a song. Several views can be drawing different songs in the same moment (the overlay
    /// and the Gallery's previews), so asking for one tour never disturbs another: a tour winds down by
    /// itself once nobody has asked for it for a while. The roads of an idle song are kept for a quick return.
    static func tour(for plan: MapPlan) -> MapTour {
        let now = MapHousekeeping.now
        let known = recent.first { $0.song == plan.song }
        if let known, known.isAsked(now) {
            known.lastAsked = now
            return known
        }
        let tour = known ?? MapTour(plan: plan)
        tour.lastAsked = now
        // Older tours make way, longest unasked first, but never one that a view is still drawing.
        let others = recent.filter { $0 !== tour }.sorted { $0.lastAsked > $1.lastAsked }
        let kept = max(Rules.remembered - 1, others.prefix { $0.isAsked(now) }.count)
        others.dropFirst(kept).forEach { $0.reset() }
        recent = [tour] + others.prefix(kept)
        // One more tour is being drawn, so every tour's share of the picture budget has shrunk.
        for other in recent {
            if other.isAsked(now) { other.trim() } else { other.rest() }
        }
        return tour
    }

    /// Winds down the tours no view has asked for lately; answers whether any pictures are left to watch over.
    private static func restIdle() -> Bool {
        let now = MapHousekeeping.now
        recent.filter { now - $0.lastAsked >= Rules.idleRelease }.forEach { $0.rest() }
        return recent.contains { $0.stills.count > 1 }
    }

    let song: String
    private let seed: MapSeed
    private let spans: [Double]
    /// One compass heading for every picture of the song, so the camera only ever pans.
    private let heading: Double

    private(set) var roads: [Int: MapRoad] = [:]
    private(set) var stills: [MapNode: MapStill] = [:]
    /// The lens of the newest picture; every picture of one look shares it, give or take rounding.
    private(set) var lens: MapLens?
    /// Bumped whenever running work is abandoned, so a late result is recognised and dropped.
    private(set) var revision = 0

    private var look: MapLook?
    /// Legs that begin at a seeded place instead of continuing the road before them.
    private var starts: Set<Int> = [0]
    /// How often each leg found no usable route; the next try swings its turn further round.
    private var deadEnds: [Int: Int] = [:]
    private var leg = 0
    private var nodes: [MapNode] = []
    private var work: Task<Void, Never>?
    /// When a view last asked for or drew this tour, and when fetching may resume, on the `MapHousekeeping` clock.
    private var lastAsked = -Double.infinity
    private var blockedUntil = -Double.infinity
    private var isPaused = false
    private var hasPictures = false

    private init(plan: MapPlan) {
        song = plan.song
        seed = plan.seed
        spans = plan.spans
        heading = Double(Int(plan.seed.unit(Rules.headingSalt) * 360))
    }

    /// Called every frame: what is playing and where the camera will be. Starts fetching if something is missing.
    func update(look: MapLook, leg: Int, nodes: [MapNode]) {
        if look != self.look {
            reset()
            self.look = look
        }
        self.leg = min(max(leg, 0), spans.count - 1)
        self.nodes = nodes
        // A paused view draws again only when something arrives; that keeps its tour going until it is complete.
        lastAsked = MapHousekeeping.now
        trim()
        guard work == nil, lastAsked > blockedUntil, nextNeed() != nil else { return }
        if isPaused {
            isPaused = false
            log("map: tour resumed")
        }
        work = Task { [revision] in await self.run(revision) }
    }

    private func isAsked(_ now: Double) -> Bool { now - lastAsked < Rules.idleStop }

    /// Abandons running work and lets the pictures go; the roads are kept.
    private func reset() {
        work?.cancel()
        work = nil
        revision += 1
        stills = [:]
        lens = nil
    }

    /// What a tour nobody draws keeps: the one picture under its camera. A view that comes back to it
    /// (playback resumed, a Gallery still drawn again) then has a map at once instead of bare ground
    /// while the others are fetched anew.
    private func rest() {
        guard stills.count > 1 else { return }
        stills = stills.filter { $0.key == nodes.first }
    }

    /// How many pictures this tour may hold: its look's share of what the idle tours leave of the budget.
    private var stillLimit: Int {
        guard let look else { return 0 }
        let now = MapHousekeeping.now
        let others = Self.recent.filter { $0 !== self }
        let resting = others.filter { !$0.isAsked(now) }
        let taken = resting.reduce(0) { $0 + Double($1.stills.count) * ($1.look?.stillPixels ?? 0) }
        return look.stillLimit(sharedBy: others.count - resting.count + 1, besides: taken)
    }

    /// Lets go of pictures beyond the tour's share: those the camera is not heading for, farthest away first.
    private func trim() {
        guard stills.count > 1 else { return }
        let limit = stillLimit
        guard stills.count > limit else { return }
        let wanted = nodes.prefix(limit), home = nodes.first?.centre ?? .zero
        let spare = stills.keys.filter { !wanted.contains($0) }
            .sorted { simd_distance($0.centre, home) > simd_distance($1.centre, home) }
        let dropped = Set(spare.prefix(stills.count - limit))
        stills = stills.filter { !dropped.contains($0.key) }
    }

    /// Roads first, from the nearest known leg up to a few legs ahead, then the pictures the camera needs.
    private func nextNeed() -> Need? {
        let anchor = anchorLeg()
        let last = max(anchor, min(leg + Rules.legsAhead, spans.count - 1))
        if let missing = (anchor...last).first(where: { roads[$0] == nil }) { return .road(missing) }
        return nodes.prefix(stillLimit).first { stills[$0] == nil }.map(Need.still)
    }

    private func anchorLeg() -> Int {
        let earliest = max(0, leg - Rules.legsBack)
        if let known = (earliest...leg).last(where: { roads[$0] != nil || starts.contains($0) }) { return known }
        // A seek landed far from any road: the walk begins again here rather than catching up leg by leg.
        starts.insert(leg)
        return leg
    }

    /// One request at a time, until nothing is missing, no view is asking any more, or MapKit keeps failing.
    private func run(_ revision: Int) async {
        var failures = 0
        while revision == self.revision, isAsked(MapHousekeeping.now), let need = nextNeed() {
            let outcome = await fetch(need)
            guard revision == self.revision else { return }
            if outcome == .fetched {
                failures = 0
                continue
            }
            failures += 1
            // Being told to slow down is answered with quiet at once; other failures get a few quick retries first.
            if outcome == .throttled || failures >= Rules.failuresBeforePause {
                blockedUntil = MapHousekeeping.now + Rules.pause
                isPaused = true
                log("map: \(outcome == .throttled ? "MapKit is throttling requests" : "no directions or pictures"), "
                    + "pausing the tour for \(Int(Rules.pause)) s")
                break
            }
            try? await Task.sleep(for: .seconds(Double(failures) * Rules.backOff))
        }
        if revision == self.revision { work = nil }
    }

    private func fetch(_ need: Need) async -> Outcome {
        let revision = self.revision
        do {
            switch need {
            case .road(let leg):
                let road = try await buildRoad(for: leg)
                guard revision == self.revision else { return .failed }
                objectWillChange.send()
                roads[leg] = road
            case .still(let node):
                guard let look else { return .failed }
                let still = try await MapService.still(at: node, look: look, heading: heading)
                guard revision == self.revision else { return .failed }
                keep(still, at: node)
            }
            return .fetched
        } catch is CancellationError {
            return .failed
        } catch {
            let detail = error as NSError
            log("map: \(need.label) failed: \(error is MapFailure ? "\(error)" : "\(detail.domain) \(detail.code) \(detail.localizedDescription)")")
            return (error as? MKError)?.code == .loadingThrottled ? .throttled : .failed
        }
    }

    private func buildRoad(for leg: Int) async throws -> MapRoad {
        let plan = MapLegPlan(leg: leg, seed: seed, span: spans[leg], previous: starts.contains(leg) ? nil : roads[leg - 1],
                              nudge: deadEnds[leg, default: 0])
        var straight: MapRoad?
        for attempt in 0..<Rules.attempts {
            let road = try await MapService.walk(from: plan.start, to: plan.destination(attempt: attempt), span: plan.span)
            // A straight road was already found; this was its one chance to be beaten by a road with a turn.
            if let straight { return road.map { $0.bends.isEmpty ? straight : $0 } ?? straight }
            guard let road else { continue }
            if road.bends.isEmpty, plan.span > Rules.bendWorthSpan {
                straight = road
                continue
            }
            return road
        }
        guard let straight else {
            deadEnds[leg, default: 0] += 1
            throw MapFailure.noRoute
        }
        return straight
    }

    private func keep(_ still: MapStill, at node: MapNode) {
        objectWillChange.send()
        stills[node] = still
        lens = still.lens
        if !hasPictures {
            hasPictures = true
            log("map: tour under way")
        }
        trim()
        Self.housekeeping.arm(every: Rules.releaseCheck) { MapTour.restIdle() }
    }
}
