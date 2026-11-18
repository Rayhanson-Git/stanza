import AppKit
import Carbon.HIToolbox

/// What a keyboard shortcut can do from anywhere on the Mac.
enum ShortcutAction: String, CaseIterable {
    case toggleLyrics, nextStyle

    var title: String {
        switch self {
        case .toggleLyrics: return "Show or hide the lyrics"
        case .nextStyle: return "Next style"
        }
    }

    var detail: String {
        switch self {
        case .toggleLyrics: return "The same as Lyrics when unlocked too."
        case .nextStyle: return "Through your favourites, or every style."
        }
    }
}

/// One key combination: the key's virtual code, Carbon modifier flags, and how it reads (⌃⌥L), taken when recorded.
struct KeyCombo: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String

    func sameKeys(as other: KeyCombo) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    /// A combination from a key press, or nil unless it holds two of ⌃ ⌥ ⌘. A single ⌘ or ⌃ would take ⌘V or ⌃A away
    /// from every app; ⌥ alone was blocked in macOS 15 (against key loggers); a bare key would fire while typing.
    static func make(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> KeyCombo? {
        let strong = [NSEvent.ModifierFlags.control, .option, .command].filter(flags.contains).count
        guard strong >= 2, let key = keyName(keyCode, characters) else { return nil }
        // Written in the order macOS menus use: ⌃⌥⇧⌘.
        let parts: [(NSEvent.ModifierFlags, Int, String)] = [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                                                             (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")]
        let held = parts.filter { flags.contains($0.0) }
        return KeyCombo(keyCode: UInt32(keyCode), modifiers: held.reduce(0) { $0 | UInt32($1.1) },
                        label: held.map(\.2).joined() + key)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ keyCode: UInt16, _ characters: String?) -> String? {
        if let name = namedKeys[Int(keyCode)] { return name }
        guard let text = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.uppercased()
    }
}

/// The shortcuts set in Settings, registered with the system so they work while another app is in front.
/// None are set until the user records one. Carbon hot keys need no Accessibility permission and see only these keys.
final class GlobalShortcuts: ObservableObject {
    static let shared = GlobalShortcuts()
    private static let signature: OSType = 0x5374_6E7A // "Stnz"
    private static let keyPrefix = "shortcut."

    @Published private(set) var combos: [ShortcutAction: KeyCombo]
    /// Shortcuts the system refused, usually because another app already uses those keys.
    @Published private(set) var unavailable: Set<ShortcutAction> = []
    /// The shortcut being recorded in Settings. All of them are off meanwhile, so pressing the old keys records them.
    @Published private(set) var recording: ShortcutAction? { didSet { if (recording == nil) != (oldValue == nil) { register() } } }
    /// Why the last key press was not taken, shown under the shortcuts.
    @Published private(set) var note: String?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    private let defaults = UserDefaults.standard
    private var perform: (ShortcutAction) -> Void = { _ in }
    private var registered: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {
        combos = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
            Self.decode(UserDefaults.standard.data(forKey: Self.keyPrefix + action.rawValue)).map { (action, $0) }
        })
    }

    /// Starts listening; `perform` runs on the main thread for each shortcut pressed.
    func start(perform: @escaping (ShortcutAction) -> Void) {
        self.perform = perform
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == GlobalShortcuts.signature, ShortcutAction.allCases.indices.contains(Int(id.id))
            else { return OSStatus(eventNotHandledErr) }
            GlobalShortcuts.shared.fire(ShortcutAction.allCases[Int(id.id)])
            return noErr
        }, 1, &pressed, nil, &handler)
        if status != noErr { log("shortcuts: could not listen for them (\(status))") }
        register()
    }

    /// Sets or (with nil) removes a shortcut. Returns the other action already on those keys, changing nothing.
    @discardableResult
    func set(_ combo: KeyCombo?, for action: ShortcutAction) -> ShortcutAction? {
        if let combo, let other = Self.conflict(combo, for: action, in: combos) { return other }
        combos[action] = combo
        let key = Self.keyPrefix + action.rawValue
        if let combo, let data = try? JSONEncoder().encode(combo) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
        log("shortcut \(action.rawValue) → \(combo?.label ?? "none")")
        register()
        return nil
    }

    static func conflict(_ combo: KeyCombo, for action: ShortcutAction, in combos: [ShortcutAction: KeyCombo]) -> ShortcutAction? {
        combos.first { $0.key != action && $0.value.sameKeys(as: combo) }?.key
    }

    static func decode(_ data: Data?) -> KeyCombo? { data.flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } }

    // MARK: Recording

    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        note = nil
        recording = action
        // Only keys typed into the window that is recording; anything else goes on as usual.
        let window = NSApp.keyWindow
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === window else { return event }
            record(event, for: action)
            return nil
        }
        // Switching to another app ends it, or every shortcut would stay off until Stanza came back.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.stopRecording() }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        keyMonitor = nil
        resignObserver = nil
        recording = nil
    }

    private func record(_ event: NSEvent, for action: ShortcutAction) {
        switch Int(event.keyCode) {
        case kVK_Escape: stopRecording()
        case kVK_Delete, kVK_ForwardDelete:
            set(nil, for: action)
            stopRecording()
        default:
            // The key as typed without modifiers, so ⇧1 reads ⇧1, not ⇧!.
            guard let combo = KeyCombo.make(keyCode: event.keyCode, flags: event.modifierFlags,
                                            characters: event.characters(byApplyingModifiers: [])) else {
                note = "Hold two of ⌃ ⌥ ⌘ with the key, so it cannot clash with copy, paste and the like."
                return
            }
            if let other = set(combo, for: action) {
                note = "\(combo.label) is already set for \(other.title.lowercased())."
                return
            }
            note = nil
            stopRecording()
        }
    }

    private func fire(_ action: ShortcutAction) {
        log("shortcut pressed: \(action.rawValue)")
        perform(action)
    }

    private func register() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        guard recording == nil, handler != nil else { return }
        var refused: Set<ShortcutAction> = []
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = combos[action] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: Self.signature, id: UInt32(index)),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered.append(ref) } else {
                refused.insert(action)
                log("shortcut \(action.rawValue) \(combo.label): the system refused it (\(status))")
            }
        }
        if unavailable != refused { unavailable = refused }
    }
}
