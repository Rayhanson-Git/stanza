import AppKit
import SwiftUI

// Draws the README banner and the GitHub social preview from the app icon and four style frames in assets/.
// Run from the repository root, after the frames exist (see the README's "Developer tools"):
//   swiftc -O -swift-version 5 -target arm64-apple-macosx15.0 design/banner/banner.swift -o /tmp/stanza-banner
//   /tmp/stanza-banner
// Writes assets/banner.png (1600x640, rounded corners) and assets/social-preview.png (1280x640, full bleed).

func hex(_ value: UInt32) -> Color {
    Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: 1)
}

enum Palette {
    static let navy = hex(0x0A0F14), teal = hex(0x2E6F73)
    static let lightTeal = hex(0x7FB3B8), cream = hex(0xEADCC8), crimson = hex(0xC2302F)
}

/// The style frames in the strip: caption, file made by `Stanza --render`, and which part of it to centre on
/// (0...1 across); the Map card is wide, so its strip frame leans left to keep the turn card in view.
let frames: [(caption: String, path: String, centre: CGFloat)] = [
    ("Messages", "assets/style-messages.png", 0.5), ("Map", "assets/style-map.png", 0.38),
    ("Codestyle", "assets/style-codestyle.png", 0.5), ("Notifications", "assets/style-notifications.png", 0.5),
]
let logoPath = "Resources/StanzaLogo_1024.png"

func loadImage(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOfFile: path) else {
        print("missing \(path): run from the repository root after rendering the frames")
        exit(1)
    }
    return image
}

struct Layout {
    let width: CGFloat, height: CGFloat
    let margin: CGFloat, logo: CGFloat, title: CGFloat, tagline: CGFloat
    let frameGap: CGFloat, frameAspect: CGFloat, corner: CGFloat

    var frameWidth: CGFloat { (width - 2 * margin - CGFloat(frames.count - 1) * frameGap) / CGFloat(frames.count) }
    var frameHeight: CGFloat { frameWidth / frameAspect }

    static let banner = Layout(width: 1600, height: 640, margin: 64, logo: 196, title: 104, tagline: 25, frameGap: 24,
                               frameAspect: 1.4, corner: 28)
    static let social = Layout(width: 1280, height: 640, margin: 56, logo: 188, title: 96, tagline: 23, frameGap: 20,
                               frameAspect: 1.15, corner: 0)
}

struct Banner: View {
    let layout: Layout
    let logo: NSImage
    let shots: [(caption: String, image: NSImage, centre: CGFloat)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 22) {
                // The icon file carries its own transparent margin, so it is drawn a little larger than it looks.
                Image(nsImage: logo).resizable().interpolation(.high).frame(width: layout.logo, height: layout.logo)
                    .padding(.leading, -layout.logo * 0.1)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stanza").font(.system(size: layout.title, weight: .semibold, design: .serif)).foregroundStyle(Palette.cream)
                    Text("Time-synced lyrics, word by word, on your Mac's desktop and lock screen.")
                        .font(.system(size: layout.tagline, weight: .medium)).foregroundStyle(Palette.lightTeal)
                    HStack(spacing: 10) {
                        Text("13 styles")
                        Circle().fill(Palette.crimson).frame(width: 6, height: 6)
                        Text("Spotify and Apple Music")
                        Circle().fill(Palette.crimson).frame(width: 6, height: 6)
                        Text("macOS 15+")
                    }
                    .font(.system(size: layout.tagline * 0.72, weight: .medium)).foregroundStyle(Palette.lightTeal.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: layout.frameGap) {
                ForEach(shots.indices, id: \.self) { index in frame(shots[index]) }
            }
        }
        .padding(.horizontal, layout.margin)
        .padding(.top, layout.margin * 0.55)
        .padding(.bottom, layout.margin * 0.8)
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: layout.corner, style: .continuous).fill(Palette.navy))
    }

    /// One style frame, cut to the lyric band around `centre`, with its name under it.
    private func frame(_ shot: (caption: String, image: NSImage, centre: CGFloat)) -> some View {
        let scale = layout.frameHeight / shot.image.size.height
        let drawnWidth = shot.image.size.width * scale
        let left = min(max(shot.centre * drawnWidth - layout.frameWidth / 2, 0), drawnWidth - layout.frameWidth)
        return VStack(alignment: .leading, spacing: 9) {
            Image(nsImage: shot.image).resizable().interpolation(.high)
                .frame(width: drawnWidth, height: layout.frameHeight)
                .offset(x: -left)
                .frame(width: layout.frameWidth, height: layout.frameHeight, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.teal, lineWidth: 1))
            Text(shot.caption).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.lightTeal)
        }
    }
}

@MainActor
func write(_ layout: Layout, to path: String, logo: NSImage, shots: [(caption: String, image: NSImage, centre: CGFloat)]) {
    let renderer = ImageRenderer(content: Banner(layout: layout, logo: logo, shots: shots).environment(\.colorScheme, .dark))
    renderer.scale = 1
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("could not render \(path)")
        exit(1)
    }
    guard image.width == Int(layout.width), image.height == Int(layout.height) else {
        print("\(path) came out \(image.width)x\(image.height), expected \(Int(layout.width))x\(Int(layout.height))")
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(image.width)x\(image.height))")
    } catch {
        print("could not write \(path): \(error.localizedDescription)")
        exit(1)
    }
}

MainActor.assumeIsolated {
    let logo = loadImage(logoPath)
    let shots = frames.map { (caption: $0.caption, image: loadImage($0.path), centre: $0.centre) }
    write(.banner, to: "assets/banner.png", logo: logo, shots: shots)
    write(.social, to: "assets/social-preview.png", logo: logo, shots: shots)
}
