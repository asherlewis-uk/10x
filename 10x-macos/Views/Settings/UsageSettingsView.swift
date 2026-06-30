import SwiftUI

struct UsageSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Usage") {
                SettingsMetaChip(text: "Local")
            }

            SettingsPanel("Local Diagnostics") {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    Text("Usage tracking is local diagnostics only.")
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("11x is an unlimited single-user local cockpit. Usage data is stored locally and never gates features, generation, or export.")
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Theme.spacingXS) {
                        localStatusRow(icon: "creditcard.fill", text: "No billing or credits")
                        localStatusRow(icon: "lock.fill", text: "No paywalls or subscriptions")
                        localStatusRow(icon: "server.rack", text: "No hosted vendor backend dependency")
                        localStatusRow(icon: "chart.bar", text: "Local usage logs only")
                    }
                    .padding(.top, Theme.spacingSM)
                }
            }
        }
    }

    private func localStatusRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .frame(width: 16, height: 16)

            Text(text)
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
    }
}
