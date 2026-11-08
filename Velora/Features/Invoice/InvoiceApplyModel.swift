import Foundation
import Combine

/// Proxy invoice apply + history (DES-v1.3-05-02 §5 / §9).
@MainActor
final class InvoiceApplyModel: ObservableObject {
    enum Tab: Int, CaseIterable {
        case apply = 0
        case history = 1

        var title: String {
            switch self {
            case .apply: return "申请"
            case .history: return "记录"
            }
        }
    }

    @Published var tab: Tab = .apply
    @Published var state: LoadState = .idle
    @Published var mode: InvoiceMode = .monthly
    @Published var period: String = InvoiceLogic.previousMonthPeriod()
    @Published var preview: InvoicePreview?
    @Published var titles: [InvoiceTitle] = []
    @Published var selectedTitleId: Int64?
    @Published var selectedOrderIds: Set<Int64> = []
    @Published var history: [InvoiceRequest] = []
    @Published var submitting = false
    @Published var showConfirm = false
    @Published var submittedId: Int64?
    @Published var launchGateOpen = false
    @Published var canInvoiceService = true
    @Published var isProxyAgent = true
    @Published var accountFrozen = false

    private var submitIdempotencyKey: String?

    var defaultTitle: InvoiceTitle? {
        titles.first(where: \.isDefault) ?? titles.first
    }

    var selectedTitle: InvoiceTitle? {
        if let id = selectedTitleId {
            return titles.first { $0.id == id } ?? defaultTitle
        }
        return defaultTitle
    }

    var gateError: InvoiceErrorCode? {
        InvoiceLogic.submitGate(
            isLoggedIn: SessionStore.shared.isLoggedIn,
            isProxyAgent: isProxyAgent,
            canInvoiceService: canInvoiceService,
            launchGateOpen: launchGateOpen,
            accountFrozen: accountFrozen
        )
    }

    var canStartApply: Bool { gateError == nil }

    var selectableItems: [InvoiceRequestItem] {
        preview?.items.filter(\.isSelectable) ?? []
    }

    var confirmAmount: Int64 { preview?.amount ?? 0 }
    var confirmTax: Int64 { preview?.taxAmount ?? 0 }
    var confirmTotal: Int64 { preview?.total ?? 0 }
    var isOffsetOnly: Bool { preview?.offsetOnly == true || (confirmAmount == 0 && (preview?.pendingOffsetTotal ?? 0) > 0) }

    var canSubmit: Bool {
        guard canStartApply, !submitting, let preview else { return false }
        guard selectedTitle != nil, !(selectedTitle?.isPendingReview ?? false) else { return false }
        if mode == .perOrder, selectedOrderIds.isEmpty { return false }
        return preview.allowsSubmit
    }

    func load() async {
        if state == .idle { state = .loading }
        await refreshCapabilities()
        async let titlesTask: () = loadTitles()
        async let historyTask: () = loadHistory()
        async let previewTask: () = refreshPreview()
        _ = await (titlesTask, historyTask, previewTask)
        if selectedTitleId == nil {
            selectedTitleId = defaultTitle?.id
        }
        if case .failed = state { return }
        state = .loaded
    }

    func setMode(_ next: InvoiceMode) async {
        guard mode != next else { return }
        mode = next
        selectedOrderIds = []
        if next == .monthly {
            period = InvoiceLogic.previousMonthPeriod()
        }
        await refreshPreview()
    }

    func toggleOrder(_ id: Int64) async {
        guard mode == .perOrder else { return }
        if selectedOrderIds.contains(id) {
            selectedOrderIds.remove(id)
        } else if selectedOrderIds.count < InvoiceConfigDefaults.maxOrdersPerRequest {
            selectedOrderIds.insert(id)
        }
        await refreshPreview()
    }

