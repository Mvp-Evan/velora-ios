import Foundation
import Combine

/// 预售付定金（DES-v1.3-06-03 §5.2 / POST /releases/{id}/presale-orders）。
@MainActor
final class PresaleDepositModel: ObservableObject {
    let releaseId: Int64

    @Published var detail: PresaleReleaseDetail?
    @Published var state: LoadState = .idle
    @Published var selectedSKUId: Int64?
    @Published var address: Address?
    @Published var busy = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var createdOrder: Order?
    @Published var createdPresaleOrderId: Int64?

    private var createIdempotencyKey: String?

    init(releaseId: Int64) {
        self.releaseId = releaseId
    }

    var isLoggedIn: Bool { SessionStore.shared.isLoggedIn }

    var serverNow: Date {
        if let fromDetail = detail?.resolvedServerNow {
            return fromDetail
        }
        let ms = SessionStore.shared.serverClock.serverNowMs()
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    var selectedSKU: SpotReleaseSKU? {
        guard let detail else { return nil }
        if let id = selectedSKUId {
            return detail.skus.first { $0.id == id } ?? detail.defaultSKU
        }
        return detail.defaultSKU
    }

    var cta: PresaleCTA {
        guard let detail else { return .payDeposit }
        return PresaleLogic.resolveReleaseCTA(
            detail: detail,
            serverNow: serverNow,
            isLoggedIn: isLoggedIn,
            hasAddress: address != nil
        )
    }

    var checklist: [PresaleDepositChecklistItem] {
        PresaleLogic.depositChecklist(
            isLoggedIn: isLoggedIn,
            eligibility: detail?.eligibility,
            hasAddress: address != nil
        )
    }

    var depositCountdownSeconds: Int {
        guard let detail else { return 0 }
        if let start = detail.depositStartAt, serverNow < start {
            return PresaleLogic.countdownSeconds(until: start, serverNow: serverNow)
        }
        if let end = detail.depositEndAt, PresaleLogic.isDepositWindowOpen(
            start: detail.depositStartAt,
            end: end,
            serverNow: serverNow
        ) {
            return PresaleLogic.countdownSeconds(until: end, serverNow: serverNow)
        }
        return 0
    }

    func load() async {
        if detail == nil { state = .loading }
        do {
            let d = try await API.presaleRelease(releaseId)
            apply(d)
            state = .loaded
            if address == nil, isLoggedIn {
                await loadDefaultAddress()
            }
        } catch {
            if detail == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    func refresh() async {
        do {
            let d = try await API.presaleRelease(releaseId)
            apply(d)
            state = .loaded
        } catch {
            // Keep last paint.
        }
    }

    func setAddress(_ a: Address) {
        address = a
    }

    func primaryAction() async {
        switch cta {
        case .login:
            needsLogin = true
        case .completeEligibility:
            await completeEligibility()
        case .payDeposit:
            await createDepositOrder()
        case .payBalance, .delayChoice, .depositPaidWaiting:
            if let oid = detail?.myOrder?.id {
                createdPresaleOrderId = oid
            } else {
                ToastCenter.shared.show(cta.buttonTitle, .info)
            }
        default:
            ToastCenter.shared.show(cta.buttonTitle, .info)
        }
    }

    func completeEligibility() async {
        guard let step = PresaleLogic.nextDepositStep(
            isLoggedIn: isLoggedIn,
            eligibility: detail?.eligibility,
            hasAddress: address != nil
        ) else {
            await createDepositOrder()
            return
        }
        switch step {
        case .login:
            needsLogin = true
        case .realName:
            needsRealName = true
        case .credit:
            ToastCenter.shared.show(PresaleCopy.creditTooLow, .info)
        case .address:
            ToastCenter.shared.show(PresaleErrorCode.addressRequired.fallbackMessage, .info)
        }
    }

    func createDepositOrder() async {
        guard !busy else { return }
        if !isLoggedIn {
            needsLogin = true
            return
        }
        guard let skuId = selectedSKU?.id else {
            ToastCenter.shared.show("请选择规格", .info)
            return
        }
        guard let addressId = address?.id else {
            ToastCenter.shared.show(PresaleErrorCode.addressRequired.fallbackMessage, .info)
            return
        }
        busy = true
        defer { busy = false }
        let key = createIdempotencyKey ?? UUID().uuidString
        createIdempotencyKey = key
        do {
            let result = try await API.createPresaleOrder(
                releaseId,
                skuId: skuId,
                qty: 1,
                addressId: addressId,
                idempotencyKey: key
            )
            createdPresaleOrderId = result.resolvedPresaleOrderId
            if let depositOrderId = result.depositOrderId {
                let od = try await API.order(depositOrderId)
                createdOrder = od.order
            }
            Haptics.success()
            createIdempotencyKey = nil
            await refresh()
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(PresaleCopy.weakNetRetry, .info)
        }
    }

    func handlePaymentFinished(_ result: PaymentResult) async {
        createdOrder = nil
        if case .success = result.outcome {
            Haptics.success()
            await refresh()
        }
    }

    private func apply(_ d: PresaleReleaseDetail) {
        detail = d
        if selectedSKUId == nil {
            selectedSKUId = d.defaultSKU?.id
        }
        if let ms = d.serverNowMs ?? d.serverTimeMs {
            SessionStore.shared.applyServerTimeMs(ms)
        } else if let now = d.resolvedServerNow {
            SessionStore.shared.applyServerTimeMs(Int64(now.timeIntervalSince1970 * 1000))
        }
    }

    private func loadDefaultAddress() async {
        do {
            let list = try await API.addresses()
            address = list.first(where: \.isDefault) ?? list.first
        } catch {
            address = nil
        }
    }

    private func handleError(_ e: APIError) {
        let code = PresaleErrorCode(rawValue: e.code)
        if code?.opensLogin == true {
            needsLogin = true
            return
        }
        if code?.opensRealName == true {
            needsRealName = true
            return
        }
        ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
    }
}
