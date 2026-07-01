import SwiftUI

/// A simple, intentional 11x wordmark used in place of the legacy `10XbuilderLogo`
/// asset until a final mark is produced. It renders as a small rounded rect
/// containing "11x" and scales from the tab bar (18pt) up to the login hero (64pt).
struct AppIconMark: View {
    let size: CGFloat
    var isFilled: Bool = false

    private var fontSize: CGFloat { size * 0.42 }
    private var cornerRadius: CGFloat { size * 0.22 }

    var body: some View {
        ZStack {
            Group {
                if isFilled {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.accent)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Theme.accent, lineWidth: max(1, size * 0.06))
                }
            }

            Text("11x")
                .font(Theme.geist(fontSize, weight: .bold))
                .foregroundStyle(isFilled ? Color.black : Theme.accent)
                .allowsTightening(true)
        }
        .frame(width: size, height: size)
    }
}

#Preview("App Icon Mark", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        AppIconMark(size: 64, isFilled: true)
        AppIconMark(size: 32)
        AppIconMark(size: 18)
    }
    .padding()
    .background(Theme.surface)
}
