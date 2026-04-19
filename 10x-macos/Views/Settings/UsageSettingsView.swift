import SwiftUI

struct UsageSettingsView: View {
    @Environment(BillingViewModel.self) private var billing
    @Environment(AuthManager.self) private var auth

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Usage")

            if billing.showsInitialLoader {
                loadingStateView
            } else {
                if billing.isTestMode {
                    testModeBanner
                }

                usageOverview

                if let balances = billing.summary?.balances, !balances.isEmpty {
                    balanceBuckets(balances)
                }

                recentUsage
            }
        }
        .task {
            guard billing.summary == nil else { return }
            guard let token = await auth.validAccessToken() else { return }
            await billing.refresh(accessToken: token)
        }
    }

    private var testModeBanner: some View {
        HStack(alignment: .top, spacing: Theme.spacingMD) {
            Image(systemName: "flask.fill")
                .foregroundStyle(Theme.warning)

            Text(billing.testModeNotice)
                .font(Theme.geist(13))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.spacingMD)
        .background(Theme.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                .stroke(Theme.warning.opacity(0.16), lineWidth: 1)
        )
    }

    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXXL) {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                HStack(alignment: .top, spacing: Theme.spacingLG) {
                    VStack(alignment: .leading, spacing: 8) {
                        LoadingSkeletonBlock(width: 180, height: 40)
                        LoadingSkeletonBlock(width: 128, height: 12)
                    }

                    Spacer()
                }

                HStack(spacing: Theme.spacingMD) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 6) {
                            LoadingSkeletonBlock(width: 72, height: 10)
                            LoadingSkeletonBlock(width: 110, height: 20)
                            LoadingSkeletonBlock(width: 130, height: 11)
                        }
                        .padding(Theme.spacingMD)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(Theme.spacingXL)
            .settingsPanelCard()

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                LoadingSkeletonBlock(width: 140, height: 18)

                VStack(spacing: Theme.spacingSM) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(alignment: .top, spacing: Theme.spacingMD) {
                            VStack(alignment: .leading, spacing: 4) {
                                LoadingSkeletonBlock(width: 120, height: 13)
                                LoadingSkeletonBlock(width: 180, height: 11)
                            }
                            Spacer()
                            LoadingSkeletonBlock(width: 72, height: 13)
                        }
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, Theme.spacingSM)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(Theme.spacingXL)
            .settingsPanelCard()

            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                LoadingSkeletonBlock(width: 160, height: 18)

                VStack(spacing: Theme.spacingSM) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(alignment: .center, spacing: Theme.spacingMD) {
                            VStack(alignment: .leading, spacing: 4) {
                                LoadingSkeletonBlock(width: 220, height: 13)
                                LoadingSkeletonBlock(width: 170, height: 11)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                LoadingSkeletonBlock(width: 78, height: 12)
                                LoadingSkeletonBlock(width: 60, height: 24, cornerRadius: 12)
                            }
                        }
                        .padding(Theme.spacingMD)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(Theme.spacingXL)
            .settingsPanelCard()
        }
    }

    private var usageOverview: some View {
        SettingsPanel("Overview") {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                HStack(alignment: .top, spacing: Theme.spacingXL) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(formatUsageAmount(billing.totalCredits))
                            .font(Theme.geist(40, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)

                        Text(availableBalanceSubtitle)
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()
                }

                if let plan = billing.currentPlan {
                    SettingsInsetRow {
                        HStack(alignment: .top, spacing: Theme.spacingLG) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(billing.summary?.subscription?.planStateLabel ?? defaultPlanStateLabel(for: plan))
                                    .font(Theme.geist(12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)

                                Text(plan.name)
                                    .font(Theme.geist(14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)

                                if let subscription = billing.summary?.subscription {
                                    Text("\(subscription.periodEndLabel) \(formatDate(subscription.currentPeriodEnd))")
                                        .font(Theme.geist(11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }

                            Spacer()

                            Text(plan.billingInterval.capitalized)
                                .font(Theme.geistMono(11, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                HStack(spacing: Theme.spacingMD) {
                    SettingsMetricTile(
                        label: "Today left",
                        value: billing.dailyRemaining.map { formatUsageAmount($0) } ?? "No cap",
                        detail: dailySubtitle
                    )

                    SettingsMetricTile(
                        label: "Today used",
                        value: formatUsageAmount(billing.summary?.dailyUsed ?? 0),
                        detail: billing.dailyLimit.map { "of \(formatUsageAmount($0)) limit" } ?? "No daily cap"
                    )

                    SettingsMetricTile(
                        label: "Latest spend",
                        value: latestChargeValue,
                        detail: latestChargeSubtitle
                    )
                }
            }
        }
    }

    private func balanceBuckets(_ balances: [CreditBalance]) -> some View {
        SettingsPanel("Balances") {
            VStack(spacing: Theme.spacingSM) {
                ForEach(balances) { balance in
                    SettingsInsetRow {
                        HStack(alignment: .top, spacing: Theme.spacingLG) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(balance.typeName)
                                    .font(Theme.geist(13, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)

                                if let expiry = expiryDetail(for: balance) {
                                    Text(expiry)
                                        .font(Theme.geist(11))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }

                            Spacer()

                            Text(formatUsageAmount(balance.balance))
                                .font(Theme.geistMono(13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var recentUsage: some View {
        SettingsRecentUsageSection(
            charges: billing.messageCharges,
            limit: nil,
            amountStyle: .usage(billing.usagePricingPlan)
        )
    }

    private var dailySubtitle: String {
        if let limit = billing.dailyLimit, let remaining = billing.dailyRemaining {
            let used = max(limit - remaining, 0)
            return "\(formatUsageAmount(used)) used of \(formatUsageAmount(limit))"
        }
        return "No daily cap"
    }

    private var latestChargeValue: String {
        guard let latest = billing.latestMessageCharge else { return "None" }
        return latest.totalCredits == 0 ? "Free" : formatUsageAmount(latest.totalCredits)
    }

    private var latestChargeSubtitle: String {
        guard let latest = billing.latestMessageCharge else { return "No usage yet" }
        return latest.messagePreview ?? taskLabel(for: latest.taskType)
    }

    private func defaultPlanStateLabel(for plan: BillingPlan) -> String {
        plan.priceCents == 0 ? "Free plan" : "Current plan"
    }

    private func expiryDetail(for balance: CreditBalance) -> String? {
        if balance.expiringSoon > 0, let nextExpiry = balance.nextExpiry {
            return "\(formatUsageAmount(balance.expiringSoon)) expiring \(formatDate(nextExpiry))"
        }

        if let nextExpiry = balance.nextExpiry {
            return "Next expiry \(formatDate(nextExpiry))"
        }

        return nil
    }

    private func taskLabel(for taskType: String) -> String {
        taskType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func formatUsageAmount(_ value: CreditAmount) -> String {
        BillingDisplay.usageAmount(for: value, using: billing.usagePricingPlan)
    }

    private var availableBalanceSubtitle: String {
        guard billing.usagePricingPlan?.dollarValuePerCredit ?? 0 > 0 else {
            return "credits available to use"
        }
        return "estimated value available to use"
    }

    private func formatDate(_ iso: String?) -> String {
        guard iso != nil else { return "" }
        return BillingDisplay.dateTime(iso)
    }
}
