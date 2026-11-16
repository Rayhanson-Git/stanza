import MapKit
import SwiftUI
import simd

/// Map: the song is a turn-by-turn walk across San Francisco. Every lyric line is one leg of real walking
/// directions; the puck moves on as each word is sung and the lyric is the navigation banner. Nothing is
/// animated by SwiftUI: each frame is a function of the playback position, the wall clock and whatever
/// roads and map pictures `MapTour` has fetched so far.
struct MapStyle: View {
    let context: StyleContext

    var body: some View {
        if let plan = MapPlan.cached(for: context.lyrics) {
            MapTourView(context: context, plan: plan, tour: MapTour.tour(for: plan))
        }
    }

    /// For the diagnostic renderer: whether the roads and the picture this frame needs have arrived.
    static func isReady(_ context: StyleContext) -> Bool { MapScene(context: context)?.isComplete ?? true }
}

/// One frame of one song's tour. Its timeline redraws it while the song plays; watching the tour redraws
/// it when a road or a picture arrives, which is the only thing that fills in a paused frame.
private struct MapTourView: View {
    let context: StyleContext
    let plan: MapPlan
    @ObservedObject var tour: MapTour

    var body: some View {
        let scene = MapScene(context: context, plan: plan, tour: tour)
        if scene.presence > Metrics.hiddenBelow {
            MapSceneView(scene: scene)
        }
    }
}

/// Lengths are design units unless noted; one unit is `MapLayout.unit` points.
private enum Metrics {
    // Frame
    static let designWidth = 874.0, designHeight = 468.0, designBand = 402.0
    static let widthFit = 0.92, bandFit = 0.96
    static let windowMargin = 14.0, displayMargin = 34.0
    static let windowCorner = 36.0, windowStroke = 0.6, windowStrokeOpacity = 0.16
    static let shadowOpacity = 0.4, shadowRadius = 18.0, shadowY = 6.0          // points
    /// Where the camera's ground point sits in the map, as shares of its width and height.
    static let focus = MapPoint(0.55, 0.60)
    /// Whole-display mode thins out toward the top and bottom, where the lock screen keeps its clock and buttons.
    static let keepsClear: [(opacity: Double, at: Double)] = [(0.14, 0), (0.14, 0.174), (1, 0.28), (1, 0.82), (0.22, 0.89), (0.22, 1)]

    // Timing
    static let fadeDelay = 5.0, fadeLength = 2.5, hiddenBelow = 0.002           // after the last word
    static let cameraStep = 0.4, cameraReach = 4                                // the camera averages the puck over ±1.6 s
    static let lookAhead = [3.0, 6.0]

    // Map pictures
    static let blendFrom = 0.72, blendSpan = 0.28, blendMost = 0.5

    // Route
    static let legsShown = 8, routeReach = 900.0                                // metres from the camera
    static let casingWidth = 10.0, routeWidth = 6.6, aheadWidth = 7.0
    static let aheadOpacity = 0.55, aheadFade = 0.35

    // Puck
    static let puckRadius = 10.5, puckDotRadius = 7.6, haloRadius = 21.0
    static let haloOpacity = 0.24, haloSwell = 0.07, haloSpeed = 2.4
    static let puckShadowOpacity = 0.35, puckShadowRadius = 3.0, puckShadowY = 1.0
}

private enum Pin {
    static let size = 30.0
    /// A balloon on a point, in multiples of `size`, with the tip at the origin.
    static let shape: Path = {
        let tip = Path { path in
            path.move(to: CGPoint(x: -0.2, y: -0.37))
            path.addLine(to: .zero)
            path.addLine(to: CGPoint(x: 0.2, y: -0.37))
            path.closeSubpath()
        }
        return tip.union(Path(ellipseIn: CGRect(x: -0.5, y: -1.3, width: 1, height: 1))).applying(CGAffineTransform(scaleX: size, y: size))
    }()
    static let glossTop = -39.0, glossBottom = -9.0, glossOpacity = 0.28
    static let glyph = "mappin", glyphSize = 13.8, glyphY = -24.0
    static let groundShadow = CGRect(x: -8, y: -2.2, width: 16, height: 4.4), groundShadowOpacity = 0.35
    static let shadowOpacity = 0.4, shadowRadius = 3.0, shadowY = 2.0
    static let dropDelay = 0.05, dropDecay = 7.997, dropRate = 11.83
    static let plainFade = 0.2                                                  // entrance when motion is reduced
    static let bounceLength = 3.0, bounceHeight = 6.0, bounceDamping = 0.17, bounceRate = 12.0
    static let ringLength = 0.7, ringStart = 8.0, ringGrowth = 40.0, ringFlattening = 0.5, ringWidth = 2.0
    static let previousFade = 0.4
}

