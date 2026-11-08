import Foundation
import Combine

/// After-sale detail + negotiation + escalate + evidence/appeal gates (DES-v1.3-09-02).
@MainActor
final class AfterSaleDetailModel: ObservableObject {
    enum Mode {
        case byAfterSaleId(Int64)
        case byOrderId(Int64)
    }

    let mode: Mode
    let isSeller: Bool

    @Published var state: LoadState = .idle
    @Published var afterSale: AfterSale?
    @Published var arbitration: Arbitration?
    @Published var working = false
    @Published var offerAmountYuan = ""
    @Published var offerClaim: AfterSaleClaim = .partial
    @Published var rejectReason = ""
    @Published var returnTracking = ""
    @Published var serverTime: Date?
    @Published var fetchedAt = Date()

    init(afterSaleId: Int64, isSeller: Bool) {
        self.mode = .byAfterSaleId(afterSaleId)
        self.isSeller = isSeller
    }

    init(orderId: Int64, isSeller: Bool) {
        self.mode = .byOrderId(orderId)
        self.isSeller = isSeller
    }

    func load() async {
        if state == .idle { state = .loading }
        do {
            switch mode {
            case .byAfterSaleId(let id):
                afterSale = try await API.afterSale(id)
            case .byOrderId(let orderId):
                afterSale = try await API.afterSaleForOrder(orderId)
            }
            serverTime = afterSale?.serverTime
            fetchedAt = Date()
            if let arbId = afterSale?.arbitrationId {
                arbitration = try await API.arbitration(arbId)
            } else {
                arbitration = nil
            }
            state = .loaded
        } catch {
            if afterSale == nil {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    func sellerRemain(now: Date) -> Int {
        AfterSaleLogic.remainSeconds(
            deadline: afterSale?.sellerDueAt,
            serverTime: serverTime ?? afterSale?.serverTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: now
        )
    }

    func evidenceRemain(now: Date) -> Int {
        AfterSaleLogic.remainSeconds(
            deadline: arbitration?.evidenceDeadline,
            serverTime: serverTime ?? arbitration?.serverTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: now
        )
    }

    func appealRemain(now: Date) -> Int {
        AfterSaleLogic.remainSeconds(
            deadline: arbitration?.appealDeadline,
            serverTime: serverTime ?? arbitration?.serverTime,
            fetchedAtLocal: fetchedAt,
            nowLocal: now
        )
    }

    var canSellerRespond: Bool {
        guard isSeller, let a = afterSale else { return false }
        return AfterSaleLogic.canSellerRespond(status: a.status)
    }

    var escalateError: AfterSaleErrorCode? {
        guard let a = afterSale else { return .cannotEscalate }
        return AfterSaleLogic.canEscalate(
            status: a.status,
            timeoutAgree: a.timeoutAgree == true,
            actorIsSeller: isSeller
        )
    }

    var canEscalate: Bool { escalateError == nil }

    var canWithdraw: Bool {
        guard !isSeller, let a = afterSale else { return false }
        return AfterSaleLogic.canWithdraw(status: a.status, refundProcessing: false) == nil
    }

    var canAttachEvidence: Bool {
        guard let arb = arbitration else { return false }
        return AfterSaleLogic.canSubmitEvidence(status: arb.status) == nil
    }

    var canAppeal: Bool {
        guard let arb = arbitration else { return false }
        return AfterSaleLogic.canAppeal(
            status: arb.status,
            final: arb.final,
            appealOf: arb.appealOf,
            appealDeadline: arb.appealDeadline,
            now: serverTime ?? arb.serverTime ?? Date()
        ) == nil
    }

    func respond(action: SellerRespondAction) async {
        guard let a = afterSale else { return }
        working = true
        defer { working = false }
        let amount: Int64? = {
            guard action == .offer else { return nil }
            let yuan = Double(offerAmountYuan.replacingOccurrences(of: ",", with: "")) ?? 0
            return Int64((yuan * 100).rounded())
        }()
        let req = SellerRespondRequest(
            action: action,
            claim: action == .offer ? offerClaim : nil,
            amountCents: amount,
            reason: action == .reject ? rejectReason : nil
        )
        do {
            afterSale = try await API.respondAfterSale(id: a.id, request: req)
            ToastCenter.shared.show("已提交", .success)
            await load()
        } catch {
            mapAndToast(error)
        }
    }

    func acceptOffer() async {
        guard let a = afterSale else { return }
        working = true
        defer { working = false }
        do {
            afterSale = try await API.acceptAfterSaleOffer(id: a.id)
            ToastCenter.shared.show("已接受方案", .success)
            await load()
        } catch {
            mapAndToast(error)
        }
    }

    func withdraw() async {
        guard let a = afterSale else { return }
        working = true
        defer { working = false }
        do {
            afterSale = try await API.withdrawAfterSale(id: a.id)
            ToastCenter.shared.show("已撤销", .success)
            await load()
        } catch {
            mapAndToast(error)
        }
    }

    func escalate() async {
        guard let a = afterSale else { return }
        if let err = escalateError {
            ToastCenter.shared.show(err.fallbackMessage)
            return
        }
        working = true
        defer { working = false }
        do {
            let arb = try await API.escalateAfterSale(id: a.id)
            arbitration = arb
            ToastCenter.shared.show("已升级小法庭", .success)
            await load()
        } catch {
            mapAndToast(error)
        }
    }

    func submitReturnTracking() async {
        guard let a = afterSale else { return }
        let tracking = returnTracking.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tracking.isEmpty else {
            ToastCenter.shared.show("请填写运单号")
            return
        }
        working = true
        defer { working = false }
        do {
            afterSale = try await API.submitReturnTracking(id: a.id, trackingNo: tracking)
            ToastCenter.shared.show("已提交退货单号", .success)
            await load()
        } catch {
            mapAndToast(error)
        }
    }

    private func mapAndToast(_ error: Error) {
        if let api = error as? APIError, let mapped = AfterSaleErrorCode.normalize(api.code) {
            ToastCenter.shared.show(mapped.fallbackMessage)
        } else {
            ToastCenter.shared.error(error)
        }
    }
}
