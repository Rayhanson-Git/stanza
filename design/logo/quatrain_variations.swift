import AppKit
import SwiftUI

// Variations on the Quatrain logo for Stanza: four lines of a verse, sung word by word.
// Drawn on Apple's macOS icon grid (measured from Notes and Calendar: an 824 pt body inset 100 pt on a 1024 canvas).
// Build:          swiftc -O -target arm64-apple-macosx15.0 quatrain_variations.swift -o /tmp/quatrain
// Sheets:         /tmp/quatrain <output folder>
// App icon:       mkdir -p /tmp/Stanza.iconset && /tmp/quatrain --icon /tmp/Stanza.iconset ../../Resources
//                 iconutil -c icns /tmp/Stanza.iconset -o ../../Resources/Stanza.icns
// The chosen logo is C (Bold three) in the Night scheme; see `chosenForm` and `chosenScheme`.

func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: opacity)
}

enum Grid {
    static let canvas: CGFloat = 1024, body: CGFloat = 824, radius: CGFloat = 185, centre: CGFloat = 512
}

// MARK: Colour schemes

struct Scheme {
    let name: String
    let note: String
    let ground: [Color]
    let radial: Bool
    let ink: Color
    let accent: Color
    let dim: Double
    let glow: Double
}

let schemes: [Scheme] = [
    Scheme(name: "Night", note: "The original: navy, cream, crimson.", ground: [hex(0x10202B), hex(0x0A0F14)], radial: false,
           ink: hex(0xEADCC8), accent: hex(0xC2302F), dim: 0.22, glow: 0.7),
    Scheme(name: "Deep teal", note: "Deep teal under cream and crimson.", ground: [hex(0x17504F), hex(0x0B2B2C)], radial: false,
           ink: hex(0xEADCC8), accent: hex(0xD03A36), dim: 0.24, glow: 0.6),
    Scheme(name: "Paper", note: "Light icon: cream page, navy ink, crimson word.", ground: [hex(0xF6EEE2), hex(0xE6D6BF)], radial: false,
           ink: hex(0x0E1A24), accent: hex(0xB7282A), dim: 0.18, glow: 0.35),
    Scheme(name: "Logo kit", note: "Graphite fading to green-black.", ground: [hex(0x2C2C2C), hex(0x171717), hex(0x06110C)], radial: true,
           ink: hex(0xEADCC8), accent: hex(0xC2302F), dim: 0.2, glow: 0.7),
    Scheme(name: "Crimson", note: "Red ground, cream lines, the sung word in night navy.", ground: [hex(0xB8302F), hex(0x6A1416)], radial: false,
           ink: hex(0xF4E9DA), accent: hex(0x0A0F14), dim: 0.28, glow: 0),
    Scheme(name: "Tide", note: "No red: teal lines, the sung word in cream.", ground: [hex(0x0F3D3E), hex(0x0A0F14)], radial: false,
           ink: hex(0x7FB3B8), accent: hex(0xF4E9DA), dim: 0.26, glow: 0.55),
    Scheme(name: "Plum", note: "Dark purple with a rose-crimson word.", ground: [hex(0x2B1742), hex(0x110A1C)], radial: false,
           ink: hex(0xEADCC8), accent: hex(0xE0475B), dim: 0.22, glow: 0.7),
    Scheme(name: "Ink", note: "Black and white; the sung word glows.", ground: [hex(0x1C1C1C), hex(0x050505)], radial: false,
           ink: hex(0xF2F2F2, 0.9), accent: hex(0xFFFFFF), dim: 0.2, glow: 0.8),
]

// MARK: Forms

enum Kind { case sung, lit, dim }

struct Segment {
    let width: CGFloat
    let kind: Kind
}

struct Line {
    let indent: CGFloat
    let segments: [Segment]
    var tilt: Double = 0
}

func sung(_ widths: CGFloat...) -> [Segment] { widths.map { Segment(width: $0, kind: .sung) } }
func lit(_ width: CGFloat) -> Segment { Segment(width: width, kind: .lit) }
func dim(_ widths: CGFloat...) -> [Segment] { widths.map { Segment(width: $0, kind: .dim) } }

