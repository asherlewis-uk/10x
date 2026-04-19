import SwiftUI

extension View {
    @ViewBuilder
    func tenXGlassRect(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint ?? .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        #else
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint ?? .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        #endif
    }

    @ViewBuilder
    func tenXGlassCapsule(tint: Color? = nil) -> some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint), in: .capsule)
            } else {
                self.glassEffect(.regular, in: .capsule)
            }
        } else {
            self.background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(tint ?? .clear)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        #else
        self.background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(tint ?? .clear)
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        #endif
    }
}
