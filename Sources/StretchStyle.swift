import SwiftUI

/// Placeholder: the sung words of the line, until this style is drawn.
struct StretchStyle: View {
    let context: StyleContext

    var body: some View {
        Text(context.sung.map(\.text).joined(separator: " "))
            .font(context.font(context.band * 0.12 * context.scale))
            .foregroundStyle(Color(nsColor: context.settings.textColor))
            .frame(width: context.canvas.width, height: context.band)
    }
}