private enum Banner {
    static let width = 322.0, widthShare = 0.56, corner = 22.0, padding = 14.0
    static let smallestText = 0.8, largestText = 1.5, largestArrow = 1.25
    static let arrowSize = 30.0, arrowColumn = 48.0, arrowGap = 10.0
    static let lyricSize = 27.0, rowHeight = 1.16, wordSpace = 0.26             // the last two are per font size
    static let detailSize = 16.0, detailHeight = 20.0, detailGap = 5.0, detailSpace = 7.0
    static let fadeIn = 0.12
    static let popLength = 1.2, popDecay = 9.0, popRate = 14.0, popFrom = 0.6, popRise = 0.3
    static let wobbleDegrees = 5.0, wobbleRate = 14.0
    static let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
    static let distances: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    static func symbol(turning angle: Double) -> String {
        let side = angle < 0 ? "left" : "right"
        switch abs(angle) {
        case ..<30: return "arrow.up"
        case ..<60: return "arrow.up.\(side)"
        case ..<140: return "arrow.turn.up.\(side)"
        default: return "arrow.uturn.\(side)"
        }
    }

    /// Greedy line breaking: the row and leading edge of each word.
    static func place(widths: [Double], space: Double, limit: Double) -> [(row: Int, x: Double)] {
        widths.reduce(into: [(row: Int, x: Double)]()) { spots, width in
            guard let last = spots.last else { return spots.append((0, 0)) }
            let x = last.x + widths[spots.count - 1] + space
            spots.append(x + width > limit ? (last.row + 1, 0) : (last.row, x))
        }
    }
}

private enum Eta {
    static let width = 250.0, height = 56.0, corner = 18.0
    static let valueSize = 20.0, valueY = 20.0, captionSize = 12.0, captionY = 41.0
    static let metresPerKilometre = 1000.0, metresPerMile = 1609.344
    static let clock = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
}

private enum Paint {
    static let ground = Color(red: 0.13, green: 0.17, blue: 0.24)
    static let casing = Color(red: 0, green: 0.27, blue: 0.72)
    static let route = Color(red: 0.04, green: 0.52, blue: 1)
    static let ahead = Color(red: 0.55, green: 0.76, blue: 1)
    static let pin = Color(red: 1, green: 0.271, blue: 0.227)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.118).opacity(0.94)
    static let hairline = Color.white.opacity(0.1), hairlineWidth = 0.6
    static let caption = Color.white.opacity(0.62)
}

// MARK: Plan

/// The song as a walk: one leg per lyric line, longer lines walking further.
struct MapPlan {
    struct Line {
        let start: Double
        let end: Double
        let words: [TimedWord]
    }

    private enum Rules {
        static let metresPerWord = 38.0, shortestLeg = 130.0, longestLeg = 480.0
        static let announceDelay = 0.3          // the next leg appears this long after a line ends
        static let shortestWord = 0.14
    }

    /// Tells one song's tour from another's: it covers every word, its line and its timing.
    let song: String
    let seed: MapSeed
    let lines: [Line]
    /// Metres walked on each leg.
    let spans: [Double]
    /// When each leg's pin and banner appear.
    let announced: [Double]
    let end: Double

    init?(lyrics: TimedLyrics) {
        guard let first = lyrics.words.first, let last = lyrics.words.last else { return nil }
        let lines = lyrics.lines.map { Line(start: $0[0].start, end: $0[$0.count - 1].end, words: $0) }
        // The walk is seeded by a few facts about the song only, so that a song keeps the walk it always had.
        let walk = "map|\(lyrics.words.count)|\(first.start)|\(last.end)|\(first.text)"
        seed = MapSeed(key: walk)
        let everyWord = lyrics.words.map { "\($0.text)\u{1}\($0.line)\u{1}\($0.start)\u{1}\($0.end)" }.joined(separator: "\n")
        song = "\(walk)|\(MapSeed(key: everyWord).value)"
        self.lines = lines
        spans = lines.map { min(max(Double($0.words.count) * Rules.metresPerWord, Rules.shortestLeg), Rules.longestLeg) }
        announced = lines.indices.map { $0 == 0 ? 0 : min(lines[$0].start, lines[$0 - 1].end + Rules.announceDelay) }
        end = last.end
    }

    func leg(at time: Double) -> Int { announced.lastIndex { $0 <= time } ?? 0 }

    /// How much of a leg has been walked: every word moves the puck on while it is sung.
    func walked(leg: Int, at time: Double) -> Double {
        let line = lines[leg]
        guard time > line.start else { return 0 }
        guard time < line.end else { return 1 }
        let sung = line.words.reduce(0) { $0 + MapMath.smoothstep((time - $1.start) / max(Rules.shortestWord, $1.end - $1.start)) }
        return sung / Double(line.words.count)
    }
}

extension MapPlan {
    private static let maxCached = 3
    @MainActor private static let songs = SongCache<MapPlan?>(limit: maxCached)

