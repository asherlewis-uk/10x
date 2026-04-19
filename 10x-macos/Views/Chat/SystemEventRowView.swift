import SwiftUI

struct SystemEventRowView: View {
    let event: BuilderSystemEvent

    private var iconName: String {
        switch event.kind {
        case .modeChange:
            return "arrow.triangle.2.circlepath"
        case .projectRename:
            return "pencil.line"
        case .dependencyChecklist:
            return "checklist"
        }
    }

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)

                    Text(event.title)
                        .font(Theme.geistMono(11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }

                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.geist(11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.spacingMD)
            .padding(.vertical, Theme.spacingSM)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(Theme.textPrimary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(Theme.textPrimary.opacity(0.06), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
    }
}
