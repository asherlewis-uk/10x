import SwiftUI

struct UsageSettingsView: View {
    @Environment(AuthManager.self) private var auth

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
                }
            }
        }
    }
}