    /// The plan for these lyrics, made once per song: the style asks for it on every frame.
    @MainActor
    static func cached(for lyrics: TimedLyrics) -> MapPlan? {
        songs.value(for: lyrics) { MapPlan(lyrics: lyrics) }
    }
}

/// Where the puck and the camera are at any moment, given the roads known so far.
private struct MapTrack {
    let plan: MapPlan
    let roads: [Int: MapRoad]

    func dot(at time: Double) -> MapPoint? {
        let leg = plan.leg(at: time)
        return roads[leg]?.point(at: plan.walked(leg: leg, at: time))
    }

    /// A moving average of the puck, so the map pans smoothly while the puck moves word by word.
    func camera(at time: Double) -> MapPoint? {
        let dots = (-Metrics.cameraReach...Metrics.cameraReach).compactMap { dot(at: time + Double($0) * Metrics.cameraStep) }
        return dots.isEmpty ? nil : dots.reduce(.zero, +) / Double(dots.count)
    }
}

// MARK: Scene

struct MapLayout {
    let unit: Double
    /// The map's size in points: a window, or the whole display.
    let size: CGSize
    let margin: Double
    let fillsDisplay: Bool
    let look: MapLook

    init(canvas: CGSize, band: Double, fillsDisplay: Bool, tilted: Bool) {
        let unit = min(Metrics.widthFit * canvas.width / Metrics.designWidth, Metrics.bandFit * band / Metrics.designBand)
        self.unit = unit
        size = fillsDisplay ? canvas : CGSize(width: Metrics.designWidth * unit, height: Metrics.designHeight * unit)
        margin = (fillsDisplay ? Metrics.displayMargin : Metrics.windowMargin) * unit
        self.fillsDisplay = fillsDisplay
        look = MapLook(fillsDisplay: fillsDisplay, tilted: tilted)
    }
}

/// Ground metres → points in the map view, for a camera looking at one ground point.
private struct MapProjection {
    let camera: MapPoint
    private let lens: MapLens
    /// Still points → map points.
    private let screen: MapLens

    init?(lens: MapLens, camera: MapPoint, layout: MapLayout) {
        guard let centre = lens(.zero) else { return nil }
        let scale = layout.unit / layout.look.stillUnit
        let focus = MapPoint(layout.size.width, layout.size.height) * Metrics.focus
        self.lens = lens
        self.camera = camera
        screen = .translation(focus - scale * centre) * .scale(scale)
    }

    /// Nil for ground behind the camera, which has no place on the map.
    func point(_ ground: MapPoint) -> CGPoint? {
        guard let spot = lens(ground - camera).flatMap({ screen($0) }) else { return nil }
        return CGPoint(x: spot.x, y: spot.y)
    }

    /// Lays a picture taken over `node` under this camera: back to the ground, across, and out through the lens again.
    func transform(for still: MapStill, at node: MapNode) -> CATransform3D {
        (screen * lens * .translation(node.centre - camera) * still.lens.inverse).transform3D
    }
}

struct MapTile {
    let picture: CGImage
    let transform: CATransform3D
    let opacity: Double
}

/// One frame: the song's timing plus a snapshot of what the tour has fetched. Plain values, so drawing is pure.
struct MapScene {
    let position: Double
    let clock: Double
    let textScale: Double
    let reduceMotion: Bool
    let plan: MapPlan
    let layout: MapLayout
    let leg: Int
    let walked: Double
    let roads: [Int: MapRoad]
    let dot: MapPoint?
    let tiles: [MapTile]
    /// False while the roads or the picture under the camera are still on their way.
    let isComplete: Bool
    private let projection: MapProjection?

    /// For callers outside the style's views: looks the song's plan and tour up itself.
    @MainActor
    init?(context: StyleContext) {
        guard let plan = MapPlan.cached(for: context.lyrics) else { return nil }
        self.init(context: context, plan: plan, tour: MapTour.tour(for: plan))
    }

    @MainActor
    init(context: StyleContext, plan: MapPlan, tour: MapTour) {
        let settings = context.settings, time = context.position
        let layout = MapLayout(canvas: context.canvas, band: context.band, fillsDisplay: settings.mapFillsDisplay, tilted: settings.mapIn3D)
        let track = MapTrack(plan: plan, roads: tour.roads)
        let camera = track.camera(at: time)
        let soon = Metrics.lookAhead.compactMap { track.camera(at: time + $0) }
        let nodes = ([camera].compactMap { $0 } + soon).map(MapNode.nearest).reduce(into: [MapNode]()) { kept, node in
            if !kept.contains(node) { kept.append(node) }
        }
        tour.update(look: layout.look, leg: plan.leg(at: time), nodes: nodes)

        position = time
        clock = context.clock
        textScale = settings.textScale
        reduceMotion = settings.reduceMotion
        self.plan = plan
        self.layout = layout
        leg = plan.leg(at: time)
        walked = plan.walked(leg: leg, at: time)
        roads = tour.roads
        dot = track.dot(at: time)
        let lens = tour.lens, stills = tour.stills
        let projection = camera.flatMap { camera in lens.flatMap { MapProjection(lens: $0, camera: camera, layout: layout) } }
        self.projection = projection
        tiles = projection.map { Self.tiles(from: stills, under: $0) } ?? []
        isComplete = camera.map { stills[MapNode.nearest(to: $0)] != nil } ?? false
    }