    func refreshPreview() async {
        do {
            let orderIds = mode == .perOrder ? Array(selectedOrderIds).sorted() : []
            if mode == .perOrder, orderIds.isEmpty {
                // Still hit preview without ids to get pool + gate flags.
                let p = try await API.invoicePreview(mode: mode, period: period, orderIds: [])
                applyPreview(p)
                return
            }
            let p = try await API.invoicePreview(mode: mode, period: period, orderIds: orderIds)
            applyPreview(p)
        } catch let e as APIError {
            if preview == nil {
                state = .failed(e.message)
            } else {
                ToastCenter.shared.show(e.message, .error)
            }
        } catch {
            if preview == nil {
                state = .failed("预览加载失败")
            }
        }
    }

    func prepareConfirm() {
        guard canSubmit else {
            if let err = gateError {
                ToastCenter.shared.show(err.fallbackMessage, .info)
            } else if selectedTitle == nil {
                ToastCenter.shared.show("请先维护发票抬头", .info)
            } else if selectedTitle?.isPendingReview == true {
                ToastCenter.shared.show(InvoiceErrorCode.invoiceTitlePendingReview.fallbackMessage, .info)
            } else {
                ToastCenter.shared.show(InvoiceErrorCode.nothingToInvoice.fallbackMessage, .info)
            }
            return
        }
        submitIdempotencyKey = UUID().uuidString
        showConfirm = true
    }

    func submit() async {
        guard let title = selectedTitle, canSubmit else { return }
        submitting = true
        defer { submitting = false }
        let key = submitIdempotencyKey ?? UUID().uuidString
        submitIdempotencyKey = key
        let orderIds: [Int64]? = mode == .perOrder ? Array(selectedOrderIds).sorted() : nil
        let body = InvoiceSubmitBody(
            mode: mode,
            period: period,
            titleId: title.id,
            orderIds: orderIds
        )
        do {
            let req = try await API.submitInvoiceRequest(body, idempotencyKey: key)
            showConfirm = false
            submittedId = req.id
            ToastCenter.shared.show(InvoiceCopy.submitSuccess, .success)
            await loadHistory()
            tab = .history
            selectedOrderIds = []
            await refreshPreview()
        } catch let e as APIError {
            let code = InvoiceErrorCode(rawValue: e.code)
            ToastCenter.shared.show(code?.fallbackMessage ?? e.message, .error)
            if code == .invoiceLockConflict || code == .invoicePeriodLocked {
                await refreshPreview()
            }
        } catch {
            ToastCenter.shared.show("提交失败，请重试", .error)
        }
    }

    private func applyPreview(_ p: InvoicePreview) {
        preview = p
        if let open = p.launchGateOpen {
            launchGateOpen = open
        }
        if let period = p.period, mode == .monthly, !period.isEmpty {
            self.period = period
        }
        if mode == .perOrder {
            // Drop selections that became unselectable.
            let selectable = Set(p.items.filter(\.isSelectable).map(\.orderId))
            selectedOrderIds = selectedOrderIds.intersection(selectable)
        } else {
            selectedOrderIds = Set(p.items.map(\.orderId))
        }
    }

    private func loadTitles() async {
        do {
            titles = try await API.invoiceTitles()
        } catch {
            // Soft-fail: apply still works if titles arrive empty; user sees empty state.
            if titles.isEmpty { titles = [] }
        }
    }

    private func loadHistory() async {
        do {
            let page = try await API.invoiceRequests(page: 1)
            history = page.items
        } catch {
            // Keep prior history on refresh failure.
        }
    }

    private func refreshCapabilities() async {
        accountFrozen = SessionStore.shared.user?.isFrozen == true
        do {
            let profile = try await API.proxySellerProfile()
            isProxyAgent = profile.isProxyAgent
            canInvoiceService = profile.capabilities?.canInvoiceService ?? true
        } catch {
            // Fall back to bootstrap seller projection when profile endpoint lags.
            if let boot = SessionStore.shared.bootstrap {
                isProxyAgent = boot.seller?.sellerType == ProxyAgentConfigDefaults.sellerType
                canInvoiceService = boot.seller?.capabilities.canInvoiceService ?? canInvoiceService
            }
        }
        // Gate defaults closed until preview/bootstrap says otherwise (design §5.1).
        if preview?.launchGateOpen == nil,
           let flag = SessionStore.shared.bootstrap?.flags[InvoiceConfigDefaults.launchGateKey] {
            launchGateOpen = flag
        }
    }
}
