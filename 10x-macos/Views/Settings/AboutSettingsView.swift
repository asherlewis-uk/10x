import SwiftUI

/// About settings: 11x identity, local-first fork notice, upstream relationship.
struct AboutSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("About")

            HStack(alignment: .center, spacing: Theme.spacingLG) {
                AppIconMark(size: 56, isFilled: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppIdentity.displayName)
                        .font(Theme.geist(20, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Unlimited single-user local cockpit")
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }

            SettingsPanel("Identity") {
                VStack(spacing: Theme.spacingSM) {
                    SettingsInsetRow {
                        statusRow(label: "App name", value: AppIdentity.displayName)
                    }
                    SettingsInsetRow {
                        statusRow(label: "Bundle ID", value: AppIdentity.bundleIdentifier, monospace: true)
                    }
                    SettingsInsetRow {
                        statusRow(label: "URL scheme", value: AppIdentity.urlScheme, monospace: true)
                    }
                    SettingsInsetRow {
                        statusRow(label: "Version", value: Config.appVersion)
                    }
                    SettingsInsetRow {
                        statusRow(label: "Build", value: Config.appBuild)
                    }
                }
            }

            SettingsPanel("Local-first fork notice") {
                LocalModeNote(
                    icon: "info.circle",
                    title: "11x is a local-first fork of 10x",
                    detail: "This repository started as a fork of the original 10x source. The built app is a separate macOS app with its own identity, app support directory, preferences, and Keychain namespace."
                )
            }

            SettingsPanel("Upstream") {
                Text("See LICENSE in the repository root for upstream license and attribution notices.")
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

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
}

#Preview {
    AboutSettingsView()
        .frame(width: 760, height: 500)
}
