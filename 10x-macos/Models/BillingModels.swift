import Foundation

typealias CreditAmount = Decimal

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

enum BillingFeatureValue: Decodable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([BillingFeatureValue])
    case object([String: BillingFeatureValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: BillingFeatureValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([BillingFeatureValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported billing feature value.")
        }
    }
}

struct BillingBootstrapResponse: Decodable {
    let summary: BillingSummaryResponse
    let history: BillingHistoryResponse
    let catalog: BillingCatalogResponse
}

struct BillingSummaryResponse: Decodable {
    let totalCredits: CreditAmount
    let dailyUsed: CreditAmount
    let dailyLimit: CreditAmount?
    let dailyRemaining: CreditAmount?
    let subscription: BillingSubscription?
    let plan: BillingPlan?
    let currentSubscription: BillingCurrentSubscription?
    let balances: [CreditBalance]
    let latestUsage: BillingUsageLog?
    let billingCustomer: BillingCustomerSummary?
    let paymentMethod: BillingPaymentMethodSummary
    let promo: BillingPromoStatus

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case dailyUsed = "daily_used"
        case dailyLimit = "daily_limit"
        case dailyRemaining = "daily_remaining"
        case subscription
        case plan
        case currentSubscription = "current_subscription"
        case balances
        case latestUsage = "latest_usage"
        case billingCustomer = "billing_customer"
        case paymentMethod = "payment_method"
        case promo
    }
}

struct BillingCurrentSubscription: Decodable {
    let subscription: BillingSubscription
    let plan: BillingPlan?
}

struct BillingHistoryResponse: Decodable {
    let usageLogs: [BillingUsageLog]
    let creditEvents: [CreditEventRecord]

    enum CodingKeys: String, CodingKey {
        case usageLogs = "usage_logs"
        case creditEvents = "credit_events"
    }
}

struct BillingCatalogResponse: Decodable {
    let currentPlanId: String?
    let subscriptions: [BillingPlan]
    let creditPacks: [BillingPlan]

    enum CodingKeys: String, CodingKey {
        case currentPlanId = "current_plan_id"
        case subscriptions
        case creditPacks = "credit_packs"
    }
}

struct BillingSubscription: Decodable {
    let id: String
    let planId: String
    let status: String
    let currentPeriodStart: String
    let currentPeriodEnd: String
    let cancelAtPeriodEnd: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case status
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd = "current_period_end"
        case cancelAtPeriodEnd = "cancel_at_period_end"
    }
}

extension BillingSubscription {
    private var normalizedStatus: String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var hasFutureAccessAfterCancellation: Bool {
        guard normalizedStatus == "cancelled",
              let periodEnd = BillingDisplay.date(from: currentPeriodEnd) else { return false }
        return periodEnd > Date()
    }

    var isScheduledForCancellation: Bool {
        cancelAtPeriodEnd && ["active", "trialing"].contains(normalizedStatus)
    }

    var showsCancellationExpiry: Bool {
        isScheduledForCancellation || hasFutureAccessAfterCancellation
    }

    var displayStatus: String {
        if showsCancellationExpiry {
            return "Cancelled"
        }
        return normalizedStatus.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var periodEndLabel: String {
        if showsCancellationExpiry {
            return "Expires"
        }
        if normalizedStatus == "cancelled" {
            return "Expired"
        }
        return "Renews"
    }

    var planStateLabel: String {
        if showsCancellationExpiry {
            return "Cancelled plan"
        }
        if normalizedStatus == "cancelled" {
            return "Expired plan"
        }
        return "Active plan"
    }
}

struct BillingPlan: Identifiable, Decodable {
    let id: String
    let code: String
    let name: String
    let description: String?
    let planType: String
    let billingInterval: String
    let monthlyCredits: CreditAmount
    let dailyCreditLimit: CreditAmount?
    let priceCents: Int
    let maxProjects: Int?
    let features: [String: BillingFeatureValue]
    let bonusCredits: CreditAmount
    let creditTypeCode: String
    let isActive: Bool?
    let stripeProductId: String?
    let stripePriceId: String?
    let checkoutEnabled: Bool?
    let baseMonthlyCredits: CreditAmount?
    let effectiveMonthlyCredits: CreditAmount?
    let promotionMultiplier: Double?
    let promotionApplied: Bool?
    let promotionDurationPeriods: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case name
        case description
        case planType = "plan_type"
        case billingInterval = "billing_interval"
        case monthlyCredits = "monthly_credits"
        case dailyCreditLimit = "daily_credit_limit"
        case priceCents = "price_cents"
        case maxProjects = "max_projects"
        case features
        case bonusCredits = "bonus_credits"
        case creditTypeCode = "credit_type_code"
        case isActive = "is_active"
        case stripeProductId = "stripe_product_id"
        case stripePriceId = "stripe_price_id"
        case checkoutEnabled = "checkout_enabled"
        case baseMonthlyCredits = "base_monthly_credits"
        case effectiveMonthlyCredits = "effective_monthly_credits"
        case promotionMultiplier = "promotion_multiplier"
        case promotionApplied = "promotion_applied"
        case promotionDurationPeriods = "promotion_duration_periods"
    }
}