    /// Fades the map out a few seconds after the last word.
    var presence: Double { 1 - MapMath.smoothstep((position - plan.end - Metrics.fadeDelay) / Metrics.fadeLength) }

    /// Bottom to top: the runner-up picture, which fills whatever the nearest leaves bare at the map's edge;
    /// the nearest picture; and the runner-up again, blended in as the camera nears the border between the two
    /// so that the hand-over never pops.
    private static func tiles(from stills: [MapNode: MapStill], under projection: MapProjection) -> [MapTile] {
        let camera = projection.camera
        let near = Set(MapNode.around(camera))
            .compactMap { node in stills[node].map { (node: node, still: $0, distance: simd_distance(node.centre, camera)) } }
            .sorted { $0.distance < $1.distance }
        func tile(_ index: Int, opacity: Double) -> MapTile {
            MapTile(picture: near[index].still.picture, transform: projection.transform(for: near[index].still, at: near[index].node), opacity: opacity)
        }
        guard near.count > 1 else { return near.indices.map { tile($0, opacity: 1) } }
        let closeness = near[0].distance / max(near[1].distance, .ulpOfOne)
        let blend = Metrics.blendMost * MapMath.smoothstep((closeness - Metrics.blendFrom) / Metrics.blendSpan)
        return [tile(1, opacity: 1), tile(0, opacity: 1)] + (blend > 0 ? [tile(1, opacity: blend)] : [])
    }
}

private struct MapSceneView: View {
    let scene: MapScene

    var body: some View {
        let layout = scene.layout
        let map = Paint.ground
            .frame(width: layout.size.width, height: layout.size.height)
            .overlay(alignment: .topLeading) { pictures }
            .overlay { Canvas { graphics, _ in scene.drawWalk(in: graphics) } }
        let chrome = Canvas { graphics, _ in scene.drawChrome(in: graphics) }
        if layout.fillsDisplay {
            let stops = Metrics.keepsClear.map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.at) }
            // Only the map is thinned out: the banner carries the lyric and has to stay readable.
            map.clipped()
                .mask(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
                .overlay(chrome)
                .opacity(scene.presence)
                // The style is centred on the lyric band; the whole-display map belongs centred on the screen.
                .offset(y: (0.5 - Layout.bandTop - Layout.bandHeight / 2) * layout.size.height)
        } else {
            let frame = RoundedRectangle(cornerRadius: Metrics.windowCorner * layout.unit, style: .continuous)
            map.overlay(chrome)
                .clipShape(frame)
                .overlay(frame.strokeBorder(Color.white.opacity(Metrics.windowStrokeOpacity), lineWidth: max(1, Metrics.windowStroke * layout.unit)))
                .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius, y: Metrics.shadowY)
                .opacity(scene.presence)
        }
    }

    private var pictures: some View {
        let still = scene.layout.look.still
        return ZStack(alignment: .topLeading) {
            ForEach(scene.tiles.indices, id: \.self) { layer in
                let tile = scene.tiles[layer]
                Image(decorative: tile.picture, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: still.width, height: still.height)
                    .projectionEffect(ProjectionTransform(tile.transform))
                    .opacity(tile.opacity)
            }
        }
        .frame(width: scene.layout.size.width, height: scene.layout.size.height, alignment: .topLeading)
    }
}

// MARK: Drawing the walk

private func disc(at centre: CGPoint, radius: Double) -> Path {
    Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
}

private func rounded(_ width: Double) -> StrokeStyle { StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }

extension MapScene {
    /// The route, pins and puck. Without a picture there is no lens to place them on the ground.
    func drawWalk(in graphics: GraphicsContext) {
        guard let projection else { return }
        drawRoute(in: graphics, projection)
        drawPins(in: graphics, projection)
        drawPuck(in: graphics, projection)
    }

    private var sinceAnnounced: Double { position - plan.announced[leg] }

    private func drawRoute(in graphics: GraphicsContext, _ projection: MapProjection) {
        let unit = layout.unit
        if let road = roads[leg] {
            let fade = MapMath.smoothstep(sinceAnnounced / Metrics.aheadFade)
            graphics.stroke(path(along: [road.stretch(from: walked, to: 1)], projection),
                            with: .color(Paint.ahead.opacity(Metrics.aheadOpacity * fade)), style: rounded(Metrics.aheadWidth * unit))
        }
        // Finished legs in full and the current one as far as the puck; a leg without a road breaks the line.
        let legs = (max(0, leg - Metrics.legsShown)...leg).map { $0 == leg ? roads[$0]?.stretch(from: 0, to: walked) : roads[$0]?.points }
        let trail = path(along: legs.split { $0 == nil }.map { $0.flatMap { $0 ?? [] } }, projection)
        graphics.stroke(trail, with: .color(Paint.casing), style: rounded(Metrics.casingWidth * unit))
        graphics.stroke(trail, with: .color(Paint.route), style: rounded(Metrics.routeWidth * unit))
    }

