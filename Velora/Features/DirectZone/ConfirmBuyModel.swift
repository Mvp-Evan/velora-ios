import Foundation
import Combine

/// Confirm-buy page: address → preview → create order (DES-v1.3-04-01 DIR-02).
@MainActor
final class ConfirmBuyModel: ObservableObject {
    let listingId: Int64
    let source: DirectOrderSource
    let initialExpectedPrice: Int64?

    @Published var address: Address?
    @Published var qty: Int = 1
    @Published var preview: FixedOrderPreview?
    @Published var state: LoadState = .idle
    @Published var submitting = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var createdOrderId: Int64?
    @Published var createdOrder: Order?

    init(
        listingId: Int64,
        source: DirectOrderSource = .detail,
        expectedPriceFen: Int64? = nil,
        initialQty: Int = 1
    ) {
        self.listingId = listingId
        self.source = source
        self.initialExpectedPrice = expectedPriceFen
        self.qty = 1
        _ = initialQty
    }

    var maxQty: Int { 1 }
    var showsQtyStepper: Bool { false }
    var canSubmit: Bool {
        address != nil && preview != nil && !submitting && state == .loaded
    }

    var goodsSubtotal: Int64 {
        guard let p = preview else { return 0 }
        return p.unitPriceFen * Int64(p.qty)
    }

    func bootstrap() async {
        if !SessionStore.shared.isLoggedIn {
            needsLogin = true
            state = .failed(DirectZoneErrorCode.unauthorized.fallbackMessage)
            return
        }
        if let gate = currentGate() {
            applyGate(gate)
            return
        }
        state = .loading
        await loadDefaultAddress()
        await refreshPreview()
    }

    func setAddress(_ a: Address) async {
        address = a
        await refreshPreview()
    }

    func setQty(_ value: Int) async {
        _ = value
        guard qty != 1 else { return }
        qty = 1
        await refreshPreview()
    }

    func refreshPreview() async {
        guard let address else {
            preview = nil
            state = .loaded
            return
        }
        if let err = DirectZoneLogic.validateOrderPreview(
            qty: qty,
            addressId: address.id,
            expectedPriceFen: expectedPrice()
        ) {
            state = .failed(err == "missing_address" ? "请先填写收货地址" : "数量无效")
            return
        }
        do {
            let p = try await API.fixedOrderPreview(
                listingId,
                qty: qty,
                addressId: address.id,
                expectedPriceFen: expectedPrice()
            )
            preview = p
            qty = 1
            state = .loaded
        } catch let e as APIError {
            handlePreviewError(e)
        } catch {
            state = .failed("费用加载失败")
        }
    }

    @discardableResult
    func submit() async -> FixedOrderCreateResult? {
        guard !submitting else { return nil }
        if let gate = currentGate() {
            applyGate(gate)
            return nil
        }
        guard let address else {
            ToastCenter.shared.show("请先填写收货地址", .info)
            return nil
        }
        guard let preview else {
            ToastCenter.shared.show("费用加载中，请稍候", .info)
            return nil
        }
        submitting = true
        defer { submitting = false }
        do {
            let result = try await API.createFixedOrder(
                listingId,
                qty: qty,
                addressId: address.id,
                source: source,
                expectedPriceFen: preview.unitPriceFen
            )
            createdOrderId = result.orderId
            // Cashier needs full Order; fetch after lock.
            if let detail = try? await API.order(result.orderId) {
                createdOrder = detail.order
            }
            Haptics.success()
            return result
        } catch let e as APIError {
            handleSubmitError(e)
            return nil
        } catch {
            ToastCenter.shared.show(DirectZoneCopy.weakNetRetry, .info)
            return nil
        }
    }

    private func expectedPrice() -> Int64? {
        preview?.unitPriceFen ?? initialExpectedPrice
    }

    private func loadDefaultAddress() async {
        do {
            let list = try await API.addresses()
            address = list.first(where: \.isDefault) ?? list.first
        } catch {
            address = nil
        }
    }

    private func currentGate() -> DirectZoneErrorCode? {
        let session = SessionStore.shared
        let rn = session.bootstrap?.me?.realNameStatus ?? session.user?.realNameStatus
        let realNameDone = rn == "verified" || rn == "passed"
        let credit = session.bootstrap?.me?.creditScore ?? session.user?.creditScore ?? 0
        let restricted = session.accessFlags.isFrozen || session.accessFlags.isBanBid
        return DirectZoneLogic.purchaseGate(
            isLoggedIn: session.isLoggedIn,
            realNameDone: realNameDone,
            creditScore: credit,
            isRestricted: restricted
        )
    }

    private func applyGate(_ gate: DirectZoneErrorCode) {
        switch gate {
        case .unauthorized:
            needsLogin = true
        case .realNameRequired:
            needsRealName = true
        default:
            break
        }
        state = .failed(gate.fallbackMessage)
        ToastCenter.shared.show(gate.fallbackMessage, .info)
    }

    private func handlePreviewError(_ e: APIError) {
        if let code = DirectZoneErrorCode(rawValue: e.code) {
            switch code {
            case .unauthorized:
                needsLogin = true
            case .realNameRequired:
                needsRealName = true
            case .priceChanged:
                ToastCenter.shared.show(code.fallbackMessage, .info)
                Task { await refreshPreviewIgnoringExpected() }
                return
            default:
                break
            }
            state = .failed(e.message.isEmpty ? code.fallbackMessage : e.message)
            return
        }
        state = .failed(e.message.isEmpty ? "费用加载失败" : e.message)
    }

    private func refreshPreviewIgnoringExpected() async {
        guard let address else { return }
        do {
            let p = try await API.fixedOrderPreview(
                listingId,
                qty: qty,
                addressId: address.id,
                expectedPriceFen: nil
            )
            preview = p
            state = .loaded
        } catch {
            // keep prior error
        }
    }

    private func handleSubmitError(_ e: APIError) {
        if ReviewCreditErrorCode.normalize(e.code)?.isCreditBlock == true {
            let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
            AppRouterProxy.presentCreditBlock(code: e.code, score: score, action: "购买")
            state = .failed(ReviewCreditCopy.errCreditGeneric)
            return
        }
        if let code = DirectZoneErrorCode(rawValue: e.code) {
            switch code {
            case .unauthorized:
                needsLogin = true
            case .realNameRequired:
                needsRealName = true
            case .creditTooLow:
                let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
                AppRouterProxy.presentCreditBlock(code: ReviewCreditErrorCode.creditBelow60.rawValue, score: score, action: "购买")
                state = .failed(code.fallbackMessage)
            case .priceChanged:
                ToastCenter.shared.show(code.fallbackMessage, .info)
                Task { await refreshPreviewIgnoringExpected() }
            case .stockInsufficient, .listingSoldOut:
                ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, .error)
                state = .failed(code.fallbackMessage)
            default:
                ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, .error)
            }
            return
        }
        ToastCenter.shared.show(DirectZoneCopy.weakNetRetry, .info)
    }
}
