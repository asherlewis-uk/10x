import SwiftUI

/// A multi-line local-mode note with an accent icon, title, and optional detail.
/// Use inside settings cards and empty states to explain local-first behavior
/// with positive framing instead of lists of disabled SaaS features.
struct LocalModeNote: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacingSM) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if let detail {
                    Text(detail)
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
    }
}

#Preview("Local Mode Note") {
    VStack(spacing: 12) {
        LocalModeNote(
            icon: "lock.fill",
            title: "Provider secrets stay in Keychain",
            detail: "API keys are stored in the system keychain and never appear in the UI or exports."
        )

        LocalModeNote(
            icon: "internaldrive.fill",
            title: "Saved on this Mac",
            detail: "Projects, generations, and assets live in your local Application Support folder."
        )
    }
    .padding()
    .background(Theme.surface)
}