struct BillingCustomerSummary: Decodable {
    let stripeCustomerId: String?
    let phoneVerified: Bool
    let phoneVerifiedAt: String?
    let phoneLast4: String?
    let signupPromoGrantedAt: String?
    let signupPromoCreditEventId: String?

    enum CodingKeys: String, CodingKey {
        case stripeCustomerId = "stripe_customer_id"
        case phoneVerified = "phone_verified"
        case phoneVerifiedAt = "phone_verified_at"
        case phoneLast4 = "phone_last4"
        case signupPromoGrantedAt = "signup_promo_granted_at"
        case signupPromoCreditEventId = "signup_promo_credit_event_id"
    }
}

struct BillingPaymentMethodSummary: Decodable {
    let hasCustomer: Bool
    let hasPaymentMethod: Bool
    let stripeCustomerId: String?
    let defaultPaymentMethodId: String?
    let brand: String?
    let last4: String?
    let expMonth: Int?
    let expYear: Int?
    let funding: String?
    let country: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case hasCustomer = "has_customer"
        case hasPaymentMethod = "has_payment_method"
        case stripeCustomerId = "stripe_customer_id"
        case defaultPaymentMethodId = "default_payment_method_id"
        case brand
        case last4
        case expMonth = "exp_month"
        case expYear = "exp_year"
        case funding
        case country
        case updatedAt = "updated_at"
    }
}

struct BillingPromoStatus: Decodable {
    let enabled: Bool
    let claimMethod: String
    let requiresPhoneVerification: Bool
    let phoneVerified: Bool
    let phoneLast4: String?
    let signupBonusAmount: CreditAmount
    let signupBonusCreditTypeCode: String
    let signupBonusClaimed: Bool
    let signupBonusClaimedAt: String?
    let signupBonusEligible: Bool
    let phoneVerificationProvider: String?
    let claimOncePerUser: Bool
    let claimOncePerDevice: Bool
    let subscriptionMultiplier: Double
    let subscriptionOfferActive: Bool
    let subscriptionOfferDurationPeriods: Int?
    let applyToPaidSubscriptions: Bool
    let applyToCreditPacks: Bool
    let applyToSignupBonus: Bool

    enum CodingKeys: String, CodingKey {
        case enabled
        case claimMethod = "claim_method"
        case requiresPhoneVerification = "requires_phone_verification"
        case phoneVerified = "phone_verified"
        case phoneLast4 = "phone_last4"
        case signupBonusAmount = "signup_bonus_amount"
        case signupBonusCreditTypeCode = "signup_bonus_credit_type_code"
        case signupBonusClaimed = "signup_bonus_claimed"
        case signupBonusClaimedAt = "signup_bonus_claimed_at"
        case signupBonusEligible = "signup_bonus_eligible"
        case phoneVerificationProvider = "phone_verification_provider"
        case claimOncePerUser = "claim_once_per_user"
        case claimOncePerDevice = "claim_once_per_device"
        case subscriptionMultiplier = "subscription_multiplier"
        case subscriptionOfferActive = "subscription_offer_active"
        case subscriptionOfferDurationPeriods = "subscription_offer_duration_periods"
        case applyToPaidSubscriptions = "apply_to_paid_subscriptions"
        case applyToCreditPacks = "apply_to_credit_packs"
        case applyToSignupBonus = "apply_to_signup_bonus"
    }
}

struct BillingCheckoutResponse: Decodable {
    let url: String
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case url
        case sessionId = "session_id"
    }
}

