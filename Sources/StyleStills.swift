import Combine
import SwiftUI

/// A still picture of every style for the shelf. Rendered one at a time between frames, kept in memory
/// only, and thrown away with the window.
final class StyleStills: ObservableObject {
    private enum Pace {
        static let betweenStills = 0.08
        static let afterResume = 0.6
        static let settingsDebounce = DispatchQueue.SchedulerTimeType.Stride.milliseconds(350)
        // Word pictures and map pictures are fetched in the background after the window opens; these
        // two later passes pick them up.
        static let lateDataPasses = [3.0, 9.0]
    }

    static let size = CGSize(width: 320, height: 200)
    static let scale: CGFloat = 2

    @Published private(set) var images: [LyricStyle: CGImage] = [:]
    /// Set while the window is out of sight or scrolling, so rendering never competes with either.
    var paused = false {
        didSet {
            guard oldValue, !paused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Pace.afterResume) { [weak self] in self?.drain() }
        }
    }

    private let settings: AppSettings
    private var pending: [LyricStyle] = []
    private var draining = false
    private var settingsObserver: AnyCancellable?
    /// `WordVisuals.revision` at the latest pass: while it stands, the word pictures in the stills are current.
    private var wordIconRevision: Int?

    init(settings: AppSettings) {
        self.settings = settings
        // Everything that changes how a still looks. Each publisher replays its current value first, hence dropFirst.
        let changes: [AnyPublisher<Void, Never>] = [
            settings.$font.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$textScale.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$textColor.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$highlightColor.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$secondaryColor.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$mapIn3D.dropFirst().map { _ in }.eraseToAnyPublisher(),
            settings.$mapFillsDisplay.dropFirst().map { _ in }.eraseToAnyPublisher(),
        ]
        settingsObserver = Publishers.MergeMany(changes)
            .debounce(for: Pace.settingsDebounce, scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.refreshAll() }
        // The first pass waits for the window to be up.
        DispatchQueue.main.async { [weak self] in self?.refreshAll() }
        for delay in Pace.lateDataPasses {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshLateData() }
        }
    }

    func refreshAll() {
        wordIconRevision = WordVisuals.shared.revision
        pending = LyricStyle.allCases
        drain()
    }

    private func refreshLateData() {
        let revision = WordVisuals.shared.revision
        pending = Self.queue(pending, adding: Self.lateDataStyles(wordIconsChanged: revision != wordIconRevision))
        wordIconRevision = revision
        drain()
    }

    /// The only stills a later pass can improve: those with map pictures, and those with word pictures when
    /// some were resolved since the pass before. Every other style draws the same picture each time.
    static func lateDataStyles(wordIconsChanged: Bool) -> [LyricStyle] {
        LyricStyle.allCases.filter { $0.drawsMapPictures || (wordIconsChanged && $0.drawsWordIcons) }
    }

    /// `pending` plus the `styles` not already waiting, so a pass that overtakes a slow one drops and doubles nothing.
    static func queue(_ pending: [LyricStyle], adding styles: [LyricStyle]) -> [LyricStyle] {
        pending + styles.filter { !pending.contains($0) }
    }

    private func drain() {
        guard !paused, !draining, let style = pending.first else { return }
        draining = true
        pending = Array(pending.dropFirst())
        if let image = Self.render(style, settings: settings) {
            images = images.merging([style: image]) { _, fresh in fresh }
        } else {
            log("stills: could not render \(style.rawValue)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Pace.betweenStills) { [weak self] in
            self?.draining = false
            self?.drain()
        }
    }

    /// Main thread only: the tile's still frame as a bitmap.
    static func render(_ style: LyricStyle, settings: AppSettings) -> CGImage? {
        MainActor.assumeIsolated {
            let scene = TileScene(demo: StyleDemo(style: style), size: size, settings: settings).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = scale
            return renderer.cgImage
        }
    }
}