struct Form {
    let name: String
    let note: String
    let lines: [Line]
    var thickness: CGFloat = 52
    var spacing: CGFloat = 92
    var gap: CGFloat = 26
    var centred = false
    var left: CGFloat = 276
    var liftLit: CGFloat = 0
    var litTilt: Double = 0
    var caret = false
}

let forms: [Form] = [
    Form(name: "A  Original", note: "Four lines; the third word of the last line is lit.",
         lines: [Line(indent: 0, segments: sung(448)), Line(indent: 44, segments: sung(366)), Line(indent: 0, segments: sung(472)),
                 Line(indent: 44, segments: sung(120) + [lit(150)] + dim(110))]),
    Form(name: "B  Words", note: "Every line broken into words, so it reads as lyrics, not a text icon.",
         lines: [Line(indent: 0, segments: sung(108, 150, 92, 98)), Line(indent: 44, segments: sung(140, 96, 150)),
                 Line(indent: 0, segments: sung(92, 128, 108, 120)), Line(indent: 44, segments: sung(118) + [lit(150)] + dim(92))],
         gap: 22),
    Form(name: "C  Bold three", note: "Three heavier lines; holds up best at Finder and list sizes.",
         lines: [Line(indent: 0, segments: sung(470)), Line(indent: 40, segments: sung(372)), Line(indent: 0, segments: sung(150) + [lit(206)])],
         thickness: 78, spacing: 128, gap: 34),
    Form(name: "D  Centred", note: "Set like a poem on a page; the current line is second, the rest still to come.",
         lines: [Line(indent: 0, segments: sung(380)), Line(indent: 0, segments: sung(150) + [lit(160)] + dim(110)),
                 Line(indent: 0, segments: dim(470)), Line(indent: 0, segments: dim(290))],
         centred: true),
    Form(name: "E  Stair", note: "Each line steps in, like the indents of a verse.",
         lines: [Line(indent: 0, segments: sung(372)), Line(indent: 56, segments: sung(352)), Line(indent: 112, segments: sung(330)),
                 Line(indent: 168, segments: sung(112) + [lit(150)])],
         left: 250),
    Form(name: "F  Caret", note: "The lit word with a typing caret after it.",
         lines: [Line(indent: 0, segments: sung(448)), Line(indent: 44, segments: sung(366)), Line(indent: 0, segments: sung(472)),
                 Line(indent: 44, segments: sung(130) + [lit(170)])],
         caret: true),
    Form(name: "G  Lifted", note: "The sung word jumps up off its line, the way words land in the app.",
         lines: [Line(indent: 0, segments: sung(448)), Line(indent: 44, segments: sung(366)), Line(indent: 0, segments: sung(472)),
                 Line(indent: 44, segments: sung(120) + [lit(150)] + dim(110))],
         spacing: 104, liftLit: 22, litTilt: -6),
    Form(name: "H  Kinetic", note: "Each line tipped a few degrees, like the Ship style on the lock screen.",
         lines: [Line(indent: 0, segments: sung(430), tilt: -3), Line(indent: 50, segments: sung(352), tilt: 2.5),
                 Line(indent: 10, segments: sung(456), tilt: -2), Line(indent: 50, segments: sung(118) + [lit(156)] + dim(100), tilt: 3)]),
]

// MARK: Drawing

struct QuatrainMark: View {
    let form: Form
    let ink: Color, accent: Color, dim: Double, glow: Double

    var body: some View {
        let count = CGFloat(form.lines.count)
        let firstRow = Grid.centre - (count - 1) * form.spacing / 2
        ZStack(alignment: .topLeading) {
            ForEach(form.lines.indices, id: \.self) { index in
                line(form.lines[index], centreY: firstRow + CGFloat(index) * form.spacing)
            }
        }
        .frame(width: Grid.canvas, height: Grid.canvas, alignment: .topLeading)
    }