struct BillingCheckoutSyncResponse: Decodable {
    let sessionId: String
    let settled: Bool
    let mode: String
    let paymentStatus: String?
    let subscriptionStatus: String?
    let creditsPending: Bool
    let summary: BillingSummaryResponse
    let history: BillingHistoryResponse
    let catalog: BillingCatalogResponse
    let invoices: [BillingInvoice]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case settled
        case mode
        case paymentStatus = "payment_status"
        case subscriptionStatus = "subscription_status"
        case creditsPending = "credits_pending"
        case summary
        case history
        case catalog
        case invoices
    }
}

struct BillingPortalResponse: Decodable {
    let url: String
}

struct BillingInvoicesResponse: Decodable {
    let invoices: [BillingInvoice]
}

struct BillingInvoice: Identifiable, Decodable {
    let id: String
    let number: String?
    let status: String?
    let currency: String
    let amountPaid: Int
    let total: Int
    let createdAt: String?
    let hostedInvoiceURL: String?
    let invoicePDF: String?
    let title: String?
    let subtitle: String?
    let description: String?
    let lineItems: [String]?
    let billingReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case status
        case currency
        case amountPaid = "amount_paid"
        case total
        case createdAt = "created_at"
        case hostedInvoiceURL = "hosted_invoice_url"
        case invoicePDF = "invoice_pdf"
        case title
        case subtitle
        case description
        case lineItems = "line_items"
        case billingReason = "billing_reason"
    }
}

struct PhoneVerificationStartResponse: Decodable {
    let sent: Bool
    let alreadyClaimed: Bool
    let phoneLast4: String?

    enum CodingKeys: String, CodingKey {
        case sent
        case alreadyClaimed = "already_claimed"
        case phoneLast4 = "phone_last4"
    }
}

struct CreditBalance: Identifiable, Decodable {
    let typeCode: String
    let typeName: String
    let balance: CreditAmount
    let nextExpiry: String?
    let expiringSoon: CreditAmount
    let expiryMode: String

    var id: String { typeCode }

    enum CodingKeys: String, CodingKey {
        case typeCode = "type_code"
        case typeName = "type_name"
        case balance
        case nextExpiry = "next_expiry"
        case expiringSoon = "expiring_soon"
        case expiryMode = "expiry_mode"
    }
}

struct BillingUsageLog: Identifiable, Decodable {
    let id: String
    let taskType: String
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let outputCreditWeight: Int
    let baseCreditCost: CreditAmount
    let creditDiscountAmount: CreditAmount
    let finalCreditCost: CreditAmount
    let status: String
    let requestId: String?
    let sessionId: String?
    let errorMessage: String?
    let createdAt: String
    let billingGroupId: String?
    let billingMessagePreview: String?
    let imageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case taskType = "task_type"
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case outputCreditWeight = "output_credit_weight"
        case baseCreditCost = "base_credit_cost"
        case creditDiscountAmount = "credit_discount_amount"
        case finalCreditCost = "final_credit_cost"
        case status
        case requestId = "request_id"
        case sessionId = "session_id"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case billingGroupId = "billing_group_id"
        case billingMessagePreview = "billing_message_preview"
        case imageCount = "image_count"
    }

    var usageGroupKey: String {
        guard let billingGroupId, !billingGroupId.isEmpty else { return id }
        return "\(billingGroupId):\(taskType)"
    }
}

struct BillingMessageCharge: Identifiable {
    let id: String
    let taskType: String
    let model: String?
    let inputTokens: Int
    let outputTokens: Int
    let totalCredits: CreditAmount
    let createdAt: String
    let callCount: Int
    let newestStatus: String
    let messagePreview: String?
    let imageCount: Int

    init(id: String, usageLogs: [BillingUsageLog]) {
        let sortedLogs = usageLogs.sorted { $0.createdAt > $1.createdAt }
        let newestLog = sortedLogs.first ?? usageLogs[0]

        self.id = id
        taskType = newestLog.taskType
        model = newestLog.model
        inputTokens = usageLogs.reduce(0) { $0 + $1.inputTokens }
        outputTokens = usageLogs.reduce(0) { $0 + $1.outputTokens }
        totalCredits = usageLogs.reduce(Decimal.zero) { $0 + $1.finalCreditCost }
        createdAt = newestLog.createdAt
        callCount = usageLogs.count
        newestStatus = Self.normalizedStatus(newestLog.status)
        messagePreview = sortedLogs.compactMap(\.billingMessagePreview).first { !$0.isEmpty }
        imageCount = usageLogs.reduce(0) { $0 + ($1.imageCount ?? 0) }
    }