    private func path(along runs: [[MapPoint]], _ projection: MapProjection) -> Path {
        Path { path in
            for run in runs {
                var isDrawing = false
                for point in run {
                    guard simd_distance(point, projection.camera) <= Metrics.routeReach, let spot = projection.point(point) else {
                        isDrawing = false
                        continue
                    }
                    if isDrawing { path.addLine(to: spot) } else { path.move(to: spot) }
                    isDrawing = true
                }
            }
        }
    }

    private func drawPins(in graphics: GraphicsContext, _ projection: MapProjection) {
        // A leg can end behind a tilted camera; such a pin is left out rather than mirrored onto the map.
        if leg > 0, sinceAnnounced < Pin.previousFade, let reached = roads[leg - 1]?.points.last.flatMap(projection.point) {
            drawPin(in: graphics, at: reached, scale: 1, lift: 0, opacity: 1 - sinceAnnounced / Pin.previousFade)
        }
        guard let spot = roads[leg]?.points.last.flatMap(projection.point) else { return }
        let unit = layout.unit
        let arrived = position - plan.lines[leg].end
        if (0..<Pin.ringLength).contains(arrived) {
            let progress = arrived / Pin.ringLength
            let radius = (Pin.ringStart + Pin.ringGrowth * (1 - pow(1 - progress, 3))) * unit
            let ring = CGRect(x: spot.x - radius, y: spot.y - radius * Pin.ringFlattening, width: 2 * radius, height: 2 * radius * Pin.ringFlattening)
            graphics.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(1 - progress)), lineWidth: Pin.ringWidth * unit)
        }
        let landing = sinceAnnounced - Pin.dropDelay
        guard !reduceMotion else {
            return drawPin(in: graphics, at: spot, scale: 1, lift: 0, opacity: min(1, max(0, landing / Pin.plainFade)))
        }
        let bounces = (0..<Pin.bounceLength).contains(arrived)
        let hop = bounces ? abs(exp(-Pin.bounceDamping * Pin.bounceRate * arrived) * sin(Pin.bounceRate * arrived)) : 0
        drawPin(in: graphics, at: spot, scale: MapMath.spring(landing, decay: Pin.dropDecay, rate: Pin.dropRate),
                lift: Pin.bounceHeight * hop, opacity: 1)
    }

    private func drawPin(in graphics: GraphicsContext, at spot: CGPoint, scale: Double, lift: Double, opacity: Double) {
        guard scale > 0, opacity > 0 else { return }
        var ground = graphics
        ground.opacity = opacity
        ground.translateBy(x: spot.x, y: spot.y)
        ground.scaleBy(x: layout.unit * scale, y: layout.unit * scale)
        ground.fill(Path(ellipseIn: Pin.groundShadow), with: .color(.black.opacity(Pin.groundShadowOpacity)))
        var pin = ground
        pin.translateBy(x: 0, y: -lift)
        pin.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(Pin.shadowOpacity), radius: Pin.shadowRadius, y: Pin.shadowY))
            layer.fill(Pin.shape, with: .color(Paint.pin))
        }
        var gloss = pin
        gloss.clip(to: Pin.shape)
        gloss.fill(Path(Pin.shape.boundingRect),
                   with: .linearGradient(Gradient(colors: [.white.opacity(Pin.glossOpacity), .white.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: Pin.glossTop), endPoint: CGPoint(x: 0, y: Pin.glossBottom)))
        pin.draw(Text(Image(systemName: Pin.glyph)).font(.system(size: Pin.glyphSize, weight: .semibold)).foregroundStyle(.white),
                 at: CGPoint(x: 0, y: Pin.glyphY))
    }

    private func drawPuck(in graphics: GraphicsContext, _ projection: MapProjection) {
        guard let spot = dot.flatMap(projection.point) else { return }
        let unit = layout.unit
        let swell = reduceMotion ? 1 : 1 + Metrics.haloSwell * sin(Metrics.haloSpeed * clock)
        graphics.fill(disc(at: spot, radius: Metrics.haloRadius * swell * unit), with: .color(Paint.route.opacity(Metrics.haloOpacity)))
        graphics.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(Metrics.puckShadowOpacity), radius: Metrics.puckShadowRadius, y: Metrics.puckShadowY))
            layer.fill(disc(at: spot, radius: Metrics.puckRadius * unit), with: .color(.white))
        }
        graphics.fill(disc(at: spot, radius: Metrics.puckDotRadius * unit), with: .color(Paint.route))
    }
}

