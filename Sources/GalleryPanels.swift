import SwiftUI

/// The glass card at the top-right that holds whichever panel is open.
struct GalleryPanel: View {
    static let width: CGFloat = 320
    static let margin: CGFloat = 18
    /// How much room the open panel takes from the hero.
    static let inset = width + margin
    static let topOffset: CGFloat = 66
    private static let padding: CGFloat = 18

    let menu: GalleryMenu
    @ObservedObject var model: GalleryModel
    /// The room under the top bar; a panel taller than this scrolls instead of running off the window.
    let maxHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.padding(Self.padding)
            ScrollView(.vertical) { content.padding(Self.padding) }.scrollIndicators(.never)
        }
        .frame(width: Self.width)
        .modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .frame(maxHeight: maxHeight, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch menu {
        case .size: SizePanel(settings: model.settings)
        case .font: FontPanel(settings: model.settings, hover: model.hover)
        case .lockScreen: LockScreenPanel(settings: model.settings)
        case .aesthetics: AestheticsPanel(settings: model.settings, hover: model.hover)
        case .spotify: PlayerPanel(player: .spotify, link: model.playerLink, monitor: model.monitor, engine: model.engine,
                                   settings: model.settings)
        case .music: PlayerPanel(player: .music, link: model.playerLink, monitor: model.monitor, engine: model.engine,
                                 settings: model.settings)
        }
    }
}

struct SizePanel: View {
    private static let normalScale = 1.0

    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                glyph(size: 12)
                Slider(value: $settings.textScale, in: AppSettings.textScaleRange) { Text("Lyric size") }
                    .labelsHidden()
                    .tint(.white)
                glyph(size: 22)
            }
            HStack {
                Text("\(Int((settings.textScale * 100).rounded()))%")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
                Button("Reset") { settings.textScale = Self.normalScale }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(settings.textScale == Self.normalScale)
            }
        }
    }

    private func glyph(size: CGFloat) -> some View {
        Image(systemName: "textformat").font(.system(size: size, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            .accessibilityHidden(true)
    }
}

struct FontPanel: View {
    private static let sampleSize: CGFloat = 16

    @ObservedObject var settings: AppSettings
    let hover: GalleryHover

    var body: some View {
        VStack(spacing: 2) {
            ForEach(LyricFont.allCases, id: \.self) { font in
                PanelRow(id: "font.\(font.rawValue)", selected: settings.font == font, hover: hover) {
                    settings.font = font
                } content: {
                    Text(font.rawValue).font(Font(font.font(size: Self.sampleSize) as CTFont)).foregroundStyle(.white)
                    Spacer()
                    if settings.font == font {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }
            if settings.style.isPhoneScreen {
                PanelNote(text: "The phone-screen styles keep the system typeface, whatever is picked here.")
            }
        }
    }
}

struct LockScreenPanel: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingSwitch(title: "Lyrics when unlocked too", detail: "Turn off to see them on the lock screen only.",
                          isOn: $settings.showWhenUnlocked)
            SettingSwitch(title: "Stop the screen sleeping", detail: "Only while a song is playing.",
                          isOn: $settings.keepScreenAwake)
            PanelRule()
            VStack(alignment: .leading, spacing: 10) {
                Text("Displays").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                ForEach(displays, id: \.id) { display in
                    SettingSwitch(title: display.name, isOn: Binding(
                        get: { !settings.disabledDisplays.contains(display.id) },
                        set: { shown in if shown == settings.disabledDisplays.contains(display.id) { settings.toggleDisplay(display.id) } }))
                }
            }
        }
    }

    private var displays: [(id: UInt32, name: String)] {
        NSScreen.screens.compactMap { screen in OverlayController.displayID(of: screen).map { ($0, screen.localizedName) } }
    }
}

struct AestheticsPanel: View {
    private enum Metrics {
        static let swatch: CGFloat = 22
        static let autoSyncDim = 0.45
    }

    @ObservedObject var settings: AppSettings
    let hover: GalleryHover

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingSwitch(title: "Colours from the album cover", detail: "They change with each song that plays.",
                          isOn: $settings.autoSyncColors)
            PanelRule()
            VStack(spacing: 2) {
                ForEach(ColorSlot.allCases, id: \.self) { slot in
                    PanelRow(id: "color.\(slot.rawValue)", hover: hover) { LyricColorPanel.shared.pick(slot) } content: {
                        Text(slot.title).font(.system(size: 13.5)).foregroundStyle(.white)
                        Spacer()
                        swatch(settings.color(slot))
                    }
                    .accessibilityHint("Opens the colour picker")
                }
            }
            .opacity(settings.autoSyncColors ? Metrics.autoSyncDim : 1)
            HStack {
                Button("Reset colors") { settings.resetColors() }.buttonStyle(QuietButtonStyle())
                Spacer()
            }
            if settings.style.isPhoneScreen {
                PanelNote(text: "The phone-screen styles bring their own colours and ignore these.")
            }
        }
    }

    /// Drawn over black so a see-through colour reads as it will over a dark wallpaper.
    private func swatch(_ color: NSColor) -> some View {
        Circle()
            .fill(Color(nsColor: color))
            .background(Circle().fill(.black))
            .frame(width: Metrics.swatch, height: Metrics.swatch)
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
    }
}

/// Points the shared system colour panel at one of the three lyric colours.
final class LyricColorPanel: NSObject {
    static let shared = LyricColorPanel()

    private let settings = AppSettings.shared
    private var slot: ColorSlot?

    func pick(_ slot: ColorSlot) {
        self.slot = slot
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = settings.storedColor(slot)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.title = "Stanza — \(slot.title)"
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        guard let slot else { return }
        // A hand-picked colour should be visible immediately, so it switches album-art matching off.
        if settings.autoSyncColors { settings.autoSyncColors = false }
        settings.setColor(sender.color, for: slot)
    }
}
