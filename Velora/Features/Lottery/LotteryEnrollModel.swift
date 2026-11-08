import Foundation
import UIKit
import Combine

/// Lottery enroll / eligibility / deposit (DES-v1.3-06-02 REL-02/03 / D24).
@MainActor
final class LotteryEnrollModel: ObservableObject {
    let releaseId: Int64

    @Published var detail: LotteryReleaseDetail?
    @Published var state: LoadState = .idle
    @Published var address: Address?
    @Published var busy = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var needsDeposit = false
    @Published var openProof = false
    @Published var openPayOrderId: Int64?
    @Published var payOrder: Order?

    /// Sticky idempotency across weak-net retries (design §5.2 / §9).
    private var enrollIdempotencyKey: String?

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

    var cta: LotteryCTA {
        guard let detail else { return .enroll }
        return LotteryLogic.resolveReleaseCTA(
            detail: detail,
            serverNow: serverNow,
            isLoggedIn: isLoggedIn,
            hasAddress: address != nil
        )
    }

    var checklist: [LotteryEnrollChecklistItem] {
        LotteryLogic.enrollChecklist(
            isLoggedIn: isLoggedIn,
            eligibility: detail?.eligibility,
            hasAddress: address != nil
        )
    }

    var enrollCountdownSeconds: Int {
        guard let detail else { return 0 }
        if LotteryLogic.isEnrollOpen(detail, serverNow: serverNow) {
            if let end = detail.enrollEndAt {
                return LotteryLogic.countdownSeconds(until: end, serverNow: serverNow)
            }
            return 0
        }
        if let start = detail.enrollStartAt, serverNow < start {
            return LotteryLogic.countdownSeconds(until: start, serverNow: serverNow)
        }
        return 0
    }

    var payCountdownSeconds: Int {
        guard let entry = detail?.myEntry, let deadline = entry.payDeadline else { return 0 }
        return LotteryLogic.countdownSeconds(until: deadline, serverNow: serverNow)
    }

    func load() async {
        if detail == nil { state = .loading }
        do {
            let d = try await API.lotteryRelease(releaseId)
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
            let d = try await API.lotteryRelease(releaseId)
            apply(d)
            state = .loaded
        } catch {
            // Keep last paint.
        }
    }

    func primaryAction() async {
        switch cta {
        case .login:
            needsLogin = true
        case .completeEligibility:
            await completeEligibility()
        case .enroll:
            await enroll()
        case .pay:
            await openPay()
        case .viewProof:
            openProof = true
        case .waitlist, .enrolledWaiting, .drawing, .lost, .paid, .forfeited, .enrollClosed, .ended, .waitEnrollOpen:
            if cta == .lost {
                ToastCenter.shared.show(LotteryCopy.depositReleased, .info)
            } else if cta == .forfeited {
                ToastCenter.shared.show(LotteryCopy.depositDeducted, .info)
            } else if let title = Optional(cta.buttonTitle) {
                ToastCenter.shared.show(title, .info)
            }
        }
    }

    func completeEligibility() async {
        guard let step = LotteryLogic.nextEnrollStep(
            isLoggedIn: isLoggedIn,
            eligibility: detail?.eligibility,
            hasAddress: address != nil
        ) else {
            await enroll()
            return
        }
        switch step {
        case .login:
            needsLogin = true
        case .realName:
            needsRealName = true
        case .credit:
            let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
            AppRouterProxy.presentCreditBlock(
                code: ReviewCreditErrorCode.creditBelow80.rawValue,
                score: score,
                action: "抽签报名"
            )
        case .deposit:
            needsDeposit = true
        case .address:
            ToastCenter.shared.show(LotteryErrorCode.addressRequired.fallbackMessage, .info)
        }
    }

    func enroll() async {
        guard !busy else { return }
        if !isLoggedIn {
            needsLogin = true
            return
        }
        guard let addressId = address?.id else {
            ToastCenter.shared.show(LotteryErrorCode.addressRequired.fallbackMessage, .info)
            return
        }
        busy = true
        defer { busy = false }
        let key = enrollIdempotencyKey ?? UUID().uuidString
        enrollIdempotencyKey = key
        let attestation = LotteryLogic.deviceAttestation(
            vendorId: UIDevice.current.identifierForVendor?.uuidString
        )
        do {
            let result = try await API.createLotteryEntry(
                releaseId,
                addressId: addressId,
                deviceAttestation: attestation,
                idempotencyKey: key
            )
            if result.needsDepositPayment {
                needsDeposit = true
                ToastCenter.shared.show("请完成保证金预授权", .info)
                return
            }
            Haptics.success()
            ToastCenter.shared.show(
                result.alreadyEntered == true ? "本场已报名" : "报名成功，保证金已冻结",
                .success
            )
            enrollIdempotencyKey = nil
            await refresh()
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(LotteryCopy.weakNetRetry, .info)
        }
    }

    /// Confirm deposit freeze sheet → retry enroll (server freezes inside POST).
    func confirmDepositAndEnroll() async {
        needsDeposit = false
        await enroll()
    }

    func openPay() async {
        guard let orderId = detail?.myEntry?.orderId else {
            ToastCenter.shared.show(LotteryCopy.forbiddenSpotBuyCTA, .info)
            return
        }
        do {
            let detail = try await API.order(orderId)
            payOrder = detail.order
            openPayOrderId = orderId
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    func setAddress(_ a: Address) {
        address = a
    }

    // MARK: - Private

    private func apply(_ d: LotteryReleaseDetail) {
        detail = d
        if let ms = d.resolvedServerNowMs {
            SessionStore.shared.applyServerTimeMs(ms)
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
        if ReviewCreditErrorCode.normalize(e.code)?.isCreditBlock == true
            || e.code == LotteryErrorCode.creditTooLow.rawValue {
            let score = SessionStore.shared.bootstrap?.me?.creditScore ?? SessionStore.shared.user?.creditScore
            AppRouterProxy.presentCreditBlock(
                code: ReviewCreditErrorCode.normalize(e.code)?.rawValue
                    ?? ReviewCreditErrorCode.creditBelow80.rawValue,
                score: score,
                action: "抽签报名"
            )
            return
        }
        if let code = LotteryErrorCode(rawValue: e.code) {
            switch code {
            case .authRequired, .unauthorized, .loginRequired:
                needsLogin = true
            case .realNameRequired:
                needsRealName = true
            case .depositNotFrozen:
                needsDeposit = true
            case .addressRequired:
                break
            case .duplicateIdNo, .duplicateDevice, .duplicateAddress, .duplicatePayAccount:
                ToastCenter.shared.show(
                    (e.message.isEmpty ? code.fallbackMessage : e.message) + " · " + LotteryCopy.duplicateHint,
                    .error
                )
                return
            default:
                break
            }
            ToastCenter.shared.show(
                e.message.isEmpty ? code.fallbackMessage : e.message,
                code.opensLogin ? .info : .error
            )
            return
        }
        ToastCenter.shared.show(e.message.isEmpty ? LotteryCopy.weakNetRetry : e.message, .error)
    }
}