    private func width(of line: Line) -> CGFloat {
        line.segments.reduce(0) { $0 + $1.width } + form.gap * CGFloat(max(0, line.segments.count - 1))
    }

    private func line(_ line: Line, centreY: CGFloat) -> some View {
        let total = width(of: line)
        let startX = form.centred ? Grid.centre - total / 2 : form.left + line.indent
        var x = startX
        let pieces: [(x: CGFloat, segment: Segment)] = line.segments.map { segment in
            defer { x += segment.width + form.gap }
            return (x, segment)
        }
        let caretX = x - form.gap + 22
        return ZStack(alignment: .topLeading) {
            ForEach(pieces.indices, id: \.self) { index in
                piece(pieces[index].segment, x: pieces[index].x, centreY: centreY)
            }
            if form.caret && line.segments.contains(where: { $0.kind == .lit }) {
                Capsule().fill(accent).frame(width: 18, height: form.thickness * 1.9)
                    .offset(x: caretX, y: centreY - form.thickness * 0.95)
            }
        }
        .frame(width: Grid.canvas, height: Grid.canvas, alignment: .topLeading)
        .rotationEffect(.degrees(line.tilt), anchor: UnitPoint(x: (startX + total / 2) / Grid.canvas, y: centreY / Grid.canvas))
    }

    @ViewBuilder
    private func piece(_ segment: Segment, x: CGFloat, centreY: CGFloat) -> some View {
        let capsule = Capsule().frame(width: segment.width, height: form.thickness)
        switch segment.kind {
        case .sung:
            capsule.foregroundStyle(ink).offset(x: x, y: centreY - form.thickness / 2)
        case .dim:
            capsule.foregroundStyle(ink.opacity(dim)).offset(x: x, y: centreY - form.thickness / 2)
        case .lit:
            capsule.foregroundStyle(accent)
                .shadow(color: accent.opacity(glow), radius: glow > 0 ? 26 : 0)
                .rotationEffect(.degrees(form.litTilt))
                .offset(x: x, y: centreY - form.thickness / 2 - form.liftLit)
        }
    }
}

struct Icon: View {
    let form: Form
    let scheme: Scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Grid.radius, style: .continuous)
                .fill(ground)
                .frame(width: Grid.body, height: Grid.body)
                .shadow(color: .black.opacity(0.32), radius: 14, y: 12)
            QuatrainMark(form: form, ink: scheme.ink, accent: scheme.accent, dim: scheme.dim, glow: scheme.glow)
        }
        .frame(width: Grid.canvas, height: Grid.canvas)
    }

    private var ground: AnyShapeStyle {
        scheme.radial
            ? AnyShapeStyle(RadialGradient(colors: scheme.ground, center: .init(x: 0.4, y: 0.3), startRadius: 30, endRadius: 620))
            : AnyShapeStyle(LinearGradient(colors: scheme.ground, startPoint: .top, endPoint: .bottom))
    }
}

extension View {
    /// Draws a 1024-point design at `side` points.
    func at(_ side: CGFloat) -> some View {
        frame(width: Grid.canvas, height: Grid.canvas).scaleEffect(side / Grid.canvas).frame(width: side, height: side)
    }
}

// MARK: Sheets

struct Tile: View {
    let title: String
    let note: String
    let form: Form
    let scheme: Scheme
    let showMenuBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Text(note).font(.system(size: 14)).foregroundStyle(.white.opacity(0.68))
                .frame(width: 380, height: 40, alignment: .topLeading)
            Icon(form: form, scheme: scheme).at(380)
            HStack(spacing: 14) {
                small(64, light: false)
                small(32, light: false)
                small(16, light: true)
                if showMenuBar {
                    QuatrainMark(form: form, ink: .black, accent: .black, dim: 0.35, glow: 0).at(26)
                        .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.86)))
                    QuatrainMark(form: form, ink: .white, accent: .white, dim: 0.35, glow: 0).at(26)
                        .frame(width: 64, height: 64).background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.24)))
                }
            }
        }
        .padding(18)
    }

    private func small(_ side: CGFloat, light: Bool) -> some View {
        Icon(form: form, scheme: scheme).at(side).frame(width: 64, height: 64)
            .background(RoundedRectangle(cornerRadius: 9).fill(light ? Color(white: 0.93) : Color(white: 0.17)))
    }
}

