import SwiftUI

struct GeneralSettingsView: View {
    @State private var databasePath = ""
    @State private var assetStoragePath = ""
    @State private var providerStatus = ""
    @State private var isLoading = true

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Settings")
            cockpitCard
            readinessCard
            versionCard
        }
        .task {
            await loadLocalStatus()
        }
    }

    // MARK: - Local Cockpit Card

    private var cockpitCard: some View {
        SettingsPanel("Local Cockpit") {
            HStack(alignment: .center, spacing: Theme.spacingLG) {
                AppIconMark(size: 48, isFilled: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppIdentity.displayName)
                        .font(Theme.geist(18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(AppIdentity.localBadgeDetails.joined(separator: " · "))
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }

            VStack(spacing: Theme.spacingSM) {
                SettingsInsetRow {
                    statusRow(label: "Mode", value: "Single-user local cockpit")
                }

                SettingsInsetRow {
                    statusRow(label: "Workspace", value: "Saved on this Mac")
                }

                SettingsInsetRow {
                    statusRow(
                        label: "Provider",
                        value: providerStatus.isEmpty ? "Loading..." : providerStatus,
                        monospace: providerStatus.contains("/")
                    )
                }
            }
        }
    }

    // MARK: - Readiness Card

    private var readinessCard: some View {
        SettingsPanel("Generation Readiness") {
            VStack(spacing: Theme.spacingSM) {
                LocalModeNote(
                    icon: "internaldrive.fill",
                    title: "Local SQLite database",
                    detail: databasePath
                )

                LocalModeNote(
                    icon: "folder.fill",
                    title: "Local asset storage",
                    detail: assetStoragePath
                )
            }
        }
    }

    // MARK: - Version Card

    private var versionCard: some View {
        SettingsPanel("Version") {
            VStack(spacing: Theme.spacingSM) {
                SettingsInsetRow {
                    statusRow(label: "Version", value: Config.appVersion, monospace: true)
                }

                SettingsInsetRow {
                    statusRow(label: "Build", value: Config.appBuild, monospace: true)
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusRow(label: String, value: String, monospace: Bool = false) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            Text(label)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(monospace ? Theme.geistMono(12, weight: .semibold) : Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func loadLocalStatus() async {
        let dbURL = CockpitDatabase.defaultDatabaseURL()
        let assetURL = LocalAssetStorage.defaultAssetRootURL()

        let repository = ProviderConfigRepository()
        let config = await repository.loadConfig()
        let hasKey = await repository.apiKey() != nil

        await MainActor.run {
            databasePath = dbURL.path
            assetStoragePath = assetURL.path
            if let config {
                let ready = hasKey && !config.baseURL.isEmpty && !config.model.isEmpty
                providerStatus = ready
                    ? "\(config.model) configured"
                    : "Provider setup required"
            } else {
                providerStatus = "Provider not configured"
            }
            isLoading = false
        }
    }
}
