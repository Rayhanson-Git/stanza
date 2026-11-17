import AppKit
import Combine
import ServiceManagement

/// Whether Stanza opens when you log in, kept in the system's own list of login items.
final class LoginItem: ObservableObject {
    /// Only a copy in an Applications folder can be a login item; one opened from the disk image or Downloads would
    /// leave the login item pointing at a copy that later disappears.
    static let isInstalled = ["/Applications/", NSHomeDirectory() + "/Applications/"].contains { Bundle.main.bundlePath.hasPrefix($0) }

    /// Whether `event`, the open-app event of this launch, says macOS opened Stanza as a login item. Pass it while
    /// launching: later the current event is something else. macOS sends the flag as the event's property value;
    /// the SDK header describes it as its own parameter, so either form counts.
    static func launchedAtLogin(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            || event.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
    }

    @Published private(set) var isOn = false
    /// macOS has the item but waits for the user to allow it in System Settings.
    @Published private(set) var needsApproval = false
    @Published private(set) var problem: String?
    private var activation: AnyCancellable?

    init() {
        refresh()
        // Login Items can be changed in System Settings meanwhile; look again whenever Stanza comes to the front.
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            problem = nil
        } catch {
            log("login item: could not turn \(on ? "on" : "off"): \(error.localizedDescription)")
            problem = "macOS did not accept the change: \(error.localizedDescription)"
        }
        refresh()
    }
}
