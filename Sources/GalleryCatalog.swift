import Foundation

/// What the window says about each style: its group, its one-line pitch, and which demo lines it plays.
extension LyricStyle {
    /// The four styles that imitate a phone screen bring their own typeface and colours.
    var isPhoneScreen: Bool { drawsWholeSong }

    var category: String {
        switch self {
        case .ship, .fisheye, .visual, .fisheyeVisual: return "Kinetic type"
        case .codestyle, .codestyleVisual, .branches, .web, .constellation: return "Motion scenes"
        case .messages, .money, .notifications, .map: return "Phone screens"
        }
    }

    var summary: String {
        switch self {
        case .ship: return "Every word settles onto a wall that sways slowly in space."
        case .fisheye: return "Three stacked words, swollen in the middle like a glass lens."
        case .visual: return "A centred column of words, with a small picture where one fits."
        case .fisheyeVisual: return "The lens stack, plus pictures next to the words that earn one."
        case .codestyle: return "Lyrics typed out like source code behind a blinking red cursor."
        case .codestyleVisual: return "The code look, plus pictures next to the words that earn one."
        case .branches: return "A path grows across the screen and every word switches on a node."
        case .web: return "Each line becomes a spider web, one thread per word."
        case .constellation: return "Each line is joined up as a star pattern, one star per word."
        case .messages: return "The song arrives as a chat thread, one bubble per line."
        case .money: return "Each line shows up as a payment, a card or a tap to pay."
        case .notifications: return "Lines land as lock-screen alerts, piles and widgets."
        case .map: return "A stroll through the city that drops a pin for each line."
        }
    }

    /// These styles draw word pictures, which are looked up in the background and can arrive after a still was made.
    var drawsWordIcons: Bool {
        switch self {
        case .visual, .fisheyeVisual, .codestyleVisual, .branches, .money, .notifications: return true
        default: return false
        }
    }

    /// These styles draw map pictures, which MapKit delivers some seconds after they are first asked for.
    var drawsMapPictures: Bool { self == .map || self == .money }

    /// The first of the two demo lines this style loops. Always even, so the pair is (n, n + 1).
    var demoFirstLine: Int {
        switch self {
        case .ship: return 0
        case .fisheye, .codestyleVisual, .messages: return 2
        // Constellation starts a new figure every 14 words; lines 4–5 hold 13, so its still shows a whole one.
        case .visual, .branches, .constellation, .money, .notifications: return 4
        case .codestyle, .map: return 6
        case .fisheyeVisual, .web: return 8
        }
    }
}
