import AppKit
import Foundation
import Observation

extension Notification.Name {
    static let tenxBillingDeepLink = Notification.Name("TenXBillingDeepLink")
    static let tenxOpenBillingCatalog = Notification.Name("TenXOpenBillingCatalog")
}

@MainActor
final class BillingDeepLinkStore {
    static let shared = BillingDeepLinkStore()

    private var pendingURL: URL?

    func save(_ url: URL) {
        pendingURL = url
    }

    func consume() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }
}

enum BillingStatusKind {
    case info
    case success
    case error
}

@Observable
@MainActor
final class BillingViewModel {
    private static let recentHistoryLimit = 100

    var summary: BillingSummaryResponse?
    var history = BillingHistoryResponse(usageLogs: [], creditEvents: [])
    var catalog = BillingCatalogResponse(currentPlanId: nil, subscriptions: [], creditPacks: [])
    var invoices: [BillingInvoice] = []
    var isLoading = false
    var isLoadingInvoices = false
    var hasLoadedInitialState = false
    var hasLoadedInvoices = false
    var invoiceErrorMessage: String?
    var errorMessage: String?
    var latestBalanceDelta: CreditAmount?
    var pendingAction: String?
    var statusMessage: String?
    var statusKind: BillingStatusKind = .info
    var isCatalogPresented = false

    private let api = APIClient()
    private let checkoutStartTimeout: TimeInterval = 90
    private let checkoutSyncTimeout: TimeInterval = 25
    private var inFlightRefreshTask: Task<BillingBootstrapResponse, Error>?
    private var inFlightInvoicesTask: Task<BillingInvoicesResponse, Error>?
    private var billingFlowRefreshTask: Task<Void, Never>?
    private var optimisticPlanId: String?
    private var statusClearTask: Task<Void, Never>?

    var paymentsEnabled: Bool {
        Config.paymentsEnabled
    }

    var signupBonusEnabled: Bool {
        Config.signupBonusEnabled
    }

    var isTestMode: Bool {
        Config.billingTestMode
    }

    var testModeNotice: String {
        "Billing is unavailable in this build."
    }

    var totalCredits: CreditAmount {
        summary?.totalCredits ?? 0
    }

    var dailyRemaining: CreditAmount? {
        summary?.dailyRemaining
    }

    var dailyLimit: CreditAmount? {
        summary?.dailyLimit
    }

    var currentPlan: BillingPlan? {
        if let optimisticPlanId,
           let optimisticPlan = allPlans.first(where: { $0.id == optimisticPlanId }) {
            return optimisticPlan
        }
        if let plan = summary?.plan {
            return plan
        }
        if let currentPlanId = catalog.currentPlanId {
            return allPlans.first(where: { $0.id == currentPlanId })
        }
        return nil
    }

    var usagePricingPlan: BillingPlan? {
        if let currentPlan, currentPlan.dollarValuePerCredit > 0 {
            return currentPlan
        }

        if let paidSubscription = catalog.subscriptions.first(where: { $0.dollarValuePerCredit > 0 }) {
            return paidSubscription
        }

        return catalog.creditPacks.first(where: { $0.dollarValuePerCredit > 0 })
    }

    private var allPlans: [BillingPlan] {
        catalog.subscriptions + catalog.creditPacks
    }