    var primaryStatus: String {
        newestStatus.isEmpty ? "completed" : newestStatus
    }

    var taskLabel: String {
        taskType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var summaryLabel: String {
        model ?? taskLabel
    }

    var statusLabel: String {
        BillingDisplay.statusLabel(primaryStatus)
    }

    var isImageGeneration: Bool {
        taskType == "openai_image_generation"
    }

    var displayedImageCount: Int {
        max(imageCount, callCount)
    }

    private static func normalizedStatus(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }
}

struct CreditEventRecord: Identifiable, Decodable {
    let id: String
    let eventType: String
    let source: String
    let amount: CreditAmount
    let description: String?
    let balanceAfter: CreditAmount
    let creditTypeId: String?
    let creditTypeName: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case source
        case amount
        case description
        case balanceAfter = "balance_after"
        case creditTypeId = "credit_type_id"
        case creditTypeName = "credit_type_name"
        case createdAt = "created_at"
    }
}

extension BillingPlan {
    var baseMonthlyCreditsValue: CreditAmount {
        baseMonthlyCredits ?? monthlyCredits
    }

    var effectiveMonthlyCreditsValue: CreditAmount {
        effectiveMonthlyCredits ?? monthlyCredits
    }

    var promotionMultiplierValue: Double {
        promotionMultiplier ?? 1
    }

    var hasPromotionAdjustment: Bool {
        promotionApplied ?? false
    }

    var promotionDurationPeriodsValue: Int? {
        guard let promotionDurationPeriods, promotionDurationPeriods > 0 else { return nil }
        return promotionDurationPeriods
    }

    var billingPeriodsPerYear: Double {
        switch billingInterval.lowercased() {
        case "annual":
            return 12
        default:
            return 1
        }
    }

    var includedCredits: CreditAmount {
        effectiveMonthlyCreditsValue + bonusCredits
    }

    var recurringPeriodDollarAmount: Double {
        Double(priceCents) / 100.0
    }

    var monthlyIncludedDollarAmount: Double {
        recurringPeriodDollarAmount / billingPeriodsPerYear
    }

    var totalIncludedDollarAmount: Double {
        billingInterval.lowercased() == "one_time" ? recurringPeriodDollarAmount : monthlyIncludedDollarAmount
    }

    var dollarValuePerCredit: Double {
        let denominator = billingInterval.lowercased() == "one_time" ? includedCredits : effectiveMonthlyCreditsValue
        guard denominator > 0 else { return 0 }
        return totalIncludedDollarAmount / denominator.doubleValue
    }
}

enum BillingDisplay {
    static func number(_ value: CreditAmount) -> String {
        numberFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    static func integer(_ value: Int) -> String {
        integerNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func creditsLabel(_ value: CreditAmount) -> String {
        "\(number(value)) credits"
    }

    static func currency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    static func currency(minorUnits amount: Int, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: Double(amount) / 100.0)) ?? currency(Double(amount) / 100.0)
    }

    static func usageDollarAmount(for credits: CreditAmount, using plan: BillingPlan?) -> Double? {
        guard let plan, plan.dollarValuePerCredit > 0 else { return nil }
        return credits.doubleValue * plan.dollarValuePerCredit
    }

    static func usageAmount(for credits: CreditAmount, using plan: BillingPlan?, zeroLabel: String? = nil) -> String {
        if credits == 0, let zeroLabel {
            return zeroLabel
        }
        if let amount = usageDollarAmount(for: credits, using: plan) {
            return currency(amount)
        }
        return creditsLabel(credits)
    }

    static func signedUsageAmount(for credits: CreditAmount, using plan: BillingPlan?) -> String {
        if let amount = usageDollarAmount(for: credits, using: plan) {
            return signedCurrency(-amount)
        }
        return "-\(creditsLabel(credits))"
    }

