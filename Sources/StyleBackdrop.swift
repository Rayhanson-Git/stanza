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