    var messageCharges: [BillingMessageCharge] {
        Dictionary(grouping: history.usageLogs, by: \.usageGroupKey)
            .map { BillingMessageCharge(id: $0.key, usageLogs: $0.value) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var latestMessageCharge: BillingMessageCharge? {
        messageCharges.first
    }

    var nonUsageCreditEvents: [CreditEventRecord] {
        history.creditEvents.filter { $0.eventType != "consume" }
    }

    var showsInitialLoader: Bool {
        !hasLoadedInitialState && summary == nil
    }

    func clear() {
        inFlightRefreshTask?.cancel()
        inFlightInvoicesTask?.cancel()
        billingFlowRefreshTask?.cancel()
        statusClearTask?.cancel()
        inFlightRefreshTask = nil
        inFlightInvoicesTask = nil
        billingFlowRefreshTask = nil
        statusClearTask = nil
        summary = nil
        history = BillingHistoryResponse(usageLogs: [], creditEvents: [])
        catalog = BillingCatalogResponse(currentPlanId: nil, subscriptions: [], creditPacks: [])
        invoices = []
        isLoading = false
        isLoadingInvoices = false
        hasLoadedInitialState = false
        hasLoadedInvoices = false
        invoiceErrorMessage = nil
        errorMessage = nil
        latestBalanceDelta = nil
        pendingAction = nil
        statusMessage = nil
        statusKind = .info
        isCatalogPresented = false
        optimisticPlanId = nil
    }

    func presentCatalog() {
        isCatalogPresented = true
    }

    func dismissCatalog() {
        isCatalogPresented = false
    }

    func refresh(accessToken: String, captureDelta: Bool = false) async {
        let previousTotal = summary?.totalCredits
        if showsInitialLoader {
            isLoading = true
        }
        errorMessage = nil

        let createdTask = inFlightRefreshTask == nil
        if createdTask {
            let api = self.api
            inFlightRefreshTask = Task {
                try await api.get(
                    APIClient.billing("bootstrap?history_limit=\(Self.recentHistoryLimit)"),
                    accessToken: accessToken
                )
            }
        }

        guard let refreshTask = inFlightRefreshTask else {
            isLoading = false
            return
        }

        do {
            let bootstrap = try await refreshTask.value

            if createdTask {
                inFlightRefreshTask = nil
            }

            applyBootstrap(bootstrap, captureDelta: captureDelta, previousTotal: previousTotal)
        } catch {
            if createdTask {
                inFlightRefreshTask = nil
            }
            if isCancellation(error) {
                isLoading = false
                return
            }
            hasLoadedInitialState = true
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        hasLoadedInitialState = true
        isLoading = false
    }

    func refreshInvoices(accessToken: String, force: Bool = false, preserveExistingOnEmpty: Bool = true) async {
        if hasLoadedInvoices && !force {
            return
        }

        isLoadingInvoices = true
        invoiceErrorMessage = nil
        let createdTask = inFlightInvoicesTask == nil || force
        if createdTask {
            if force {
                inFlightInvoicesTask?.cancel()
            }
            let api = self.api
            inFlightInvoicesTask = Task {
                try await api.get(APIClient.billing("invoices"), accessToken: accessToken)
            }
        }

        guard let invoicesTask = inFlightInvoicesTask else {
            isLoadingInvoices = false
            return
        }

        do {
            let response = try await invoicesTask.value
            if createdTask {
                inFlightInvoicesTask = nil
            }
            applyInvoices(response.invoices, preserveExistingOnEmpty: preserveExistingOnEmpty)
            hasLoadedInvoices = true
            invoiceErrorMessage = nil
        } catch {
            if createdTask {
                inFlightInvoicesTask = nil
            }
            if isCancellation(error) {
                isLoadingInvoices = false
                return
            }
            invoiceErrorMessage = "Couldn't load invoices right now. Try reopening Billing in a moment."
        }

        isLoadingInvoices = false
    }

    func clearStatusMessage() {
        statusClearTask?.cancel()
        statusClearTask = nil
        statusMessage = nil
        statusKind = .info
    }

    private func setStatus(_ message: String?, kind: BillingStatusKind, autoClearAfter seconds: TimeInterval? = nil) {
        statusClearTask?.cancel()
        statusClearTask = nil
        statusMessage = message
        statusKind = kind

        guard let seconds, let message else { return }
        statusClearTask = Task { [message] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, self.statusMessage == message else { return }
            self.statusMessage = nil
            self.statusKind = .info
            self.statusClearTask = nil
        }
    }

    private func applyBootstrap(
        _ bootstrap: BillingBootstrapResponse,
        captureDelta: Bool,
        previousTotal: CreditAmount?
    ) {
        summary = bootstrap.summary
        history = bootstrap.history
        catalog = bootstrap.catalog

        if captureDelta, let previousTotal {
            let delta = bootstrap.summary.totalCredits - previousTotal
            latestBalanceDelta = delta == 0 ? nil : delta
        } else if !captureDelta {
            latestBalanceDelta = nil
        }

        if let optimisticPlanId,
           bootstrap.summary.plan?.id == optimisticPlanId || bootstrap.catalog.currentPlanId == optimisticPlanId {
            self.optimisticPlanId = nil
        }
    }

    private func applyCheckoutSyncResponse(
        _ response: BillingCheckoutSyncResponse,
        captureDelta: Bool,
        previousTotal: CreditAmount?
    ) {
        summary = response.summary
        history = response.history
        catalog = response.catalog
        applyInvoices(response.invoices, preserveExistingOnEmpty: true)
        hasLoadedInvoices = true

        if captureDelta, let previousTotal {
            let delta = response.summary.totalCredits - previousTotal
            latestBalanceDelta = delta == 0 ? nil : delta
        } else if !captureDelta {
            latestBalanceDelta = nil
        }

        if let optimisticPlanId,
           response.summary.plan?.id == optimisticPlanId || response.catalog.currentPlanId == optimisticPlanId {
            self.optimisticPlanId = nil
        }
    }

    private func applyInvoices(_ newInvoices: [BillingInvoice], preserveExistingOnEmpty: Bool) {
        if preserveExistingOnEmpty && newInvoices.isEmpty && !invoices.isEmpty {
            return
        }
        invoices = newInvoices
    }

    private func startBillingFlowAutoRefresh(
        accessToken: String,
        captureDelta: Bool,
        attempts: Int = 16,
        initialDelay: Duration = .zero
    ) {
        billingFlowRefreshTask?.cancel()
        billingFlowRefreshTask = Task {
            if initialDelay != .zero {
                try? await Task.sleep(for: initialDelay)
            }

            defer {
                if !Task.isCancelled {
                    self.billingFlowRefreshTask = nil
                }
            }

            for attempt in 0..<attempts {
                if Task.isCancelled {
                    return
                }

                await refresh(accessToken: accessToken, captureDelta: captureDelta)
                await refreshInvoices(accessToken: accessToken, force: true, preserveExistingOnEmpty: true)

                if attempt == attempts - 1 {
                    break
                }

                let delay: Duration
                switch attempt {
                case 0..<5:
                    delay = .milliseconds(700)
                case 5..<10:
                    delay = .seconds(1)
                default:
                    delay = .seconds(2)
                }
                try? await Task.sleep(for: delay)
            }
        }
    }

    func openSubscriptionCheckout(planId: String, accessToken: String) async {
        guard paymentsEnabled else {
            setStatus(testModeNotice, kind: .info, autoClearAfter: 8)
            return
        }
        await openExternalFlow(
            action: "checkout:subscription:\(planId)",
            endpoint: APIClient.billing("checkout/subscription"),
            body: ["plan_id": planId],
            initialMessage: "Opening Stripe Checkout…",
            accessToken: accessToken
        )
    }

    func openPackCheckout(planId: String, accessToken: String) async {
        guard paymentsEnabled else {
            setStatus(testModeNotice, kind: .info, autoClearAfter: 8)
            return
        }
        await openExternalFlow(
            action: "checkout:pack:\(planId)",
            endpoint: APIClient.billing("checkout/pack"),
            body: ["plan_id": planId],
            initialMessage: "Opening Stripe Checkout…",
            accessToken: accessToken
        )
    }

    func openBillingPortal(accessToken: String) async {
        guard paymentsEnabled else {
            setStatus(testModeNotice, kind: .info, autoClearAfter: 8)
            return
        }
        pendingAction = "portal"
        errorMessage = nil
        statusClearTask?.cancel()
        statusMessage = "Opening billing portal…"
        statusKind = .info

        do {
            let response: BillingPortalResponse = try await api.post(
                APIClient.billing("portal"),
                accessToken: accessToken,
                requestTimeout: checkoutStartTimeout
            )
            try openExternalURL(response.url)
            startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: false)
        } catch {
            pendingAction = nil
            errorMessage = error.localizedDescription
            setStatus("Could not open the billing portal.", kind: .error)
        }
    }

    func isLocalSignupBonusBlocked(for userId: String?) -> Bool {
        SignupBonusClaimStore.isBlocked(for: userId)
    }

    func claimSignupBonus(accessToken: String, userId: String?) async {
        guard signupBonusEnabled else {
            setStatus("Promotional credits are disabled in this build.", kind: .info, autoClearAfter: 8)
            return
        }
        guard !SignupBonusClaimStore.isBlocked(for: userId) else {
            setStatus("This Mac has already used the local signup bonus claim.", kind: .info, autoClearAfter: 8)
            return
        }

        pendingAction = "signup-bonus:claim"
        errorMessage = nil
        statusClearTask?.cancel()
        statusMessage = "Claiming free credits…"
        statusKind = .info

        do {
            let updatedSummary: BillingSummaryResponse = try await api.post(
                APIClient.billing("promo/claim-signup-bonus"),
                json: [:],
                accessToken: accessToken
            )
            SignupBonusClaimStore.markClaimed(userId: userId)
            summary = updatedSummary
            await refresh(accessToken: accessToken, captureDelta: true)
            pendingAction = nil
            setStatus("Signup bonus applied.", kind: .success, autoClearAfter: 6)
        } catch {
            pendingAction = nil
            errorMessage = error.localizedDescription
            setStatus("Could not claim the signup bonus.", kind: .error)
        }
    }

    func sendPhoneVerificationCode(phoneNumber: String, accessToken: String) async -> Bool {
        guard signupBonusEnabled else {
            setStatus("Promotional credits are disabled in this build.", kind: .info, autoClearAfter: 8)
            return false
        }
        pendingAction = "phone:send"
        errorMessage = nil
        statusClearTask?.cancel()
        statusMessage = "Sending verification code…"
        statusKind = .info

        do {
            let response: PhoneVerificationStartResponse = try await api.post(
                APIClient.billing("promo/send-phone-otp"),
                json: ["phone_number": phoneNumber],
                accessToken: accessToken
            )
            pendingAction = nil
            if response.alreadyClaimed {
                setStatus("Your signup bonus has already been claimed.", kind: .info, autoClearAfter: 6)
                await refresh(accessToken: accessToken)
                return false
            }
            setStatus("Verification code sent to ending in \(response.phoneLast4 ?? "—").", kind: .success, autoClearAfter: 6)
            return response.sent
        } catch {
            pendingAction = nil
            errorMessage = error.localizedDescription
            setStatus("Could not send the verification code.", kind: .error)
            return false
        }
    }

    func verifyPhoneCode(phoneNumber: String, otpCode: String, accessToken: String) async {
        guard signupBonusEnabled else {
            setStatus("Promotional credits are disabled in this build.", kind: .info, autoClearAfter: 8)
            return
        }
        pendingAction = "phone:verify"
        errorMessage = nil
        statusClearTask?.cancel()
        statusMessage = "Verifying phone number…"
        statusKind = .info

        do {
            let updatedSummary: BillingSummaryResponse = try await api.post(
                APIClient.billing("promo/verify-phone-otp"),
                json: [
                    "phone_number": phoneNumber,
                    "otp_code": otpCode,
                ],
                accessToken: accessToken
            )
            summary = updatedSummary
            await refresh(accessToken: accessToken, captureDelta: true)
            pendingAction = nil
            setStatus("Phone verified. Signup bonus applied.", kind: .success, autoClearAfter: 6)
        } catch {
            pendingAction = nil
            errorMessage = error.localizedDescription
            setStatus("Phone verification failed.", kind: .error)
        }
    }

    func handleDeepLink(_ url: URL, accessToken: String) async {
        guard
            url.scheme == "app.10x.macos",
            url.host == "billing",
            url.path == "/return"
        else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let source = queryItems["source"] ?? "checkout"
        let status = queryItems["status"] ?? "success"
        let action = queryItems["action"] ?? "subscription"
        let sessionId = queryItems["session_id"].flatMap { $0.isEmpty ? nil : $0 }
        let planId = queryItems["plan_id"].flatMap { $0.isEmpty ? nil : $0 }

        pendingAction = nil
        statusClearTask?.cancel()
        switch (source, status, action) {
        case ("checkout", "success", "subscription"):
            optimisticPlanId = planId
            if let sessionId {
                statusMessage = "Confirming subscription…"
                statusKind = .info
                await syncCheckoutSession(sessionId, action: action, accessToken: accessToken, captureDelta: true)
            } else {
                setStatus("Subscription checkout completed. Refreshing billing…", kind: .success, autoClearAfter: 6)
                await refresh(accessToken: accessToken, captureDelta: true)
                await refreshInvoices(accessToken: accessToken, force: true)
                startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: true, initialDelay: .seconds(1))
            }
        case ("checkout", "success", "pack"):
            if let sessionId {
                statusMessage = "Applying credit pack…"
                statusKind = .info
                await syncCheckoutSession(sessionId, action: action, accessToken: accessToken, captureDelta: true)
            } else {
                setStatus("Credit pack purchased. Refreshing billing…", kind: .success, autoClearAfter: 6)
                await refresh(accessToken: accessToken, captureDelta: true)
                await refreshInvoices(accessToken: accessToken, force: true)
                startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: true, initialDelay: .seconds(1))
            }
        case ("checkout", "cancel", _):
            optimisticPlanId = nil
            setStatus("Checkout was canceled.", kind: .info, autoClearAfter: 6)
            await refresh(accessToken: accessToken)
            await refreshInvoices(accessToken: accessToken, force: true)
        case ("portal", _, _):
            optimisticPlanId = nil
            setStatus("Billing portal closed. Refreshing billing…", kind: .info, autoClearAfter: 6)
            await refresh(accessToken: accessToken)
            await refreshInvoices(accessToken: accessToken, force: true)
            startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: false, initialDelay: .seconds(1))
        default:
            optimisticPlanId = nil
            setStatus("Billing updated. Refreshing…", kind: .info, autoClearAfter: 6)
            await refresh(accessToken: accessToken)
            await refreshInvoices(accessToken: accessToken, force: true)
            startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: false, initialDelay: .seconds(1))
        }
    }

    private func syncCheckoutSession(
        _ sessionId: String,
        action: String,
        accessToken: String,
        captureDelta: Bool
    ) async {
        let maxAttempts = action == "subscription" ? 8 : 5
        let startingTotal = summary?.totalCredits
        let startingInvoiceIDs = Set(invoices.map(\.id))
        var latestResponse: BillingCheckoutSyncResponse?

        for attempt in 1...maxAttempts {
            do {
                let response: BillingCheckoutSyncResponse = try await api.post(
                    APIClient.billing("checkout/session/sync"),
                    json: ["session_id": sessionId],
                    accessToken: accessToken,
                    requestTimeout: checkoutSyncTimeout
                )
                latestResponse = response
                applyCheckoutSyncResponse(response, captureDelta: captureDelta, previousTotal: startingTotal)

                if response.settled {
                    startBillingFlowAutoRefresh(
                        accessToken: accessToken,
                        captureDelta: captureDelta,
                        attempts: 12,
                        initialDelay: .seconds(1)
                    )
                    optimisticPlanId = nil
                    errorMessage = nil
                    if action == "subscription" && response.creditsPending {
                        Task {
                            await pollForInvoiceHistoryUpdate(accessToken: accessToken, previousInvoiceIDs: startingInvoiceIDs)
                        }
                        setStatus("Subscription is active. Credits are finalizing…", kind: .success)
                        Task {
                            await pollForPendingSubscriptionCredits(
                                accessToken: accessToken,
                                baselineTotal: response.summary.totalCredits
                            )
                        }
                        return
                    }

                    setStatus(
                        action == "subscription"
                            ? "Subscription is active."
                            : "Credit pack applied.",
                        kind: .success,
                        autoClearAfter: 6
                    )
                    Task {
                        await pollForInvoiceHistoryUpdate(accessToken: accessToken, previousInvoiceIDs: startingInvoiceIDs)
                    }
                    return
                }

                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(attempt < 3 ? 700 : 1200))
                }
            } catch {
                optimisticPlanId = nil
                if isCancellation(error) {
                    return
                }
                errorMessage = error.localizedDescription
                setStatus("Could not confirm the checkout.", kind: .error)
                return
            }
        }

        optimisticPlanId = nil
        startBillingFlowAutoRefresh(
            accessToken: accessToken,
            captureDelta: captureDelta,
            attempts: 12,
            initialDelay: .milliseconds(800)
        )
        if latestResponse != nil {
            setStatus(
                action == "subscription"
                    ? "Checkout finished. Stripe is still finalizing your subscription."
                    : "Checkout finished. Stripe is still finalizing your credit pack.",
                kind: .info,
                autoClearAfter: 8
            )
        } else {
            setStatus("Billing updated. Refreshing…", kind: .info, autoClearAfter: 6)
        }
    }

    private func pollForInvoiceHistoryUpdate(accessToken: String, previousInvoiceIDs: Set<String>) async {
        let hadInvoices = !previousInvoiceIDs.isEmpty

        for attempt in 0..<10 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled {
                return
            }

            await refreshInvoices(accessToken: accessToken, force: true, preserveExistingOnEmpty: true)

            let currentIDs = Set(invoices.map(\.id))
            if hadInvoices {
                if !currentIDs.isEmpty && currentIDs != previousInvoiceIDs {
                    return
                }
            } else if !currentIDs.isEmpty {
                return
            }
        }
    }

    private func pollForPendingSubscriptionCredits(accessToken: String, baselineTotal: CreditAmount) async {
        for _ in 1...12 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled {
                return
            }

            await refresh(accessToken: accessToken, captureDelta: true)
            if (summary?.totalCredits ?? baselineTotal) > baselineTotal {
                setStatus("Subscription credits applied.", kind: .success, autoClearAfter: 6)
                return
            }
        }

        setStatus("Subscription is active. Credits will appear shortly.", kind: .info, autoClearAfter: 8)
    }

    private func openExternalFlow(
        action: String,
        endpoint: String,
        body: [String: Any],
        initialMessage: String,
        accessToken: String
    ) async {
        pendingAction = action
        errorMessage = nil
        statusClearTask?.cancel()
        statusMessage = initialMessage
        statusKind = .info

        do {
            let response: BillingCheckoutResponse = try await api.post(
                endpoint,
                json: body,
                accessToken: accessToken,
                requestTimeout: checkoutStartTimeout
            )
            try openExternalURL(response.url)
            startBillingFlowAutoRefresh(accessToken: accessToken, captureDelta: false)
        } catch {
            pendingAction = nil
            errorMessage = error.localizedDescription
            setStatus("Could not start the billing flow.", kind: .error)
        }
    }

    private func openExternalURL(_ rawURL: String) throws {
        guard let url = URL(string: rawURL) else {
            throw APIError.invalidURL
        }
        let opened = NSWorkspace.shared.open(url)
        if !opened {
            throw APIError.invalidResponse
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return false
    }
}
