import Foundation
import Combine

/// 预售单详情：biz_status 时间线、尾款支付、延期选择（DES-v1.3-06-03 §5.7 / §5.10）。
@MainActor
final class PresaleOrderDetailModel: ObservableObject {
    let presaleOrderId: Int64

    @Published var detail: PresaleOrderDetail?
    @Published var state: LoadState = .idle
    @Published var busy = false
    @Published var needsLogin = false
    @Published var openPayOrder: Order?
    @Published var payingBalance = false
    @Published var showDelaySheet = false
    @Published var confirmBalanceAmount = false

    private var refundIdempotencyKey: String?
    private var balancePayIdempotencyKey: String?

    init(presaleOrderId: Int64) {
        self.presaleOrderId = presaleOrderId
    }

    var serverNow: Date {
        if let fromDetail = detail?.resolvedServerNow {
            return fromDetail
        }
        let ms = SessionStore.shared.serverClock.serverNowMs()
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    var cta: PresaleCTA {
        guard let detail else { return .payBalance }
        return PresaleLogic.resolveOrderCTA(
            order: detail.asSummary,
            delayNotice: detail.openDelayNotice,
            serverNow: serverNow
        )
    }

    var balanceCountdownSeconds: Int {
        guard let detail, detail.resolvedStatus.showsBalanceCountdown,
              let deadline = detail.balanceDeadline else { return 0 }
        return PresaleLogic.countdownSeconds(until: deadline, serverNow: serverNow)
    }

    var balanceCountdownLine: String {
        PresaleLogic.balanceDeadlineCountdownLine(seconds: balanceCountdownSeconds)
    }

    func load() async {
        if detail == nil { state = .loading }
        do {
            let d = try await API.presaleOrder(presaleOrderId)
            apply(d)
            state = .loaded
        } catch let e as APIError {
            if PresaleErrorCode(rawValue: e.code)?.opensLogin == true {
                needsLogin = true
            }
            if detail == nil {
                state = .failed(e.message)
            } else {
                ToastCenter.shared.error(e)
            }
        } catch {
            if detail == nil {
                state = .failed("加载失败")
            }
        }
    }

    func refresh() async {
        do {
            let d = try await API.presaleOrder(presaleOrderId)
            apply(d)
            state = .loaded
        } catch {
            // Keep last paint.
        }
    }

    func primaryAction() async {
        switch cta {
        case .payDeposit:
            await openDepositPay()
        case .payBalance:
            confirmBalanceAmount = true
        case .delayChoice:
            showDelaySheet = true
        default:
            ToastCenter.shared.show(cta.buttonTitle, .info)
        }
    }

    func openDepositPay() async {
        guard let orderId = detail?.depositOrderId else {
            ToastCenter.shared.show("定金单不可用", .info)
            return
        }
        payingBalance = false
        await openCashier(orderId: orderId)
    }

    func confirmAndPayBalance() async {
        confirmBalanceAmount = false
        guard let orderId = detail?.balanceOrderId else {
            ToastCenter.shared.show(PresaleCopy.notBalancePending, .info)
            return
        }
        payingBalance = true
        await openCashier(orderId: orderId)
    }

    func openCashier(orderId: Int64) async {
        guard !busy else { return }
        if !SessionStore.shared.isLoggedIn {
            needsLogin = true
            return
        }
        busy = true
        defer { busy = false }
        do {
            let od = try await API.order(orderId)
            openPayOrder = od.order
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(PresaleCopy.weakNetRetry, .info)
        }
    }

    /// Continue waiting — default if no choice (design §5.7); no server write required.
    func continueWaiting() {
        showDelaySheet = false
        ToastCenter.shared.show(PresaleCopy.delayContinue, .success)
    }

    func refundDeposit() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let key = refundIdempotencyKey ?? UUID().uuidString
        refundIdempotencyKey = key
        do {
            let result = try await API.refundPresaleDeposit(presaleOrderId, idempotencyKey: key)
            Haptics.success()
            ToastCenter.shared.show(
                result.bizStatus == .buyerRefunded ? PresaleCopy.refunded : "退定金申请已提交",
                .success
            )
            refundIdempotencyKey = nil
            showDelaySheet = false
            await refresh()
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(PresaleCopy.weakNetRetry, .info)
        }
    }

    func createBalancePayment(orderId: Int64, provider: String) async throws -> Payment {
        let key = balancePayIdempotencyKey ?? UUID().uuidString
        balancePayIdempotencyKey = key
        return try await API.createBalancePayment(
            orderId: orderId,
            provider: provider,
            idempotencyKey: key
        )
    }

    func handlePaymentFinished(_ result: PaymentResult) async {
        openPayOrder = nil
        payingBalance = false
        balancePayIdempotencyKey = nil
        if case .success = result.outcome {
            Haptics.success()
            await refresh()
        }
    }

    private func apply(_ d: PresaleOrderDetail) {
        detail = d
        if let ms = d.serverNowMs {
            SessionStore.shared.applyServerTimeMs(ms)
        } else if let now = d.resolvedServerNow {
            SessionStore.shared.applyServerTimeMs(Int64(now.timeIntervalSince1970 * 1000))
        }
    }

    private func handleError(_ e: APIError) {
        let code = PresaleErrorCode(rawValue: e.code)
        if code?.opensLogin == true {
            needsLogin = true
            return
        }
        ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
    }
}