struct Sheet: View {
    let heading: String
    let subheading: String
    let tiles: [Tile]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading).font(.system(size: 46, weight: .medium, design: .serif)).foregroundStyle(.white)
                Text(subheading).font(.system(size: 16)).foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 18)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) { ForEach(0..<4, id: \.self) { tiles[$0] } }
                HStack(alignment: .top, spacing: 18) { ForEach(4..<8, id: \.self) { tiles[$0] } }
            }
        }
        .padding(42)
        .background(Color(white: 0.07))
    }
}

@MainActor
func write(_ view: some View, to path: String, scale: CGFloat = 1) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
    renderer.scale = scale
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        print("could not render \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (\(image.width)x\(image.height))")
    } catch {
        print("could not write \(path): \(error.localizedDescription)")
    }
}

/// The chosen logo: C, Bold three, in the Night scheme.
let chosenForm = forms[2]
let chosenScheme = schemes[0]

/// The mark cropped to its own bounds, in one colour, `height` points tall, for the menu bar.
/// The Bold three mark spans x 276…746 and y 345…679 on the 1024 canvas, centred on (511, 512).
struct MenuBarGlyph: View {
    let height: CGFloat
    private let crop = CGSize(width: 490, height: 350)

    var body: some View {
        QuatrainMark(form: chosenForm, ink: .black, accent: .black, dim: 0.4, glow: 0)
            .frame(width: Grid.canvas, height: Grid.canvas)
            .frame(width: crop.width, height: crop.height)
            .clipped()
            .scaleEffect(height / crop.height)
            .frame(width: crop.width * height / crop.height, height: height)
    }
}

/// Writes every size macOS asks for in an .iconset, drawn from the vector at each size rather than scaled down.
@MainActor
func writeIconset(to folder: String) {
    let sizes: [(name: String, points: CGFloat)] = [
        ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
        ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
    ]
    for size in sizes {
        write(Icon(form: chosenForm, scheme: chosenScheme).at(size.points), to: "\(folder)/icon_\(size.name).png")
    }
}

/// The 18-point menu-bar mark at 1x and 2x; the app marks it as a template so macOS tints it.
@MainActor
func writeMenuBarGlyph(to folder: String) {
    write(MenuBarGlyph(height: 18), to: "\(folder)/StanzaMenuBar.png")
    write(MenuBarGlyph(height: 18), to: "\(folder)/StanzaMenuBar@2x.png", scale: 2)
}

let arguments = CommandLine.arguments
if arguments.count > 3, arguments[1] == "--icon" {
    // --icon <iconset folder> <resources folder>
    MainActor.assumeIsolated {
        writeIconset(to: arguments[2])
        writeMenuBarGlyph(to: arguments[3])
        write(Icon(form: chosenForm, scheme: chosenScheme), to: "\(arguments[3])/StanzaLogo_1024.png")
    }
    exit(0)
}

let output = arguments.count > 1 ? arguments[1] : "."
MainActor.assumeIsolated {
    let night = schemes[0]
    write(Sheet(heading: "Quatrain: forms",
                subheading: "Eight shapes in the original colours. Small sizes and the one-colour menu-bar mark sit under each.",
                tiles: forms.map { Tile(title: $0.name, note: $0.note, form: $0, scheme: night, showMenuBar: true) }),
          to: "\(output)/quatrain_forms.png")
    let original = forms[0]
    write(Sheet(heading: "Quatrain: colours",
                subheading: "The original shape in eight colour schemes. Any scheme works with any shape.",
                tiles: schemes.enumerated().map { index, scheme in
                    Tile(title: "\(index + 1)  \(scheme.name)", note: scheme.note, form: original, scheme: scheme, showMenuBar: false)
                }),
          to: "\(output)/quatrain_colours.png")
}
