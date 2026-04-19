import SwiftUI

struct IntegrationApprovalView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth

    let approval: BuilderViewModel.IntegrationApprovalState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            header
            summary
            actions
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.spacingSM) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.warning)

            Text("INTEGRATION APPROVAL")
                .font(Theme.geistMono(10, weight: .semibold))
                .foregroundStyle(Theme.warning)

            Spacer(minLength: 0)

            Text(approval.request.integrationName.uppercased())
                .font(Theme.geistMono(10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(approval.request.prompt)
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Approve or deny this access request. Your choice stays out of the chat history.")
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.spacingSM) {
            Button {
                respond(approved: false)
            } label: {
                Text(approval.request.denyLabel)
                    .font(Theme.geist(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.04))
                    }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                respond(approved: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))

                    Text(approval.request.approveLabel)
                        .font(Theme.geist(12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
            .fill(Theme.warning.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Theme.warning.opacity(0.22), lineWidth: 1)
            }
    }

    private func respond(approved: Bool) {
        Task { @MainActor in
            guard let token = await auth.validAccessToken() else { return }
            viewModel.respondToIntegrationApproval(approved, accessToken: token)
        }
    }
}