    static func statusLabel(_ status: String) -> String {
        status
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func includedUsageAmountLabel(_ plan: BillingPlan) -> String {
        switch plan.billingInterval.lowercased() {
        case "annual", "monthly":
            return "\(currency(plan.monthlyIncludedDollarAmount)) per month"
        case "one_time":
            return "\(currency(plan.totalIncludedDollarAmount)) one time"
        default:
            return currency(plan.monthlyIncludedDollarAmount)
        }
    }

    static func includedUsageSummary(_ plan: BillingPlan) -> String {
        switch plan.billingInterval.lowercased() {
        case "annual", "monthly":
            return "\(currency(plan.monthlyIncludedDollarAmount)) of included usage per month"
        case "one_time":
            return "\(currency(plan.totalIncludedDollarAmount)) of included usage one time"
        default:
            return "\(currency(plan.monthlyIncludedDollarAmount)) of included usage"
        }
    }

    static func planAllowanceSummary(_ plan: BillingPlan) -> String {
        switch plan.billingInterval.lowercased() {
        case "annual":
            return "\(currency(plan.monthlyIncludedDollarAmount)) included per month · Annual billing"
        case "monthly":
            return "\(currency(plan.monthlyIncludedDollarAmount)) included per month · Monthly billing"
        case "one_time":
            return "\(currency(plan.totalIncludedDollarAmount)) included one time"
        default:
            return "\(currency(plan.monthlyIncludedDollarAmount)) included · \(plan.billingInterval.capitalized)"
        }
    }

    static func planPromotionSummary(_ plan: BillingPlan) -> String? {
        guard plan.hasPromotionAdjustment else { return nil }
        if let durationPeriods = plan.promotionDurationPeriodsValue {
            return "\(multiplierLabel(plan.promotionMultiplierValue)) intro allowance · Active for \(promotionWindowLabel(durationPeriods))"
        }
        return "\(multiplierLabel(plan.promotionMultiplierValue)) intro allowance · Active while the promo is enabled"
    }

    static func subscriptionPromotionHeadline(_ plan: BillingPlan) -> String {
        "\(multiplierLabel(plan.promotionMultiplierValue)) \(plan.name) intro allowance"
    }

    static func subscriptionPromotionDetail(
        for plan: BillingPlan,
        isCurrentPlan: Bool,
        fallbackDurationPeriods: Int?
    ) -> String {
        let durationPeriods = plan.promotionDurationPeriodsValue ?? fallbackDurationPeriods
        let multiplier = multiplierLabel(plan.promotionMultiplierValue)
        let allowance = includedUsageAmountLabel(plan)

        if isCurrentPlan {
            if let durationPeriods {
                return "Your current \(plan.name) billing period is using the \(multiplier) intro allowance. Included usage is \(allowance). After \(promotionWindowLabel(durationPeriods)), the plan returns to its standard allowance."
            }
            return "Your current \(plan.name) billing period is using the \(multiplier) intro allowance. Included usage is \(allowance) while the promo is active."
        }

        if let durationPeriods {
            return "New \(plan.name) subscriptions start with the \(multiplier) intro allowance. Included usage is \(allowance) for \(promotionWindowLabel(durationPeriods)), then the plan returns to its standard allowance."
        }

        return "New \(plan.name) subscriptions start with the \(multiplier) intro allowance. Included usage is \(allowance) while the promo is active."
    }

    static func signupBonusAmount(_ credits: CreditAmount, using plan: BillingPlan?) -> String {
        usageAmount(for: credits, using: plan)
    }

    static func date(from iso: String) -> Date? {
        internetDateTime.date(from: iso) ?? fallbackDateTime.date(from: iso)
    }

    static func dateTime(_ iso: String?) -> String {
        guard let iso else { return "No date" }
        if let date = date(from: iso) {
            return dateTimeFormatter.string(from: date)
        }
        return iso
    }

    static func dateOnly(_ iso: String?) -> String {
        guard let iso else { return "No date" }
        if let date = date(from: iso) {
            return dateOnlyFormatter.string(from: date)
        }
        return iso
    }

    static func multiplierLabel(_ multiplier: Double) -> String {
        let rounded = Int(multiplier.rounded())
        if abs(multiplier - Double(rounded)) < 0.001 {
            return "\(rounded)x"
        }
        return String(format: "%.1fx", multiplier)
    }

    static func promotionWindowLabel(_ periods: Int) -> String {
        if periods == 1 {
            return "the first billing period"
        }
        return "the first \(periods) billing periods"
    }

    private static func signedCurrency(_ amount: Double) -> String {
        let prefix = amount > 0 ? "+" : ""
        return "\(prefix)\(currency(amount))"
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        return formatter
    }()

    private static let integerNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    private static let internetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackDateTime = ISO8601DateFormatter()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
