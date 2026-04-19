import AppKit
import SwiftUI

struct BillingView: View {
    @Environment(BillingViewModel.self) private var billing
    @Environment(AuthManager.self) private var auth

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Billing")

            if billing.showsInitialLoader {
                loadingStateView
            } else {
                if let banner = activeBanner {
                    bannerView(message: banner.message, kind: banner.kind)
                }

                if billing.signupBonusEnabled, let promo = billing.summary?.promo, promo.enabled {
                    promoCard(promo)
                }

                if billing.signupBonusEnabled, let promo = billing.summary?.promo, showsSubscriptionPromotionCard, let subscriptionPromotionPlan {
                    subscriptionPromotionCard(subscriptionPromotionPlan, promo: promo)
                }

                planCard
                paymentMethodCard
                invoicesSection
                messageChargesSection
            }
        }
        .sheet(
            isPresented: Binding(
                get: { billing.isCatalogPresented },
                set: { isPresented in
                    if isPresented {
                        billing.presentCatalog()
                    } else {
                        billing.dismissCatalog()
                    }
                }
            )
        ) {
            BillingCatalogSheet(
                catalog: billing.catalog,
                currentPlan: billing.currentPlan,
                pendingAction: billing.pendingAction,
                onChooseSubscription: { plan in
                    Task {
                        guard let token = await auth.validAccessToken() else { return }
                        await billing.openSubscriptionCheckout(planId: plan.id, accessToken: token)
                    }
                },
                onChoosePack: { plan in
                    Task {
                        guard let token = await auth.validAccessToken() else { return }
                        await billing.openPackCheckout(planId: plan.id, accessToken: token)
                    }
                },
                onManageBilling: {
                    Task {
                        guard let token = await auth.validAccessToken() else { return }
                        await billing.openBillingPortal(accessToken: token)
                    }
                }
            )
        }
        .task {
            guard let token = await auth.validAccessToken() else { return }
            if billing.summary == nil {
                await billing.refresh(accessToken: token)
            }
            await billing.refreshInvoices(accessToken: token)
        }
    }

    private var activeBanner: (message: String, kind: BillingStatusKind)? {
        if let statusMessage = billing.statusMessage {
            return (statusMessage, billing.statusKind)
        }
        if let errorMessage = billing.errorMessage {
            return (errorMessage, .error)
        }
        return nil
    }

    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXXL) {
            loadingCard(titleWidth: 120, rowCount: 3)
            loadingCard(titleWidth: 150, rowCount: 1)
            loadingCard(titleWidth: 100, rowCount: 3)
            loadingChargesCard
        }
    }

    private func loadingCard(titleWidth: CGFloat, rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            LoadingSkeletonBlock(width: titleWidth, height: 18)

            VStack(spacing: Theme.spacingSM) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            LoadingSkeletonBlock(width: 140, height: 12)
                            LoadingSkeletonBlock(width: 180, height: 10)
                        }
                        Spacer()
                        LoadingSkeletonBlock(width: 70, height: 12)
                    }
                    .padding(Theme.spacingMD)
                    .billingCard(radius: 8)
                }
            }
        }
        .padding(Theme.spacingXL)
        .settingsPanelCard()
    }

    private var loadingChargesCard: some View {
        VStack(alignment: .leading, spacing: Theme.spacingLG) {
            LoadingSkeletonBlock(width: 150, height: 18)

            VStack(spacing: Theme.spacingSM) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: Theme.spacingMD) {
                        VStack(alignment: .leading, spacing: 6) {
                            LoadingSkeletonBlock(width: 260, height: 14)
                            LoadingSkeletonBlock(width: 180, height: 11)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            LoadingSkeletonBlock(width: 70, height: 12)
                            LoadingSkeletonBlock(width: 56, height: 24, cornerRadius: 12)
                        }
                    }
                    .padding(Theme.spacingLG)
                    .billingCard(radius: 8)
                }
            }
        }
        .padding(Theme.spacingXL)
        .settingsPanelCard()
    }

    private func promoCard(_ promo: BillingPromoStatus) -> some View {
        SettingsPanel("Signup Bonus") {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(signupBonusHeadline(for: promo))
                        .font(Theme.geist(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    if let claimedAt = promo.signupBonusClaimedAt {
                        Text("Claimed \(BillingDisplay.dateOnly(claimedAt))")
                            .font(Theme.geist(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer()

                promoActionButton(promo)
            }
        }
    }

    @ViewBuilder
    private func promoActionButton(_ promo: BillingPromoStatus) -> some View {
        if promo.signupBonusClaimed {
            badge("Claimed", tint: Theme.accent)
        } else if billing.isLocalSignupBonusBlocked(for: auth.userId) {
            badge("Used On This Mac", tint: Theme.textSecondary)
        } else {
            Button {
                Task {
                    guard let token = await auth.validAccessToken() else { return }
                    await billing.claimSignupBonus(accessToken: token, userId: auth.userId)
                }
            } label: {
                Text(billing.pendingAction == "signup-bonus:claim" ? "Claiming…" : "Claim Credits")
                    .font(Theme.geist(13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(billing.pendingAction == "signup-bonus:claim" || !promo.signupBonusEligible)
            .opacity((billing.pendingAction == "signup-bonus:claim" || !promo.signupBonusEligible) ? 0.6 : 1)
        }
    }

    private func signupBonusHeadline(for promo: BillingPromoStatus) -> String {
        if promo.signupBonusClaimed {
            return "Signup bonus claimed"
        }
        return "Claim free credits"
    }

    private var showsSubscriptionPromotionCard: Bool {
        (billing.summary?.promo.subscriptionOfferActive ?? false) || (billing.currentPlan?.hasPromotionAdjustment ?? false)
    }

    private var subscriptionPromotionPlan: BillingPlan? {
        if let currentPlan = billing.currentPlan, currentPlan.hasPromotionAdjustment {
            return currentPlan
        }

        return billing.catalog.subscriptions.first(where: { $0.hasPromotionAdjustment || $0.promotionMultiplierValue > 1.0 })
    }

    private func subscriptionPromotionCard(_ plan: BillingPlan, promo: BillingPromoStatus) -> some View {
        SettingsPanel("Subscription Promotion") {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(BillingDisplay.subscriptionPromotionHeadline(plan))
                        .font(Theme.geist(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(subscriptionPromotionDetail(for: plan, promo: promo))
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                badge(BillingDisplay.multiplierLabel(plan.promotionMultiplierValue), tint: Theme.accent)
            }
        }
    }

    private func subscriptionPromotionDetail(for plan: BillingPlan, promo: BillingPromoStatus) -> String {
        let isCurrentPlan = billing.currentPlan?.id == plan.id && (billing.currentPlan?.hasPromotionAdjustment ?? false)
        return BillingDisplay.subscriptionPromotionDetail(
            for: plan,
            isCurrentPlan: isCurrentPlan,
            fallbackDurationPeriods: promo.subscriptionOfferDurationPeriods
        )
    }

    private var planCard: some View {
        SettingsPanel("Current Plan") {
            HStack(alignment: .top, spacing: Theme.spacingLG) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(billing.currentPlan?.name ?? "No plan")
                            .font(Theme.geist(18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        if let subscription = billing.summary?.subscription {
                            badge(subscription.displayStatus, tint: badgeColor(for: subscription))
                        }
                    }

                    if billing.currentPlan == nil {
                        Text("Choose a subscription or one-time usage pack.")
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textSecondary)
                    } else if let subscription = billing.summary?.subscription, subscription.showsCancellationExpiry {
                        Text("Cancelled in Stripe. Access stays active until \(BillingDisplay.dateOnly(subscription.currentPeriodEnd)).")
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                Button {
                    billing.presentCatalog()
                } label: {
                    Text("Browse Plans")
                        .font(Theme.geist(13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surface)
                        .foregroundStyle(Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if let plan = billing.currentPlan {
                SettingsInsetRow {
                    billingInfoRow(label: "Included usage", value: BillingDisplay.planAllowanceSummary(plan))
                }

                if let promotionSummary = BillingDisplay.planPromotionSummary(plan) {
                    SettingsInsetRow {
                        billingInfoRow(label: "Promotion", value: promotionSummary)
                    }
                }
            }

            if let subscription = billing.summary?.subscription {
                SettingsInsetRow {
                    billingInfoRow(
                        label: subscription.periodEndLabel,
                        value: BillingDisplay.dateOnly(subscription.currentPeriodEnd)
                    )
                }
            }
        }
    }

    private var paymentMethodCard: some View {
        SettingsPanel("Payment Method") {
            SettingsInsetRow {
                HStack(alignment: .center, spacing: Theme.spacingMD) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.separator, lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        if let paymentMethod = billing.summary?.paymentMethod, paymentMethod.hasPaymentMethod {
                            Text(paymentMethodTitle(paymentMethod))
                                .font(Theme.geist(13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(paymentMethodSubtitle(paymentMethod))
                                .font(Theme.geist(12))
                                .foregroundStyle(Theme.textTertiary)
                        } else {
                            Text("No payment method on file")
                                .font(Theme.geist(13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text(billing.paymentsEnabled
                                ? "Open Stripe to add a card, update billing details, or cancel your plan."
                                : "Stripe actions are disabled in this build.")
                                .font(Theme.geist(12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        Task {
                            guard let token = await auth.validAccessToken() else { return }
                            await billing.openBillingPortal(accessToken: token)
                        }
                    } label: {
                        Text(billing.paymentsEnabled ? "Manage In Stripe" : "Stripe Disabled")
                            .font(Theme.geist(13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.surfaceElevated)
                            .foregroundStyle(Theme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!billing.paymentsEnabled || billing.pendingAction == "portal")
                    .opacity((!billing.paymentsEnabled || billing.pendingAction == "portal") ? 0.6 : 1)
                }
            }
        }
    }

    private func paymentMethodTitle(_ paymentMethod: BillingPaymentMethodSummary) -> String {
        let brand = (paymentMethod.brand ?? "Card").capitalized
        return "\(brand) ending in \(paymentMethod.last4 ?? "----")"
    }

    private func paymentMethodSubtitle(_ paymentMethod: BillingPaymentMethodSummary) -> String {
        if let month = paymentMethod.expMonth, let year = paymentMethod.expYear {
            return "Expires \(String(format: "%02d", month))/\(year)"
        }
        return "Saved payment method"
    }

    private var invoicesSection: some View {
        SettingsPanel("Invoices") {
            if billing.isLoadingInvoices && !billing.hasLoadedInvoices {
                ProgressView()
                    .controlSize(.small)
            }
        } content: {
            if let invoiceErrorMessage = billing.invoiceErrorMessage, billing.invoices.isEmpty {
                Text(invoiceErrorMessage)
                    .font(Theme.geist(13))
                    .foregroundStyle(Theme.warning)
            } else if billing.invoices.isEmpty {
                Text(billing.isLoadingInvoices && !billing.hasLoadedInvoices ? "Loading invoices…" : "No invoices yet.")
                    .font(Theme.geist(13))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: Theme.spacingSM) {
                    ForEach(billing.invoices.prefix(12)) { invoice in
                        invoiceRow(invoice)
                    }
                }
            }
        }
    }

    private var messageChargesSection: some View {
        SettingsRecentUsageSection(
            charges: billing.messageCharges,
            limit: 12,
            amountStyle: .signedUsage(usagePricingPlan)
        )
    }

    private func billingInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            Text(label)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(Theme.geist(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func invoiceRow(_ invoice: BillingInvoice) -> some View {
        SettingsInsetRow {
            HStack(alignment: .top, spacing: Theme.spacingMD) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(invoice.title ?? invoice.description ?? invoice.number ?? "Invoice")
                        .font(Theme.geist(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let subtitle = invoice.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.geist(12))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: Theme.spacingSM) {
                        Text(BillingDisplay.dateTime(invoice.createdAt))
                        if let number = invoice.number, !number.isEmpty {
                            Text("•")
                            Text(number)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }

                VStack(alignment: .trailing, spacing: 6) {
                    Text(BillingDisplay.currency(minorUnits: invoice.amountPaid > 0 ? invoice.amountPaid : invoice.total, currencyCode: invoice.currency))
                        .font(Theme.geistMono(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: Theme.spacingSM) {
                        badge((invoice.status ?? "open").capitalized, tint: badgeColor(for: invoice.status ?? "open"))

                        if let url = invoice.hostedInvoiceURL ?? invoice.invoicePDF {
                            Button("Open") {
                                guard let resolvedURL = URL(string: url) else { return }
                                NSWorkspace.shared.open(resolvedURL)
                            }
                            .buttonStyle(.plain)
                            .font(Theme.geist(11, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.geist(11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private func bannerView(message: String, kind: BillingStatusKind) -> some View {
        let tint: Color = switch kind {
        case .info:
            Theme.textSecondary
        case .success:
            Theme.accent
        case .error:
            Theme.error
        }

        return HStack(spacing: Theme.spacingMD) {
            Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)

            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                billing.clearStatusMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.15), lineWidth: 1)
        )
    }

    private func badgeColor(for status: String) -> Color {
        Theme.billingStatusTint(status)
    }

    private func badgeColor(for subscription: BillingSubscription) -> Color {
        if subscription.isScheduledForCancellation {
            return Theme.warning
        }
        return badgeColor(for: subscription.status)
    }

    private var usagePricingPlan: BillingPlan? {
        billing.usagePricingPlan
    }
}

private struct BillingCatalogSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum CatalogTab: String, CaseIterable {
        case subscriptions = "Subscriptions"
        case packs = "Usage Packs"
    }

    let catalog: BillingCatalogResponse
    let currentPlan: BillingPlan?
    let pendingAction: String?
    let onChooseSubscription: (BillingPlan) -> Void
    let onChoosePack: (BillingPlan) -> Void
    let onManageBilling: () -> Void

    @State private var selectedTab: CatalogTab = .subscriptions

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.spacingLG) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Plans & Packs")
                            .font(Theme.geist(24, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(Config.paymentsEnabled
                            ? "Stripe opens in your browser and returns to 10x automatically."
                            : "Payments are disabled in this build. This sheet is read-only for plan and usage validation.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    closeButton
                }

                if let currentPlan {
                    currentPlanCard(currentPlan)
                }

                HStack(spacing: Theme.spacingMD) {
                    tabBar

                    Spacer()

                    Button {
                        onManageBilling()
                    } label: {
                        Text(Config.paymentsEnabled ? "Open Stripe Portal" : "Stripe Disabled")
                            .font(Theme.geist(12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Theme.surfaceElevated)
                            .foregroundStyle(Theme.textPrimary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Theme.separator, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!Config.paymentsEnabled || pendingAction == "portal")
                    .opacity((!Config.paymentsEnabled || pendingAction == "portal") ? 0.6 : 1)
                }
            }
            .padding(.horizontal, Theme.spacingXL)
            .padding(.top, Theme.spacingXL)
            .padding(.bottom, Theme.spacingLG)

            Divider()
                .overlay(Theme.separator)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingXL) {
                    switch selectedTab {
                    case .subscriptions:
                        catalogSection(
                            title: "Subscriptions",
                            subtitle: "Recurring plans with monthly included usage.",
                            plans: catalog.subscriptions,
                            action: onChooseSubscription
                        )
                    case .packs:
                        catalogSection(
                            title: "Usage Packs",
                            subtitle: "One-time purchases for extra usage.",
                            plans: catalog.creditPacks,
                            action: onChoosePack
                        )
                    }
                }
                .padding(Theme.spacingXL)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .overlay(Theme.separator)

            HStack {
                Text(Config.paymentsEnabled
                    ? "Secure checkout is handled by Stripe and returns to 10x automatically."
                    : "Payments are disabled in this build.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Theme.geist(13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.surfaceElevated)
                .foregroundStyle(Theme.textPrimary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.separator, lineWidth: 1))
            }
            .padding(.horizontal, Theme.spacingXL)
            .padding(.vertical, Theme.spacingLG)
        }
        .background(Theme.surface)
        .frame(minWidth: 760, minHeight: 640)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 30)
                .background(Theme.surface)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func currentPlanCard(_ plan: BillingPlan) -> some View {
        HStack(alignment: .center, spacing: Theme.spacingLG) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Plan")
                    .font(Theme.geistMono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Text(plan.name)
                    .font(Theme.geist(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(BillingDisplay.planAllowanceSummary(plan))
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                Text(BillingDisplay.includedUsageSummary(plan))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let promotionSummary = BillingDisplay.planPromotionSummary(plan) {
                    Text(promotionSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer()

            Text(plan.billingInterval.capitalized)
                .font(Theme.geistMono(11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.spacingMD)
        .billingCard(radius: 18, background: Theme.surfaceElevated)
    }

    private var tabBar: some View {
        HStack(spacing: Theme.spacingSM) {
            ForEach(CatalogTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(Theme.geist(12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == tab ? Theme.accent : Theme.surfaceElevated)
                        .foregroundStyle(selectedTab == tab ? Color.black.opacity(0.9) : Theme.textPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Theme.separator, lineWidth: 1)
        )
    }

    private func catalogSection(
        title: String,
        subtitle: String,
        plans: [BillingPlan],
        action: @escaping (BillingPlan) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.spacingMD) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.geist(18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            }

            ForEach(plans) { plan in
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(Theme.geist(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(plan.description ?? "")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            Text(BillingDisplay.includedUsageSummary(plan))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            if let promotionSummary = BillingDisplay.planPromotionSummary(plan) {
                                Text(promotionSummary)
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }

                        Spacer()

                        Text(currency(plan.priceCents))
                            .font(Theme.geist(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }

                    HStack(spacing: Theme.spacingMD) {
                        smallPlanMetric("Included", BillingDisplay.includedUsageAmountLabel(plan))
                        if plan.bonusCredits > 0 {
                            smallPlanMetric("Bonus", "+\(BillingDisplay.usageAmount(for: plan.bonusCredits, using: plan))")
                        }
                        if let dailyLimit = plan.dailyCreditLimit {
                            smallPlanMetric("Daily Cap", BillingDisplay.usageAmount(for: dailyLimit, using: plan))
                        }
                        Spacer()
                        planActionButton(plan: plan, action: action)
                    }
                }
                .padding(Theme.spacingMD)
                .billingCard(radius: 16, background: Theme.surfaceElevated)
            }
        }
    }

    private func smallPlanMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.geistMono(10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    @ViewBuilder
    private func planActionButton(plan: BillingPlan, action: @escaping (BillingPlan) -> Void) -> some View {
        let isCurrent = currentPlan?.id == plan.id
        let isSubscription = selectedTab == .subscriptions
        let actionKey = isSubscription ? "checkout:subscription:\(plan.id)" : "checkout:pack:\(plan.id)"
        let isBusy = pendingAction == actionKey

        if isCurrent {
            Text("Current")
                .font(Theme.geist(11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.accent.opacity(0.12))
                .foregroundStyle(Theme.accent)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Theme.accent.opacity(0.25), lineWidth: 1)
                )
        } else if !Config.paymentsEnabled {
            Text("Unavailable In Build")
                .font(Theme.geist(11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.warning.opacity(0.12))
                .foregroundStyle(Theme.warning)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Theme.warning.opacity(0.25), lineWidth: 1)
                )
        } else if plan.checkoutEnabled == false {
            Text("Unavailable")
                .font(Theme.geist(11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.surface)
                .foregroundStyle(Theme.textSecondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Theme.separator, lineWidth: 1)
                )
        } else {
            Button {
                action(plan)
            } label: {
                Text(isBusy ? "Opening…" : ctaLabel(for: plan))
                    .font(Theme.geist(11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surface)
                    .foregroundStyle(Theme.textPrimary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Theme.separator, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .opacity(isBusy ? 0.6 : 1)
        }
    }

    private func ctaLabel(for plan: BillingPlan) -> String {
        if plan.billingInterval.lowercased() == "one_time" {
            return "Buy Pack"
        }
        return "Choose Plan"
    }

    private func currency(_ cents: Int) -> String {
        BillingDisplay.currency(minorUnits: cents, currencyCode: "USD")
    }
}

private extension View {
    func billingCard(radius: CGFloat, background: Color = Theme.surface) -> some View {
        self
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}

struct LoadingSkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.textPrimary.opacity(isPulsing ? 0.08 : 0.14))
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
