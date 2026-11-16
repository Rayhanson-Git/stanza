import SwiftUI

extension LyricStyle {
    /// Four sRGB colours per style, darkest first, ending on the accent.
    var palette: [Color] {
        let hex: [UInt32]
        switch self {
        case .ship: hex = [0x071A2E, 0x0F3557, 0x1F7A8C, 0xF4B860]
        case .fisheye: hex = [0x1C0B33, 0x4A1A7A, 0xA23FB0, 0xFF9E6D]
        case .visual: hex = [0x04261F, 0x0B5C4A, 0x23A58A, 0xF0D06A]
        case .fisheyeVisual: hex = [0x2A0A1E, 0x7A1D3F, 0xD9534F, 0xF7C59F]
        case .codestyle: hex = [0x0A0D12, 0x141C2B, 0x23405F, 0xE5484D]
        case .codestyleVisual: hex = [0x0C0B17, 0x1D1840, 0x4B2F8F, 0xF06292]
        case .branches: hex = [0x04140C, 0x0C3B24, 0x1B7A45, 0xA3D977]
        case .web: hex = [0x140A05, 0x4A2110, 0xA34D1C, 0xF2B36B]
        case .constellation: hex = [0x030414, 0x0B0D3A, 0x2B2A80, 0xA99CF0]
        case .messages: hex = [0x06142B, 0x0B3A7A, 0x2F80ED, 0xA8D4FF]
        case .money: hex = [0x041409, 0x0B3D1C, 0x1F9150, 0xD4E66A]
        case .notifications: hex = [0x170D2E, 0x3F2470, 0xB0508A, 0xF5B971]
        case .map: hex = [0x0D1520, 0x1F3044, 0x3F6B6F, 0xE0B87A]
        case .stretch: hex = [0x1A0A0A, 0x5C1A1A, 0xC0392B, 0xFFD3B6]
        case .ransomNote: hex = [0x15120C, 0x3D3423, 0x8C7A55, 0xF2E6C9]
        case .ink: hex = [0x0A0E1A, 0x16223F, 0x2D4A7A, 0xD9E4F5]
        case .liquid: hex = [0x05161A, 0x0D3D45, 0x1A8C8C, 0x9FF0E0]
        case .departureBoard: hex = [0x0B0B0B, 0x22262B, 0x3A4552, 0xF2C94C]
        case .score: hex = [0x120F0A, 0x2E2718, 0x6B5B3A, 0xEDE3CC]
        case .highlighter: hex = [0x0F140A, 0x2A3A14, 0x7A9A2A, 0xF5F27A]
        case .receipt: hex = [0x111111, 0x2B2B2B, 0x5A5A5A, 0xF0EDE6]
        case .calendar: hex = [0x08101F, 0x14284D, 0x3D6FD1, 0xFF8A65]
        case .voiceMemo: hex = [0x140A1A, 0x3A1A4A, 0x8A3FB0, 0xFF6B6B]
        }
        return hex.map { Color(.sRGB, red: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255, blue: Double($0 & 0xFF) / 255) }
    }

    /// The flat colour a tile shows before its picture is ready.
    var placeholderColor: Color { palette[1] }
}

/// The soft coloured wash behind a preview: a smooth 3×3 mesh of the style's palette, with no texture on top.
struct StyleBackdrop: View {
    private enum Metrics {
        static let jitter = 0.1
        // Which palette colour sits at each mesh point, row by row: dark corners, the accent low on the right.
        static let colorOrder = [0, 1, 0,
                                 1, 2, 2,
                                 0, 2, 3]
    }

    let style: LyricStyle

    var body: some View {
        let palette = style.palette
        MeshGradient(width: 3, height: 3, points: points, colors: Metrics.colorOrder.map { palette[$0] },
                     background: .clear, colorSpace: .device)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Corners stay put; edge midpoints slide along their edge and the centre wanders, differently per style.
    private var points: [SIMD2<Float>] {
        let seed = Double(LyricStyle.allCases.firstIndex(of: style) ?? 0) + 1
        func wander(_ salt: Double) -> Float { Float(0.5 + Metrics.jitter * sin(seed * 7.31 + salt * 2.17)) }
        return [[0, 0], [wander(1), 0], [1, 0],
                [0, wander(2)], [wander(3), wander(4)], [1, wander(5)],
                [0, 1], [wander(6), 1], [1, 1]]
    }
}
