import AppKit
import SwiftUI

// Draws the background of the install window that opens with the Stanza disk image: the app on the left,
// an arrow, Applications on the right (Finder places the two icons over the marked spots).
// Run from the repository root:
//   swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 design/dmg/dmg_background.swift -o /tmp/stanza-dmg-bg
//   /tmp/stanza-dmg-bg && tiffutil -cathidpicheck /tmp/dmg-bg.png /tmp/dmg-bg@2x.png -out Resources/DMGBackground.tiff
// scripts/release.sh uses the same window size and icon spots.

let size = CGSize(width: 640, height: 400)
let iconCentreY: CGFloat = 186
let appX: CGFloat = 170, applicationsX: CGFloat = 470

func hex(_ value: UInt32) -> Color {
    Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: 1)
}

/// The Paper colours of the logo: Finder draws the icon names in dark text, so the window stays light.
let paper = [hex(0xF6EEE2), hex(0xE6D6BF)], navy = hex(0x10202B), crimson = hex(0xC2302F)

struct Background: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: paper, startPoint: .top, endPoint: .bottom)
            arrow.position(x: (appX + applicationsX) / 2, y: iconCentreY)
            Text("Drag Stanza into Applications")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(navy.opacity(0.75))
                .position(x: size.width / 2, y: 330)
        }
        .frame(width: size.width, height: size.height)
    }

    private var arrow: some View {
        HStack(spacing: 0) {
            Capsule().fill(navy.opacity(0.35)).frame(width: 96, height: 4)
            Image(systemName: "chevron.right").font(.system(size: 22, weight: .bold)).foregroundStyle(crimson)
        }
    }
}

// Top-level code runs on the main thread.
MainActor.assumeIsolated {
    for (scale, suffix) in [(1.0, ""), (2.0, "@2x")] {
        let renderer = ImageRenderer(content: Background())
        renderer.scale = scale
        guard let image = renderer.cgImage else { fatalError("could not draw the background") }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: "/tmp/dmg-bg\(suffix).png"))
    }
}
print("wrote /tmp/dmg-bg.png and /tmp/dmg-bg@2x.png")