// MARK: Drawing the banner and the arrival card

private struct MapGuidance {
    let symbol: String
    let metres: Double
    let street: String
}

extension MapScene {
    /// The next turn on this leg, or the rest of the leg once the last turn is behind.
    private var guidance: MapGuidance {
        guard let road = roads[leg] else {
            return MapGuidance(symbol: Banner.symbol(turning: 0), metres: plan.spans[leg] * (1 - walked), street: MapCity.name)
        }
        let done = walked * road.metres
        guard let next = road.bends.first(where: { $0.at > done }) else {
            return MapGuidance(symbol: Banner.symbol(turning: 0), metres: road.metres - done,
                               street: road.bends.last?.street ?? road.street ?? MapCity.name)
        }
        return MapGuidance(symbol: Banner.symbol(turning: next.angle), metres: next.at - done, street: next.street ?? MapCity.name)
    }

    func drawChrome(in graphics: GraphicsContext) {
        drawBanner(in: graphics)
        drawArrival(in: graphics)
    }

    private func drawCard(_ card: CGRect, corner: Double, in graphics: GraphicsContext) {
        let shape = Path(roundedRect: card, cornerRadius: corner, style: .continuous)
        graphics.fill(shape, with: .color(Paint.card))
        graphics.stroke(shape, with: .color(Paint.hairline), lineWidth: Paint.hairlineWidth * layout.unit)
    }

    private func drawBanner(in graphics: GraphicsContext) {
        let unit = layout.unit, scale = min(max(textScale, Banner.smallestText), Banner.largestText)
        let fontSize = Banner.lyricSize * scale * unit, rowHeight = (fontSize * Banner.rowHeight).rounded()
        let arrowScale = min(scale, Banner.largestArrow) * unit
        let pad = Banner.padding * unit, gutter = Banner.arrowColumn * arrowScale
        let width = min(Banner.widthShare * layout.size.width, Banner.width * scale * unit)
        // The whole line is laid out up front, so words keep their place as the rest of the line arrives.
        let words = plan.lines[leg].words
        let labels = words.map { graphics.resolve(Text($0.text).font(.system(size: fontSize, weight: .bold)).foregroundStyle(.white)) }
        let widths = labels.map { Double($0.measure(in: Banner.unbounded).width) }
        let spots = Banner.place(widths: widths, space: fontSize * Banner.wordSpace, limit: width - 2 * pad - gutter)
        let rows = Double((spots.last?.row ?? 0) + 1)
        let card = CGRect(x: layout.margin, y: layout.margin, width: width,
                          height: 2 * pad + rows * rowHeight + (Banner.detailGap + Banner.detailHeight) * unit)
        drawCard(card, corner: Banner.corner * unit, in: graphics)
        let guide = guidance
        graphics.draw(Text(Image(systemName: guide.symbol)).font(.system(size: Banner.arrowSize * arrowScale, weight: .bold)).foregroundStyle(.white),
                      at: CGPoint(x: card.minX + pad + (gutter - Banner.arrowGap * unit) / 2, y: card.midY))
        let left = card.minX + pad + gutter, top = card.minY + pad
        for (index, word) in words.enumerated() where word.start <= position {
            let centre = CGPoint(x: left + spots[index].x + widths[index] / 2, y: top + (Double(spots[index].row) + 0.5) * rowHeight)
            drawWord(labels[index], at: centre, age: position - word.start, rise: rowHeight * Banner.popRise, in: graphics)
        }
        drawDetail(guide, in: CGRect(x: left, y: top + rows * rowHeight + Banner.detailGap * unit,
                                     width: width - 2 * pad - gutter, height: Banner.detailHeight * unit), graphics)
    }

    /// A sung word, popping up as it arrives.
    private func drawWord(_ label: GraphicsContext.ResolvedText, at centre: CGPoint, age: Double, rise: Double, in graphics: GraphicsContext) {
        var pen = graphics
        pen.opacity = min(1, age / Banner.fadeIn)
        pen.translateBy(x: centre.x, y: centre.y)
        if !reduceMotion, age < Banner.popLength {
            let settled = MapMath.spring(age, decay: Banner.popDecay, rate: Banner.popRate)
            let size = Banner.popFrom + (1 - Banner.popFrom) * settled
            pen.translateBy(x: 0, y: (1 - settled) * rise)
            pen.scaleBy(x: size, y: size)
            pen.rotate(by: .degrees(Banner.wobbleDegrees * sin(Banner.wobbleRate * age) * pow(1 - age / Banner.popLength, 2)))
        }
        pen.draw(label, at: .zero)
    }

