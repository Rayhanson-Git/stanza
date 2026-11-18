import SwiftUI

/// The keyboard shortcuts part of Settings: one row per action, each recorded by clicking it and pressing the keys.
/// The recording state lives in `GlobalShortcuts` (view-local @State needs full Xcode; see `WordIcon`).
struct ShortcutSettings: View {
    private static let hint = "None are set. Click Set, then press the keys with two of ⌃ ⌥ ⌘. Esc cancels; Delete removes one."

    @ObservedObject var shortcuts: GlobalShortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keyboard shortcuts").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            ForEach(ShortcutAction.allCases, id: \.self) { action in row(action) }
            if let note = shortcuts.note { PanelNote(text: note) } else if shortcuts.combos.isEmpty { PanelNote(text: Self.hint) }
        }
        .onDisappear { shortcuts.stopRecording() }
    }

    private func row(_ action: ShortcutAction) -> some View {
        let combo = shortcuts.combos[action], recording = shortcuts.recording == action
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white)
                Text(shortcuts.unavailable.contains(action) ? "Another app uses these keys; pick others." : action.detail)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Button(recording ? "Type keys…" : combo?.label ?? "Set") {
                recording ? shortcuts.stopRecording() : shortcuts.startRecording(action)
            }
            .buttonStyle(QuietButtonStyle())
            .fixedSize()
            .accessibilityLabel(recording ? "Recording a shortcut for \(action.title)" : "\(action.title) shortcut: \(combo?.label ?? "none")")
            if combo != nil, !recording {
                Button { shortcuts.set(nil, for: action) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove the shortcut for \(action.title)")
            }
        }
    }
}
