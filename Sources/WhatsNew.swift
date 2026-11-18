import SwiftUI

/// One release's notes from CHANGELOG.md: its bullets, with sub-bullets marked as indented.
struct ReleaseNotes: Equatable {
    struct Item: Equatable {
        let text: String
        let indented: Bool
    }

    let version: String
    let items: [Item]
}

/// What's New: the first time the window opens after an update, a pop-up with the notes of every release since the
/// one last seen.
/// The notes are CHANGELOG.md, copied into the app by build.sh, so they are the same text as the GitHub release.
enum WhatsNew {
    /// Copies updated from before What's New existed have no record; they are shown the releases after this one.
    /// 0.4.8's notes round up the features and fixes of 0.4.1 to 0.4.7 for them.
    static let baseline = "0.4.7"

    static func bundled() -> [ReleaseNotes] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            log("what's new: no CHANGELOG.md in the app")
            return []
        }
        return parse(text)
    }

    /// Sections start at "## <version>"; "- " starts a note, "  - " an indented one, and any other text continues it.
    static func parse(_ changelog: String) -> [ReleaseNotes] {
        var releases: [ReleaseNotes] = []
        var version: String?
        var items: [ReleaseNotes.Item] = []
        func close() {
            if let version, !items.isEmpty { releases.append(ReleaseNotes(version: version, items: items)) }
        }
        for line in changelog.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                close()
                // Only the number: "## 0.4.9 (date)" is version 0.4.9.
                version = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)
                items = []
            } else if version == nil || trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("- ") {
                items.append(.init(text: String(trimmed.dropFirst(2)), indented: line.hasPrefix(" ")))
            } else if let last = items.popLast() {
                items.append(.init(text: last.text + " " + trimmed, indented: last.indented))
            }
        }
        close()
        return releases
    }

    /// Compares dotted version numbers part by part, so 0.4.10 is newer than 0.4.9.
    static func isNewer(_ version: String, than other: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }, b = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The releases after `lastSeen`, up to and including `current`, newest first as in the changelog.
    static func unseen(in releases: [ReleaseNotes], current: String, lastSeen: String) -> [ReleaseNotes] {
        releases.filter { isNewer($0.version, than: lastSeen) && !isNewer($0.version, than: current) }
    }

    /// What the window opens with. Nothing for a new user, whose first-run introduction comes instead.
    static func toShow(in releases: [ReleaseNotes], current: String, lastSeen: String?, onboardingDone: Bool) -> [ReleaseNotes] {
        onboardingDone ? unseen(in: releases, current: current, lastSeen: lastSeen ?? baseline) : []
    }
}

/// The What's New pop-up: a card in the middle of the window, over a dimmed page, closed only with OK.
struct WhatsNewCard: View {
    static let width: CGFloat = 520
    /// Kept clear above and below it in the window.
    static let margin: CGFloat = 40
    private static let padding: CGFloat = 24
    private static let iconSize: CGFloat = 46

    @ObservedObject var model: GalleryModel
    /// The room it may take; longer notes scroll inside the card.
    let maxHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable()
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's New").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    Text("Stanza \(AppUpdater.currentVersion)").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(Self.padding)
            ViewThatFits(in: .vertical) {
                notes
                ScrollView(.vertical) { notes }.scrollIndicators(.visible)
            }
            PanelRule()
            HStack {
                Button("All changes") { StanzaLinks.open(StanzaLinks.changes) }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button("OK") { model.dismissWhatsNew() }
                    .buttonStyle(PrimaryPillStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Self.padding)
            .padding(.vertical, 16)
        }
        .frame(width: Self.width)
        .modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 18)
        .frame(maxHeight: maxHeight)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.whatsNew, id: \.version) { release in
                VStack(alignment: .leading, spacing: 8) {
                    // The running version is in the header; earlier ones are named over their notes.
                    if release.version != AppUpdater.currentVersion || model.whatsNew.count > 1 {
                        Text("Stanza \(release.version)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                    ForEach(release.items.indices, id: \.self) { index in note(release.items[index]) }
                }
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.bottom, Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ item: ReleaseNotes.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").font(.system(size: 14)).foregroundStyle(.white.opacity(0.5)).accessibilityHidden(true)
            Text(Self.styled(item.text)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, item.indented ? 16 : 0)
    }

    /// The changelog's **bold** names, kept bold.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