    /// Distance to the next turn and the street it leads onto.
    private func drawDetail(_ guide: MapGuidance, in row: CGRect, _ graphics: GraphicsContext) {
        let font = Font.system(size: Banner.detailSize * layout.unit, weight: .semibold).monospacedDigit()
        let distance = graphics.resolve(Text(Banner.distances.string(fromDistance: guide.metres)).font(font).foregroundStyle(.white))
        let taken = distance.measure(in: Banner.unbounded).width + Banner.detailSpace * layout.unit
        graphics.draw(distance, at: CGPoint(x: row.minX, y: row.midY), anchor: .leading)
        let street = graphics.resolve(Text(guide.street).font(font).foregroundStyle(Paint.caption))
        let room = CGSize(width: max(0, row.width - taken), height: row.height)
        let height = street.measure(in: room).height
        graphics.draw(street, in: CGRect(x: row.minX + taken, y: row.midY - height / 2, width: room.width, height: height))
    }

    /// When the song ends, how long that is, and how far there is still to walk.
    private func drawArrival(in graphics: GraphicsContext) {
        let unit = layout.unit
        let card = CGRect(x: layout.margin, y: layout.size.height - layout.margin - Eta.height * unit, width: Eta.width * unit, height: Eta.height * unit)
        drawCard(card, corner: Eta.corner * unit, in: graphics)
        let secondsLeft = max(0, plan.end - position)
        let metresLeft = plan.spans[leg...].reduce(0, +) - plan.spans[leg] * walked
        let isMetric = Locale.current.measurementSystem == .metric
        let distance = metresLeft / (isMetric ? Eta.metresPerKilometre : Eta.metresPerMile)
        let columns = [
            (value: Date(timeIntervalSinceReferenceDate: clock + secondsLeft).formatted(Eta.clock), caption: "arrival"),
            // A player gone wrong can report an infinite position; converting that plainly would trap.
            (value: "\(Int(exactly: (secondsLeft / 60).rounded(.up)) ?? 0)", caption: "min"),
            (value: distance.formatted(.number.precision(.fractionLength(1))), caption: isMetric ? "km" : "mi"),
        ]
        for (index, column) in columns.enumerated() {
            let x = card.minX + card.width * (Double(index) + 0.5) / Double(columns.count)
            graphics.draw(Text(column.value).font(.system(size: Eta.valueSize * unit, weight: .bold)).foregroundStyle(.white),
                          at: CGPoint(x: x, y: card.minY + Eta.valueY * unit))
            graphics.draw(Text(column.caption).font(.system(size: Eta.captionSize * unit, weight: .medium)).foregroundStyle(Paint.caption),
                          at: CGPoint(x: x, y: card.minY + Eta.captionY * unit))
        }
    }
}

// MARK: Self-check

/// Assert-style checks of the map's pure logic, for `Stanza --self-check`.
func mapStyleSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ condition: Bool, _ what: String) {
        if !condition { failures.append("map: \(what)") }
    }
    func near(_ a: Double, _ b: Double, within tolerance: Double = 0.0001) -> Bool { abs(a - b) < tolerance }

    let short = (0..<3).map { TimedWord(text: "la", start: 1 + Double($0) * 0.4, end: 1.35 + Double($0) * 0.4, line: 0) }
    let long = (0..<20).map { TimedWord(text: "na", start: 5 + Double($0) * 0.2, end: 5.15 + Double($0) * 0.2, line: 1) }
    let lyrics = TimedLyrics(tier: .wordLevel, words: short + long)
    if let plan = MapPlan(lyrics: lyrics) {
        check(plan.spans == [130, 480], "leg length follows word count, within limits")
        check(near(plan.announced[1], 2.45) && plan.leg(at: 2.4) == 0 && plan.leg(at: 2.5) == 1, "the next leg is announced 0.3 s after a line ends")
        check(plan.walked(leg: 0, at: 0.5) == 0 && plan.walked(leg: 0, at: 3) == 1 && near(plan.walked(leg: 0, at: 1.175), 1.0 / 6),
              "the puck moves only while words are sung")
        check(plan.seed == MapPlan(lyrics: lyrics)?.seed && (0..<50).allSatisfy { (0..<1).contains(plan.seed.unit($0)) },
              "seeded draws repeat and stay in 0..<1")
        let lost = MapRoad(points: [MapPoint(-9000, 0), MapPoint(-9100, 0)], signposts: [])
        let wayBack = MapLegPlan(leg: 1, seed: plan.seed, span: 200, previous: lost, nudge: 0)
        check(wayBack.outside && wayBack.destination(attempt: 0).x > -9100, "a walk that leaves the city turns back toward it")
    } else {
        check(false, "a plan is made from any lyrics")
    }

    // North for 100 m, then east: one right turn onto the signposted street.
    let corner = MapRoad(points: [MapPoint(0, 0), MapPoint(0, 60), MapPoint(0, 60), MapPoint(0, 100), MapPoint(80, 100)],
                         signposts: [.init(at: MapPoint(0, 0), street: "Oak St"), .init(at: MapPoint(0, 100), street: "Fell St")])
    let bend = corner?.bends.first
    check(corner?.bends.count == 1 && near(bend?.at ?? 0, 100) && near(bend?.angle ?? 0, 90) && bend?.street == "Fell St" && corner?.street == "Oak St",
          "a corner becomes one named right turn")
    check(corner.map { near($0.metres, 180) && near($0.point(at: 0.5).y, 90) && $0.stretch(from: 0.5, to: 1).count == 3 } ?? false,
          "positions along a road")
    check(MapRoad.streetName(in: "Turn right onto Fell St toward Gough St") == "Fell St" && MapRoad.streetName(in: "Start on Mission St") == "Mission St"
          && MapRoad.streetName(in: "The destination is on your left") == nil, "street names are read from instructions")

    // Where MapKit put the corners of a 640 m square in a tilted picture, and a fifth point it reported.
    let tilted = MapLens(reach: 320, corners: [MapPoint(619.775, -1.992), MapPoint(1438.900, 380.735), MapPoint(944.401, 787.356), MapPoint(280.339, 582.965)])
    func lands(_ point: MapPoint?, on expected: MapPoint, within tolerance: Double) -> Bool {
        point.map { simd_distance($0, expected) < tolerance } ?? false
    }
    check(tilted.map { lands($0(MapPoint(0, 320)), on: MapPoint(637.823, 692.995), within: 0.5) && lands($0(.zero), on: MapPoint(821.5, 488.5), within: 0.5)
                       && lands($0(MapPoint(120, -45)).flatMap($0.inverse.callAsFunction), on: MapPoint(120, -45), within: 0.001) } ?? false,
          "the lens solved from four corners places other ground points")
    return failures + mapSharingChecks().filter { !$0.0 }.map { "map: \($0.1)" }
}

