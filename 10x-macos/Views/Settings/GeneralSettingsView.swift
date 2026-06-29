import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AuthManager.self) private var auth
    @State private var selectedUpdateChannel = AppUpdateChannel.preferredChannel()

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Settings")
            profileCard
            supportCard
            updatesCard
            sessionCard
        }
        .task {
            // Billing refresh disabled in 11x local cockpit
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        SettingsPanel("Account") {
            HStack(alignment: .center, spacing: Theme.spacingLG) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                    Text(initials)
                        .font(Theme.geist(20, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.userEmail ?? "No email on file")
                        .font(Theme.geist(18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Unlimited local cockpit")
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()
            }

            VStack(spacing: Theme.spacingSM) {
                if let email = auth.userEmail {
                    SettingsInsetRow {
                        accountRow(label: "Email", value: email)
                    }
                }

                if let userId = auth.userId {
                    SettingsInsetRow {
                        accountRow(label: "User ID", value: userId, monospace: true)
                    }
                }
            }
        }
    }

    private var supportCard: some View {
        SettingsPanel("Support") {
            SettingsInsetRow {
                accountRow(label: "Email", value: "support@example.invalid")
            }
        }
    }

    // MARK: - Updates

    private var updatesCard: some View {
        SettingsPanel("Updates") {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacingMD) {
                    Text("Update Channel")
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer()

                    SettingsMetaChip(text: "Build default: \(Config.defaultUpdateChannel.title)")
                }

                Picker("Update Channel", selection: updateChannelBinding) {
                    ForEach(AppUpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedUpdateChannel.summary)
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: Theme.spacingSM) {
                    SettingsInsetRow {
                        accountRow(label: "Version", value: Config.appVersion, monospace: true)
                    }

                    SettingsInsetRow {
                        accountRow(label: "Build", value: Config.appBuild, monospace: true)
                    }

                    SettingsInsetRow {
                        accountRow(label: "Feed", value: Config.sparkleFeedURL)
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    private var sessionCard: some View {
        SettingsPanel("Session") {
            Button(role: .destructive) {
                auth.signOut()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                    Text("Sign Out")
                        .font(Theme.geist(13, weight: .medium))
                }
                .foregroundStyle(Theme.error)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.error.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.error.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func accountRow(label: String, value: String, monospace: Bool = false) -> some View {
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

    private func defaultPlanStateLabel(for plan: BillingPlan) -> String {
        plan.priceCents == 0 ? "Free plan" : "Current plan"
    }

    private var initials: String {
        guard let email = auth.userEmail else { return "?" }
        let parts = email.split(separator: "@").first?.split(separator: ".") ?? []
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(email.prefix(2)).uppercased()
    }

    private var updateChannelBinding: Binding<AppUpdateChannel> {
        Binding(
            get: { selectedUpdateChannel },
            set: { newValue in
                selectedUpdateChannel = newValue
                newValue.persist()
            }
        )
    }
}
