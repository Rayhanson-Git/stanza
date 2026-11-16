import AppKit
import SwiftUI

/// Where the About card and the credit line point.
enum StanzaLinks {
    static let portfolio = URL(string: "https://rayhanson.tech")!
    static let source = URL(string: "https://github.com/Rayhanson-Git/stanza")!
    static let changes = URL(string: "https://github.com/Rayhanson-Git/stanza/blob/main/CHANGELOG.md")!
    static let author = "Harvey Rayhanson"

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// About Stanza, reached from Settings: what the app is, who made it, and where to find more.
struct AboutPanel: View {
    private static let iconSize: CGFloat = 56

    @ObservedObject var model: GalleryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { model.menu = .settings } label: { Label("Settings", systemImage: "chevron.left") }
                .buttonStyle(QuietButtonStyle())
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stanza").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    Text("Version \(AppUpdater.currentVersion)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Text("Time-synced lyrics, word by word, on your Mac's desktop and lock screen.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Text("Designed and built by \(StanzaLinks.author).")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            PanelRule()
            VStack(spacing: 2) {
                link("rayhanson.tech", detail: "Portfolio", url: StanzaLinks.portfolio)
                link("Source on GitHub", detail: nil, url: StanzaLinks.source)
                link("What's new", detail: nil, url: StanzaLinks.changes)
            }
            PanelNote(text: "Free and open source under the MIT licence. Updates by Sparkle. Lyrics from NetEase Cloud Music and LRCLIB.")
        }
    }

    private func link(_ title: String, detail: String?, url: URL) -> some View {
        PanelRow(id: "about.\(title)", hover: model.hover) { StanzaLinks.open(url) } content: {
            Text(title).font(.system(size: 13.5)).foregroundStyle(.white)
            if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)) }
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
        .accessibilityHint("Opens \(url.host() ?? "the page") in your browser")
    }
}

/// The quiet credit at the foot of the window, under the styles.
struct CreditLine: View {
    let hover: GalleryHover

    var body: some View {
        HStack {
            Spacer()
            Hoverable(id: "credit", hover: hover) { hovered in
                Button { StanzaLinks.open(StanzaLinks.portfolio) } label: {
                    HStack(spacing: 4) {
                        Text("Made by").foregroundStyle(.white.opacity(0.4))
                        Text("Rayhanson").foregroundStyle(.white.opacity(hovered ? 0.95 : 0.7)).underline(hovered)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("rayhanson.tech")
                .accessibilityLabel("Made by Rayhanson. Opens rayhanson.tech")
            }
        }
    }
}
