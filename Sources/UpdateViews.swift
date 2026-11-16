import SwiftUI

/// The gear at the top right of the window; it opens the Settings panel.
struct SettingsButton: View {
    private static let size: CGFloat = 36

    @ObservedObject var model: GalleryModel

    var body: some View {
        let isOpen = model.menu == .settings || model.menu == .about
        Hoverable(id: "settings", hover: model.hover) { hovered in
            // Closes the card from Settings or About alike; opens Settings otherwise.
            Button { model.menu = isOpen ? nil : .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: Self.size, height: Self.size)
                    .background(Color.white.opacity(isOpen ? 0.18 : hovered ? 0.08 : 0), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        }
    }
}

/// Settings: opening at login, and updates.
struct SettingsPanel: View {
    @ObservedObject var model: GalleryModel
    @ObservedObject var loginItem: LoginItem
    let updater: AppUpdater?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let switchedOn = loginItem.isOn || loginItem.needsApproval
            SettingSwitch(title: "Open at login", detail: "Start Stanza when you log in to this Mac.",
                          isOn: Binding(get: { switchedOn }, set: { loginItem.set($0) }))
                // Turning it off always works; turning it on needs the copy in Applications.
                .disabled(!LoginItem.isInstalled && !switchedOn)
            if !LoginItem.isInstalled && !switchedOn {
                PanelNote(text: "Move Stanza into your Applications folder and open it from there to use this.")
            }
            if loginItem.needsApproval {
                PanelNote(text: "Allow Stanza in System Settings › General › Login Items to finish.")
            }
            if let problem = loginItem.problem { PanelNote(text: problem) }
            if let updater {
                PanelRule()
                UpdateSettings(updater: updater)
            }
            PanelRule()
            PanelRow(id: "settings.about", hover: model.hover) { model.menu = .about } content: {
                Text("About Stanza").font(.system(size: 13.5)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .onAppear { loginItem.refresh() }
    }
}

/// The updates part of Settings: the automatic-install switch, the version and the check button.
struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingSwitch(title: "Install updates automatically", detail: "Downloads quietly and installs when Stanza restarts.",
                          isOn: Binding(get: { updater.installsAutomatically }, set: { updater.installsAutomatically = $0 }))
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stanza \(AppUpdater.currentVersion)").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                    Text(status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                Button(buttonTitle) { updater.act() }
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                    .disabled(!updater.canAct)
            }
        }
    }

    /// Shorter than the menu's wording, so it fits beside the version.
    private var buttonTitle: String {
        switch updater.pending {
        case .ready: return "Restart"
        case .available: return "Update…"
        case nil: return "Check Now"
        }
    }

    private var status: String {
        switch updater.pending {
        case .ready(let version): return "Version \(version) is ready. It installs when Stanza restarts."
        case .available(let version): return "Version \(version) is available."
        case nil:
            guard let lastCheck = updater.lastCheck else { return "Looks for updates once a day." }
            return "Up to date. Checked \(lastCheck.formatted(.relative(presentation: .named)))."
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
