import Foundation
import Combine

/// Universal Link `/pay/balance/{id}` landing (DES-v1.3-06-03 §5.3).
@MainActor
final class BalancePayLandingModel: ObservableObject {
    let balanceOrderId: Int64
    let token: String?

    @Published var landing: BalancePayLanding?
    @Published var state: LoadState = .idle
    @Published var needsLogin = false
    @Published var openPayOrder: Order?
    @Published var busy = false
    @Published var confirmAmount = false

    private var payIdempotencyKey: String?

    init(balanceOrderId: Int64, token: String? = nil) {
        self.balanceOrderId = balanceOrderId
        self.token = token
    }

    var serverNow: Date {
        if let now = landing?.serverNow { return now }
        if let ms = landing?.serverNowMs {
            return Date(timeIntervalSince1970: Double(ms) / 1000)
        }
        let ms = SessionStore.shared.serverClock.serverNowMs()
        return Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    var countdownSeconds: Int {
        guard let deadline = landing?.deadline else { return 0 }
        return PresaleLogic.countdownSeconds(until: deadline, serverNow: serverNow)
    }

    func load() async {
        if landing == nil { state = .loading }
        do {
            let result = try await API.balancePayLanding(orderId: balanceOrderId, token: token)
            landing = result
            if let ms = result.serverNowMs {
                SessionStore.shared.applyServerTimeMs(ms)
            }
            state = .loaded
            if result.requiresLogin == true || result.buyerMismatch == true {
                needsLogin = true
            }
        } catch let e as APIError {
            let code = PresaleErrorCode(rawValue: e.code)
            if code?.opensLogin == true {
                needsLogin = true
            }
            if landing == nil {
                state = .failed(code?.fallbackMessage ?? e.message)
            } else {
                ToastCenter.shared.error(e)
            }
        } catch {
            if landing == nil {
                state = .failed("加载失败")
            }
        }
    }

    func pay() async {
        confirmAmount = false
        guard !busy else { return }
        if !SessionStore.shared.isLoggedIn {
            needsLogin = true
            return
        }
        guard landing?.canPay != false else {
            ToastCenter.shared.show(PresaleCopy.notBalancePending, .info)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let od = try await API.order(balanceOrderId)
            openPayOrder = od.order
        } catch let e as APIError {
            let code = PresaleErrorCode(rawValue: e.code)
            if code?.opensLogin == true {
                needsLogin = true
            } else {
                ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
            }
        } catch {
            ToastCenter.shared.show(PresaleCopy.weakNetRetry, .info)
        }
    }

    func createBalancePayment(orderId: Int64, provider: String) async throws -> Payment {
        let key = payIdempotencyKey ?? UUID().uuidString
        payIdempotencyKey = key
        return try await API.createBalancePayment(
            orderId: orderId,
            provider: provider,
            idempotencyKey: key
        )
    }

    func handlePaymentFinished(_ result: PaymentResult) async {
        openPayOrder = nil
        payIdempotencyKey = nil
        if case .success = result.outcome {
            Haptics.success()
            await load()
        }
    }
}
