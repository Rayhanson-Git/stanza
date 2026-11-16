import AppKit
import Combine

/// Pure colour maths, covered by SelfCheck.swift.
enum AccentExtractor {
    static let sampleSide = 40
    static let minSaturation: CGFloat = 0.25
    static let minBrightness: CGFloat = 0.3
    // Palette rules: enough distinct hues for a card, none of them muddy.
    static let paletteRange = 3...5
    static let minShareOfTopScore: CGFloat = 0.03
    static let minHueDistance: CGFloat = 0.06
    static let fillerHueSteps: [CGFloat] = [0.07, -0.07, 0.14]
    static let greyFallback: [CGFloat] = [0.84, 0.90, 0.80]

    private struct Bucket {
        var count = 0, red = 0, green = 0, blue = 0

        var color: NSColor {
            let total = CGFloat(count) * 255
            return NSColor(srgbRed: CGFloat(red) / total, green: CGFloat(green) / total, blue: CGFloat(blue) / total, alpha: 1)
        }

        /// Population × saturation × brightness, or nil for colours too grey or too dark to be an accent.
        var vividScore: CGFloat? {
            let candidate = color
            guard candidate.saturationComponent > minSaturation, candidate.brightnessComponent > minBrightness else { return nil }
            return CGFloat(count) * (candidate.saturationComponent + 0.2) * (candidate.brightnessComponent + 0.2)
        }
    }

    /// The image shrunk to 40×40 and sorted into 4,096 colour buckets (4 bits per channel).
    private static func buckets(of image: CGImage) -> [Bucket]? {
        let side = sampleSide
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let pixels = context.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) else { return nil }
        let filled = (0..<side * side).reduce(into: [Int: Bucket]()) { buckets, pixel in
            let red = Int(pixels[pixel * 4]), green = Int(pixels[pixel * 4 + 1]), blue = Int(pixels[pixel * 4 + 2])
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            buckets[key, default: Bucket()].count += 1
            buckets[key]!.red += red
            buckets[key]!.green += green
            buckets[key]!.blue += blue
        }
        // Sorted by key so results never depend on dictionary order.
        return filled.sorted { $0.key < $1.key }.map(\.value)
    }

    /// The most prominent vivid colour, or the most common colour for grey artwork.
    static func accent(of image: CGImage) -> NSColor? {
        guard let buckets = buckets(of: image) else { return nil }
        let vivid = buckets.compactMap { bucket in bucket.vividScore.map { (bucket, $0) } }.max { $0.1 < $1.1 }?.0
        return (vivid ?? buckets.max { $0.count < $1.count })?.color
    }

    /// Three to five distinct, bright colours for tinting cards: the strongest vivid colours whose hues
    /// differ, padded with hue-shifted copies of the strongest, or light greys for colourless artwork.
    static func palette(of image: CGImage) -> [NSColor]? {
        guard let buckets = buckets(of: image) else { return nil }
        let ranked = buckets.compactMap { bucket in bucket.vividScore.map { (color: bucket.color, score: $0) } }
            .sorted { $0.score > $1.score }
        guard let top = ranked.first else { return greyFallback.map { NSColor(white: $0, alpha: 1) } }
        func hueDistance(_ first: NSColor, _ second: NSColor) -> CGFloat {
            let difference = abs(first.hueComponent - second.hueComponent)
            return min(difference, 1 - difference)
        }
        let distinct = ranked.reduce(into: [NSColor]()) { chosen, candidate in
            guard chosen.count < paletteRange.upperBound, candidate.score > top.score * minShareOfTopScore,
                  chosen.allSatisfy({ hueDistance($0, candidate.color) > minHueDistance }) else { return }
            chosen.append(candidate.color)
        }
        let fillers = fillerHueSteps.map { step -> NSColor in
            let hue = (top.color.hueComponent + step).truncatingRemainder(dividingBy: 1)
            return NSColor(hue: hue < 0 ? hue + 1 : hue, saturation: top.color.saturationComponent,
                           brightness: top.color.brightnessComponent, alpha: 1)
        }
        let padded = distinct + fillers.prefix(max(0, paletteRange.lowerBound - distinct.count))
        return padded.map { color in
            NSColor(hue: color.hueComponent, saturation: min(max(color.saturationComponent * 0.85, 0.40), 0.72),
                    brightness: max(color.brightnessComponent, 0.95), alpha: 1)
        }
    }
}

/// Reads the current track's album art. Recolours the lyrics from it while "Colours from the album cover" is on, and
/// keeps a small palette for the styles that tint their cards with the cover.
final class ArtworkColorSync: ObservableObject {
    @Published private(set) var palette: [NSColor]?
    private let monitor: NowPlayingMonitor
    private let settings: AppSettings
    private var observers: Set<AnyCancellable> = []
    private var loadedTrack: Track?
    private var loadingTrack: Track?
    private var accent: NSColor?

    init(monitor: NowPlayingMonitor, settings: AppSettings) {
        self.monitor = monitor
        self.settings = settings
        monitor.$track.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }.store(in: &observers)
        settings.$autoSyncColors.removeDuplicates().combineLatest(settings.$style.removeDuplicates())
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.sync() }.store(in: &observers)
    }

    /// Artwork is only fetched when something will use it.
    private var isNeeded: Bool { settings.autoSyncColors || settings.style.usesArtworkPalette }

    private func sync() {
        guard let track = monitor.track else {
            palette = nil
            loadedTrack = nil
            return
        }
        if loadedTrack == track { return applyAccent() }
        if palette != nil { palette = nil }
        guard isNeeded, loadingTrack != track, let player = monitor.player else { return }
        loadingTrack = track
        let probe = monitor.probe
        probe.queue.async { [weak self] in
            let artwork = probe.artwork(player: player)
            Task { @MainActor [weak self] in
                let image = await Self.image(from: artwork)
                self?.finish(track, accent: image.flatMap(AccentExtractor.accent(of:)), palette: image.flatMap(AccentExtractor.palette(of:)))
            }
        }
    }

    private func finish(_ track: Track, accent: NSColor?, palette: [NSColor]?) {
        if loadingTrack == track { loadingTrack = nil }
        // Ignore a result that arrives after the track changed.
        guard monitor.track == track else { return }
        loadedTrack = track
        self.accent = accent
        self.palette = palette
        log(accent.map { "album art: accent \($0.hexString), \(palette?.count ?? 0) card colours" } ?? "album art: no usable artwork for current track")
        applyAccent()
    }

    private func applyAccent() {
        guard settings.autoSyncColors else { return }
        // A track without artwork goes back to the hand-picked colours instead of keeping the last track's.
        if let accent { settings.applyAccent(accent) } else { settings.clearAccent() }
    }

    /// The address comes from the player, so only the web is allowed: URLSession would also read `file:` URLs.
    static func isFetchable(_ url: URL) -> Bool { url.scheme?.lowercased() == "https" }

    private static func image(from artwork: Artwork?) async -> CGImage? {
        let data: Data?
        switch artwork {
        case .data(let bytes): data = bytes
        case .url(let url) where isFetchable(url): data = try? await URLSession.shared.data(from: url).0
        case .url(let url):
            log("album art: not fetching a \(url.scheme ?? "scheme-less") address")
            data = nil
        case nil: data = nil
        }
        return data.flatMap(NSImage.init(data:))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