/// Checks of what several views share (plans, tours, the picture budget) and of the lens's limits.
private func mapSharingChecks() -> [(Bool, String)] {
    func song(_ texts: [String]) -> TimedLyrics {
        TimedLyrics(tier: .wordLevel, words: texts.enumerated().map { TimedWord(text: $1, start: Double($0), end: Double($0) + 0.5, line: $0 / 2) })
    }
    // The same word count, first word and end points: only the words in between tell these two songs apart.
    let one = song(["we", "walk", "the", "line"]), other = song(["we", "ride", "the", "tide"])
    guard let first = MapPlan(lyrics: one), let second = MapPlan(lyrics: other) else { return [(false, "a plan is made from any lyrics")] }
    let keepsApart = MainActor.assumeIsolated {
        let mine = MapTour.tour(for: first), yours = MapTour.tour(for: second)
        // Two views taking turns, as the overlay and a Gallery preview do on every frame.
        let turns = (0..<3).map { _ in MapTour.tour(for: first) === mine && MapTour.tour(for: second) === yours }
        return mine !== yours && !turns.contains(false) && mine.revision == 0 && yours.revision == 0
            && MapPlan.cached(for: one)?.song == first.song && MapPlan.cached(for: other)?.song == second.song
    }
    let megabytes = 4.0 / 1_048_576
    let withinBudget = [MapLook(fillsDisplay: false, tilted: true), MapLook(fillsDisplay: true, tilted: true)].allSatisfy { look in
        (1...4).allSatisfy { Double($0 * look.stillLimit(sharedBy: $0)) * look.stillPixels * megabytes <= 120 }
    }
    let window = MapLook(fillsDisplay: false, tilted: false)
    // Three of these corners are within a hundredth of a point of one line.
    let flat = MapLens(reach: 320, corners: [MapPoint(0, 0), MapPoint(100, 100), MapPoint(200, 200.01), MapPoint(300, 300)])
    let wild = MapLens(reach: 320, corners: [MapPoint(0, 0), MapPoint(.nan, 0), MapPoint(100, 100), MapPoint(0, 100)])
    // Depth falls away to the north; 100 m north of the origin is level with the camera.
    let horizon = MapLens(matrix: simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, -0.01, 1)]))
    return [
        (first.song != second.song && first.seed == second.seed, "songs that differ only in their middle words are told apart, and keep the same walk"),
        (keepsApart, "two songs drawn at once keep their own plans and tours, and neither tour is reset"),
        (withinBudget && window.stillLimit(sharedBy: 1) == 4 && window.stillLimit(sharedBy: 2) == 2
            && window.stillLimit(sharedBy: 1, besides: window.stillPixels) == 3, "tours share one picture budget of about 120 MB"),
        (flat == nil && wild == nil, "corners on one line, or that are not numbers, make no lens"),
        (horizon(MapPoint(0, 50)) != nil && horizon(MapPoint(0, 100)) == nil && horizon(MapPoint(0, 400)) == nil,
         "ground level with or behind the camera has no place in the picture"),
    ]
}
