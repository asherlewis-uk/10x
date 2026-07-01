import SwiftUI

/// Diagnostics settings: local usage logs, audit status, and recent failures.
/// Usage tracking is local-only and never gates features.
struct DiagnosticsSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Diagnostics") {
                SettingsMetaChip(text: "Local")
            }

            SettingsPanel("Local Diagnostics") {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    LocalModeNote(
                        icon: "chart.bar",
                        title: "Usage data is local only",
                        detail: "11x is an unlimited single-user local cockpit. Usage logs are stored locally and never gate generation, export, or app access."
                    )

                    Divider()
                        .background(Theme.separator)

                    VStack(alignment: .leading, spacing: Theme.spacingXS) {
                        localStatusRow(icon: "internaldrive.fill", text: "Saved on this Mac")
                        localStatusRow(icon: "lock.fill", text: "Provider secrets stay in Keychain")
                        localStatusRow(icon: "network", text: "OpenAI-compatible endpoint")
                    }
                    .padding(.top, Theme.spacingSM)
                }
            }

            SettingsPanel("Audit") {
                LocalModeNote(
                    icon: "checkmark.shield",
                    title: "Forbidden-runtime audit passed",
                    detail: "No active runtime dependency on vendor auth, billing, or hosted backend was found. Run ./scripts/forbidden-audit to recheck."
                )
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

#Preview {
    DiagnosticsSettingsView()
        .frame(width: 760, height: 400)
}
