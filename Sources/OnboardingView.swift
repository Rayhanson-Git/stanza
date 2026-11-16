import SwiftUI

extension OnboardingStep {
    var title: String {
        switch self {
        case .welcome: return "Your lyrics, a word at a time"
        case .player: return "Connect your music player"
        case .style: return "Choose a look for the words"
        case .done: return "Stanza is ready"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "Stanza watches the song playing in Spotify or Apple Music and draws each word over your lock screen at the moment it is sung."
        case .player:
            return "Stanza asks your player which song is on and how far along it is. macOS checks with you once per player: open yours, then choose Allow."
        case .style:
            return "\(LyricStyle.allCases.count) styles to pick from. Nothing is final: switch whenever you like, in this window or from the menu bar."
        case .done:
            return "Put a song on and lock the screen to see it. This window stays one click away in the menu bar."
        }
    }

    var actionTitle: String {
        switch self {
        case .welcome: return "Start setup"
        case .player, .style: return "Next"
        case .done: return "Open the gallery"
        }
    }
}

/// The first-run introduction. It takes over the whole window until it has been finished once.
struct OnboardingView: View {
    private enum Metrics {
        static let textWidth: CGFloat = 400
        static let sideMaxWidth: CGFloat = 600
        static let columnSpacing: CGFloat = 60
        static let previewAspect: CGFloat = 1.6
        static let previewCorner: CGFloat = 22
        static let thumbColumns = 5
        static let thumbSpacing: CGFloat = 10
        static let thumbCorner: CGFloat = 12
        static let cardCorner: CGFloat = 22
        static let dot: CGFloat = 6
    }

    @ObservedObject var model: GalleryModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var stills: StyleStills

    var body: some View {
        let step = model.onboardingStep
        ZStack {
            StyleBackdrop(style: model.browsed).id(model.browsed).transition(.opacity)
            Color.black.opacity(0.5)
            LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.1), location: 0.6),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
            HStack(spacing: Metrics.columnSpacing) {
                textColumn(step).frame(width: Metrics.textWidth, alignment: .leading)
                sideColumn(step).frame(maxWidth: Metrics.sideMaxWidth)
            }
            .padding(.leading, 64)
            .padding(.trailing, 56)
            .padding(.top, 76)
            .padding(.bottom, 60)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        .animation(.easeInOut(duration: 0.45), value: model.browsed)
    }

    // MARK: Words and buttons

    private func textColumn(_ step: OnboardingStep) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            progress(step)
            Text(step.title)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Text(step.message)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.74))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 12) {
                Button(step.actionTitle) { model.advanceOnboarding() }
                    .buttonStyle(PrimaryPillStyle())
                    .keyboardShortcut(.defaultAction)
                if step != .welcome {
                    Button("Back") { model.retreatOnboarding() }.buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.top, 30)
        }
        .id(step)
        .transition(.opacity)
    }

    private func progress(_ step: OnboardingStep) -> some View {
        let steps = OnboardingStep.allCases
        return HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(steps, id: \.self) { each in
                    Circle().fill(.white.opacity(each == step ? 1 : 0.34)).frame(width: Metrics.dot, height: Metrics.dot)
                }
            }
            Text("Step \(step.rawValue + 1) of \(steps.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Right-hand side

    @ViewBuilder private func sideColumn(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome, .done:
            preview
        case .player:
            VStack(spacing: 16) {
                ForEach(Player.allCases, id: \.self) { player in
                    PlayerPanel(player: player, link: model.playerLink, monitor: model.monitor, engine: model.engine,
                                settings: settings, compact: true)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)))
                }
            }
        case .style:
            VStack(spacing: 18) {
                preview
                thumbnails.fixedSize(horizontal: false, vertical: true).layoutPriority(1)
            }
        }
    }

    /// The browsed style, playing. Built from the same scene as a shelf tile.
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.previewCorner, style: .continuous)
        return model.browsed.placeholderColor
            .aspectRatio(Metrics.previewAspect, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    TileScene(demo: model.heroDemo, size: geometry.size, settings: settings).id(model.browsed).transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            .accessibilityHidden(true)
    }

    private var thumbnails: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.thumbSpacing), count: Metrics.thumbColumns)
        return LazyVGrid(columns: columns, spacing: Metrics.thumbSpacing) {
            ForEach(LyricStyle.allCases, id: \.self) { style in thumbnail(style, watching: style == model.browsed) }
        }
    }

    private func thumbnail(_ style: LyricStyle, watching: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.thumbCorner, style: .continuous)
        return Button { model.browse(style) } label: {
            VStack(spacing: 5) {
                style.placeholderColor
                    .aspectRatio(Metrics.previewAspect, contentMode: .fit)
                    .overlay {
                        if let still = stills.images[style] {
                            Image(decorative: still, scale: StyleStills.scale).resizable().interpolation(.high)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(watching ? 0.95 : 0.1), lineWidth: watching ? 2 : 1))
                Text(style.rawValue)
                    .font(.system(size: 11.5, weight: watching ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(watching ? 1 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview \(style.rawValue)")
        .accessibilityAddTraits(watching ? .isSelected : [])
    }
}
