import Foundation
import Combine

/// Buyer after-sale apply (DES-v1.3-09-02 AFS-04).
@MainActor
final class AfterSaleApplyModel: ObservableObject {
    let orderId: Int64
    let orderStatus: String
    let afterSaleStatus: String
    let signedAt: Date?
    let shipDeadline: Date?
    let remainingPayableCents: Int64
    let unboxPhotoCount: Int
    let isRealNamed: Bool
    let accountRestricted: Bool

    @Published var type: AfterSaleType = .notAsDescribed
    @Published var claim: AfterSaleClaim = .refund
    @Published var amountYuanText: String = ""
    @Published var reason: String = ""
    @Published var submitting = false
    @Published var errorMessage: String?
    @Published var created: AfterSale?

    private var idempotencyKey: String?

    init(
        orderId: Int64,
        orderStatus: String,
        afterSaleStatus: String,
        signedAt: Date?,
        shipDeadline: Date?,
        remainingPayableCents: Int64,
        unboxPhotoCount: Int = 0,
        isRealNamed: Bool = true,
        accountRestricted: Bool = false
    ) {
        self.orderId = orderId
        self.orderStatus = orderStatus
        self.afterSaleStatus = afterSaleStatus
        self.signedAt = signedAt
        self.shipDeadline = shipDeadline
        self.remainingPayableCents = remainingPayableCents
        self.unboxPhotoCount = unboxPhotoCount
        self.isRealNamed = isRealNamed
        self.accountRestricted = accountRestricted
        self.amountYuanText = String(format: "%.2f", Double(remainingPayableCents) / 100)
    }

    var types: [AfterSaleType] { AfterSaleLogic.selectableTypes() }

    var claimAmountCents: Int64 {
        switch claim {
        case .refund, .returnRefund:
            return remainingPayableCents
        case .partial:
            let yuan = Double(amountYuanText.replacingOccurrences(of: ",", with: "")) ?? 0
            return Int64((yuan * 100).rounded())
        }
    }

    var gateError: AfterSaleErrorCode? {
        AfterSaleLogic.createGate(
            type: type,
            orderStatus: orderStatus,
            afterSaleStatus: afterSaleStatus,
            signedAt: signedAt,
            shipDeadline: shipDeadline,
            unboxPhotoCount: unboxPhotoCount,
            claim: claim,
            claimAmountCents: claimAmountCents,
            remainingPayableCents: remainingPayableCents,
            isLoggedIn: SessionStore.shared.isLoggedIn,
            isRealNamed: isRealNamed,
            accountRestricted: accountRestricted
        )
    }

    var canSubmit: Bool {
        gateError == nil && !submitting && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func onTypeChange() {
        if type.isAppearance, claim == .partial {
            // keep
        }
        errorMessage = gateError?.fallbackMessage
    }

    func onClaimChange() {
        if claim != .partial {
            amountYuanText = String(format: "%.2f", Double(remainingPayableCents) / 100)
        }
        errorMessage = gateError?.fallbackMessage
    }

    func submit() async {
        errorMessage = gateError?.fallbackMessage
        guard canSubmit else { return }
        submitting = true
        defer { submitting = false }
        if idempotencyKey == nil {
            idempotencyKey = APIClient.shared.idempotencyKey()
        }
        let req = CreateAfterSaleRequest(
            type: type,
            claim: claim,
            claimAmountCents: claimAmountCents,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            unboxPhotoIds: []
        )
        do {
            created = try await API.createAfterSale(
                orderId: orderId,
                request: req,
                idempotencyKey: idempotencyKey
            )
            ToastCenter.shared.show("售后已提交", .success)
        } catch {
            if let api = error as? APIError, let mapped = AfterSaleErrorCode.normalize(api.code) {
                errorMessage = mapped.fallbackMessage
            } else {
                errorMessage = (error as? APIError)?.message ?? error.localizedDescription
            }
            ToastCenter.shared.error(error)
        }
    }
}
