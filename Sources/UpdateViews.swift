import SwiftUI

/// The foot of the window: which Stanza this is, how updates are going, and the one switch for them.
struct UpdateFooter: View {
    private static let switchWidth: CGFloat = 290

    @ObservedObject var updater: AppUpdater

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stanza \(AppUpdater.currentVersion)").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                Text(status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 12)
            SettingSwitch(title: "Install updates automatically", isOn: Binding(
                get: { updater.installsAutomatically }, set: { updater.installsAutomatically = $0 }))
                .frame(width: Self.switchWidth)
            Button(updater.actionTitle) { updater.act() }
                .buttonStyle(QuietButtonStyle())
                .disabled(!updater.canAct)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var status: String {
        switch updater.pending {
        case .ready(let version): return "Version \(version) is downloaded and installs when Stanza restarts."
        case .available(let version): return "Version \(version) is available."
        case nil:
            guard let lastCheck = updater.lastCheck else { return "Looks for updates once a day." }
            return "Up to date. Last checked \(lastCheck.formatted(.relative(presentation: .named)))."
        }
    }
}

/// Shown at the top left only while an update waits, so it is noticed without getting in the way.
struct UpdatePill: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        if let pending = updater.pending {
            Button { updater.act() } label: {
                Label(title(pending), systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: GalleryTopBar.height - 8)
            }
            .buttonStyle(DimWhenDisabledStyle())
            .padding(4)
            .modifier(GlassSurface(shape: Capsule(), interactive: true))
            .help(updater.actionTitle)
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
        }
    }

    private func title(_ pending: AppUpdater.Pending) -> String {
        switch pending {
        case .ready: return "Restart to update"
        case .available(let version): return "Stanza \(version) is out"
        }
    }
}
