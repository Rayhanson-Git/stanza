import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--self-check") {
    runSelfCheck()
    exit(0)
}
// A mistyped diagnostic command must not fall through and start the menu-bar app.
func usage() -> Never {
    print("""
        usage: Stanza --self-check
               Stanza --lyrics "<artist>" "<title>" <seconds>
               Stanza --render "<style>" <output.png> [seconds]
               Stanza --render-gallery <output.png> [view] [<width>x<height>]
               Stanza --render-tile "<style>" <output.png>
        styles: \(LyricStyle.allCases.map(\.rawValue).joined(separator: ", "))
        views: \(Diagnostics.galleryViews.joined(separator: ", "))
        """)
    exit(2)
}
if let flag = arguments.firstIndex(of: "--lyrics") {
    guard arguments.count > flag + 3, let seconds = Double(arguments[flag + 3]) else { usage() }
    Diagnostics.lookUp(artist: arguments[flag + 1], title: arguments[flag + 2], seconds: seconds)
    exit(0)
}
if let flag = arguments.firstIndex(of: "--render") {
    guard arguments.count > flag + 2, let style = LyricStyle(rawValue: arguments[flag + 1]) else { usage() }
    let requested = arguments.count > flag + 3 ? Double(arguments[flag + 3]) : Diagnostics.defaultRenderPosition
    guard let position = requested else { usage() }
    // Top-level code runs on the main thread.
    exit(MainActor.assumeIsolated { Diagnostics.render(style: style, to: arguments[flag + 2], position: position) } ? 0 : 1)
}
if let flag = arguments.firstIndex(of: "--render-gallery") {
    guard arguments.count > flag + 1 else { usage() }
    // Options that follow may be "-key value" preference overrides, which are not ours to parse.
    let extras = arguments.dropFirst(flag + 2).prefix { !$0.hasPrefix("-") }
    let view = extras.first { Diagnostics.galleryViews.contains($0) }
    let size = extras.compactMap(Diagnostics.size(from:)).first
    guard extras.count == (view == nil ? 0 : 1) + (size == nil ? 0 : 1) else { usage() }
    exit(MainActor.assumeIsolated { Diagnostics.renderGallery(to: arguments[flag + 1], showing: view ?? "none", size: size) } ? 0 : 1)
}
if let flag = arguments.firstIndex(of: "--render-tile") {
    guard arguments.count > flag + 2, let style = LyricStyle(rawValue: arguments[flag + 1]) else { usage() }
    exit(MainActor.assumeIsolated { Diagnostics.renderTile(style: style, to: arguments[flag + 2]) } ? 0 : 1)
}

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
