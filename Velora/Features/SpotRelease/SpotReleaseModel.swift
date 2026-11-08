import Foundation
import Combine

/// Spot release detail / rush (DES-v1.3-06-01 REL-01/10/12 / D23).
@MainActor
final class SpotReleaseModel: ObservableObject {
    let releaseId: Int64

    @Published var detail: SpotReleaseDetail?
    @Published var state: LoadState = .idle
    @Published var selectedSKUId: Int64?
    @Published var address: Address?
    @Published var busy = false
    @Published var needsLogin = false
    @Published var needsRealName = false
    @Published var needsExclusiveDeposit = false
    @Published var vipWindowMessage: String?
    @Published var createdOrderId: Int64?
    @Published var createdOrder: Order?
    @Published var showSoldOut = false

    /// Sticky idempotency keys across retries (design §5.4).
    private var reserveIdempotencyKey: String?
    private var orderIdempotencyKey: String?
    private var depositIdempotencyKey: String?
    private var pollTask: Task<Void, Never>?

    init(releaseId: Int64) {
        self.releaseId = releaseId
    }

    deinit {
        pollTask?.cancel()
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

    var cta: SpotReleaseCTA {
        guard let detail else { return .reserve }
        return SpotReleaseLogic.resolveCTA(detail: detail, serverNow: serverNow, isLoggedIn: isLoggedIn)
    }

    var countdownSeconds: Int {
        guard let detail, let start = detail.startAt else { return 0 }
        if SpotReleaseLogic.isSaleOpen(detail, serverNow: serverNow) { return 0 }
        return SpotReleaseLogic.countdownSeconds(until: start, serverNow: serverNow)
    }

    var countdownLine: String {
        SpotReleaseLogic.countdownLine(seconds: countdownSeconds)
    }

    var showsServerTimeHint: Bool {
        true // design §9 — fixed copy beside countdown
    }

    var showsClockSkewBanner: Bool {
        SpotReleaseLogic.shouldShowServerTimeSkewHint(clientSkewMs: SessionStore.shared.serverClock.offsetMs)
    }

    var exclusiveChecklist: [SpotReleaseExclusiveChecklistItem] {
        guard let detail else { return [] }
        return SpotReleaseLogic.exclusiveChecklist(
            isLoggedIn: isLoggedIn,
            eligibility: detail.eligibility,
            exclusive: detail.isExclusive
        )
    }

    var vipClosedCopy: String? {
        if let msg = vipWindowMessage, !msg.isEmpty { return msg }
        guard let detail else { return nil }
        if let next = detail.nextWindow {
            return next.message
                ?? SpotReleaseLogic.vipWindowClosedCopy(
                    openAt: next.openAt,
                    level: detail.eligibility?.resolvedVipLevel ?? 0,
                    levelName: next.levelName
                )
        }
        return nil
    }

    func load() async {
        if detail == nil { state = .loading }
        do {
            let d = try await API.spotRelease(releaseId)
            apply(d)
            state = .loaded
            startPolling()
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
            let d = try await API.spotRelease(releaseId)
            apply(d)
            state = .loaded
        } catch {
            // Keep last good paint during poll.
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func primaryAction() async {
        switch cta {
        case .login:
            needsLogin = true
        case .reserve:
            await reserve()
        case .completeEligibility:
            await completeEligibility()
        case .rush:
            await rush()
        case .waitVIPWindow:
            if let copy = vipClosedCopy {
                ToastCenter.shared.show(copy, .info)
            } else {
                ToastCenter.shared.show(SpotReleaseCopy.vipWindowClosed, .info)
            }
        case .soldOut:
            showSoldOut = true
            ToastCenter.shared.show(SpotReleaseCopy.soldOutHint, .info)
        default:
            break
        }
    }

    func reserve() async {
        guard !busy else { return }
        if !isLoggedIn {
            needsLogin = true
            return
        }
        busy = true
        defer { busy = false }
        let key = reserveIdempotencyKey ?? UUID().uuidString
        reserveIdempotencyKey = key
        do {
            let result = try await API.reserveSpotRelease(releaseId, idempotencyKey: key)
            Haptics.success()
            ToastCenter.shared.show(
                result.alreadyReserved == true ? SpotReleaseCopy.reserved : "预约成功，开售前将提醒你",
                .success
            )
            await refresh()
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(SpotReleaseCopy.weakNetRetry, .info)
        }
    }

    func completeEligibility() async {
        guard let detail else { return }
        guard let step = SpotReleaseLogic.nextExclusiveStep(
            isLoggedIn: isLoggedIn,
            eligibility: detail.eligibility,
            exclusive: detail.isExclusive
        ) else {
            await rush()
            return
        }
        switch step {
        case .login:
            needsLogin = true
        case .realName:
            needsRealName = true
        case .deposit:
            await startExclusiveDeposit()
        }
    }

    func startExclusiveDeposit() async {
        guard !busy else { return }
        if !isLoggedIn {
            needsLogin = true
            return
        }
        busy = true
        defer { busy = false }
        let key = depositIdempotencyKey ?? UUID().uuidString
        depositIdempotencyKey = key
        do {
            let result = try await API.spotReleaseExclusiveDeposit(releaseId, idempotencyKey: key)
            if result.isFrozen {
                Haptics.success()
                ToastCenter.shared.show("保证金已冻结", .success)
                await refresh()
            } else {
                needsExclusiveDeposit = true
                ToastCenter.shared.show("请完成保证金预授权", .info)
            }
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(SpotReleaseCopy.weakNetRetry, .info)
        }
    }

    func rush() async {
        guard !busy else { return }
        if !isLoggedIn {
            needsLogin = true
            return
        }
        guard let sku = selectedSKU else {
            ToastCenter.shared.show("请选择规格", .info)
            return
        }
        let limit = detail?.resolvedLimitPerUser ?? 1
        if let err = SpotReleaseLogic.validateQty(1, limitPerUser: limit) {
            ToastCenter.shared.show(err.fallbackMessage, .info)
            return
        }
        busy = true
        defer { busy = false }
        let key = orderIdempotencyKey ?? UUID().uuidString
        orderIdempotencyKey = key
        do {
            let result = try await API.createSpotReleaseOrder(
                releaseId,
                skuId: sku.id,
                qty: 1,
                addressId: address?.id,
                idempotencyKey: key
            )
            createdOrderId = result.orderId
            orderIdempotencyKey = nil
            if let detail = try? await API.order(result.orderId) {
                createdOrder = detail.order
            }
            Haptics.success()
            await refresh()
        } catch let e as APIError {
            handleError(e)
        } catch {
            ToastCenter.shared.show(SpotReleaseCopy.weakNetRetry, .info)
        }
    }

    func selectSKU(_ id: Int64) {
        selectedSKUId = id
    }

    func setAddress(_ a: Address) {
        address = a
    }

    // MARK: - Private

    private func apply(_ d: SpotReleaseDetail) {
        detail = d
        showSoldOut = d.status == .soldOut || (SpotReleaseLogic.isSaleOpen(d, serverNow: serverNow) && d.resolvedRemaining <= 0)
        if selectedSKUId == nil {
            selectedSKUId = d.defaultSKU?.id
        }
        if let ms = d.resolvedServerNowMs {
            SessionStore.shared.applyServerTimeMs(ms)
        }
        if let next = d.nextWindow, let open = next.openAt, open > serverNow {
            vipWindowMessage = next.message
                ?? SpotReleaseLogic.vipWindowClosedCopy(
                    openAt: open,
                    level: d.eligibility?.resolvedVipLevel ?? 0,
                    levelName: next.levelName
                )
        } else {
            vipWindowMessage = nil
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let saleOpen = self.detail.map { SpotReleaseLogic.isSaleOpen($0, serverNow: self.serverNow) } ?? false
                let remaining: Int? = {
                    guard let detail = self.detail, let start = detail.startAt, !saleOpen else { return nil }
                    return SpotReleaseLogic.countdownSeconds(until: start, serverNow: self.serverNow)
                }()
                let interval = SpotReleaseLogic.pollIntervalSeconds(remainingToStart: remaining, saleOpen: saleOpen)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
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
        if let code = SpotReleaseErrorCode(rawValue: e.code) {
            switch code {
            case .authRequired, .unauthorized, .loginRequired:
                needsLogin = true
            case .realNameRequired:
                needsRealName = true
            case .exclusiveEligibilityRequired:
                if detail?.eligibility?.isRealNamed != true {
                    needsRealName = true
                } else {
                    needsExclusiveDeposit = true
                }
            case .depositNotFrozen:
                needsExclusiveDeposit = true
            case .vipWindowClosed:
                vipWindowMessage = e.message.isEmpty ? code.fallbackMessage : e.message
                ToastCenter.shared.show(vipWindowMessage ?? code.fallbackMessage, .info)
                Task { await refresh() }
                return
            case .soldOut:
                showSoldOut = true
            case .saleNotStarted:
                // Re-fetch sale_open — do not unlock on local clock.
                Task { await refresh() }
            default:
                break
            }
            ToastCenter.shared.show(e.message.isEmpty ? code.fallbackMessage : e.message, code.opensLogin ? .info : .error)
            return
        }
        ToastCenter.shared.show(e.message.isEmpty ? SpotReleaseCopy.weakNetRetry : e.message, .error)
    }
}
