import SwiftUI

/// 代拍开票：可开票池 / 申请 / 历史（DES-v1.3-05-02 §5.1 / §9）。
struct InvoiceHomeView: View {
    @StateObject private var model = InvoiceApplyModel()
    @State private var showTitleEditor = false

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VErrorView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(InvoiceCopy.homeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $model.showConfirm) {
            confirmSheet
        }
        .sheet(isPresented: $showTitleEditor) {
            NavigationStack {
                InvoiceTitleEditorView(existing: model.titles) {
                    showTitleEditor = false
                    Task { await model.load() }
                }
            }
        }
        .navigationDestination(item: $model.submittedId) { id in
            InvoiceDetailView(requestId: id)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VPillSegments(
                items: InvoiceApplyModel.Tab.allCases.map { ($0.rawValue, $0.title) },
                selection: Binding(
                    get: { model.tab.rawValue },
                    set: { model.tab = InvoiceApplyModel.Tab(rawValue: $0) ?? .apply }
                )
            )
            .padding(.horizontal, VSpace.l)
            .padding(.vertical, VSpace.m)

            switch model.tab {
            case .apply:
                applyScroll
            case .history:
                historyScroll
            }
        }
    }

    private var applyScroll: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if let gate = model.gateError {
                        gateBanner(gate)
                    }
                    modeCard
                    basisCard
                    titleCard
                    if model.mode == .perOrder {
                        orderPickCard
                    } else {
                        monthlyItemsCard
                    }
                    offsetsCard
                    amountCard
                }
                .padding(VSpace.l)
                .padding(.bottom, 88)
            }
            submitBar
        }
    }

    private var historyScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.m) {
                if model.history.isEmpty {
                    VEmptyState(
                        icon: "doc.text",
                        title: InvoiceCopy.emptyHistory,
                        message: InvoiceCopy.emptyPoolHint
                    )
                } else {
                    ForEach(model.history) { req in
                        NavigationLink {
                            InvoiceDetailView(requestId: req.id, seed: req)
                        } label: {
                            historyRow(req)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(VSpace.l)
        }
    }

    private func gateBanner(_ code: InvoiceErrorCode) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(code.fallbackMessage)
                    .font(.vHeadline)
                    .foregroundStyle(Color.vText)
                Text(code == .launchGateClosed ? InvoiceCopy.gateClosedHint : InvoiceCopy.capabilityReadOnly)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var modeCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("开票方式").font(.vHeadline)
                HStack(spacing: 10) {
                    modeChip(.monthly)
                    modeChip(.perOrder)
                }
                Text(model.mode == .monthly ? InvoiceCopy.monthlyNoPick : InvoiceCopy.selectOrders)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                Text("账期 \(model.period)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
        .opacity(model.canStartApply ? 1 : 0.55)
        .disabled(!model.canStartApply)
    }

    private func modeChip(_ mode: InvoiceMode) -> some View {
        let on = model.mode == mode
        return Button {
            Task { await model.setMode(mode) }
        } label: {
            Text(mode.displayLabel)
                .font(.vCaptionMedium)
                .foregroundStyle(on ? Color.white : Color.vText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? Color.vPrimary : Color.vFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var basisCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("开票口径").font(.vHeadline)
                if let preview = model.preview {
                    Text(preview.resolvedBasisLabel)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                    Text(preview.basis.plainExplanation)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    if let type = preview.invoiceType {
                        Text(type.displayLabel)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                } else {
                    Text(InvoiceBasis.platformFee.plainExplanation)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }

    private var titleCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text(InvoiceCopy.titlesTitle).font(.vHeadline)
                    Spacer()
                    Button("管理") { showTitleEditor = true }
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                }
                if let title = model.selectedTitle {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.title).font(.vBodyMedium)
                        if let tax = title.taxNoMasked {
                            Text(tax).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        if !title.displayEmail.isEmpty {
                            Text(title.displayEmail).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                        if title.isPendingReview {
                            Text(InvoiceErrorCode.invoiceTitlePendingReview.fallbackMessage)
                                .font(.vMicro)
                                .foregroundStyle(Color.vGold)
                        }
                    }
                    if model.titles.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(model.titles) { t in
                                    Button {
                                        model.selectedTitleId = t.id
                                    } label: {
                                        Text(t.title)
                                            .font(.vMicro)
                                            .foregroundStyle(model.selectedTitleId == t.id ? Color.white : Color.vText)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                model.selectedTitleId == t.id ? Color.vPrimary : Color.vFill,
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    Text("尚未配置抬头，请先添加企业抬头与税号")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    Button("添加抬头") { showTitleEditor = true }
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                }
            }
        }
    }

    private var monthlyItemsCard: some View {
        VCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("可开票订单")
                    .font(.vHeadline)
                    .padding(VSpace.l)
                if let items = model.preview?.items, !items.isEmpty {
                    ForEach(items) { item in
                        itemRow(item, selectable: false)
                        if item.id != items.last?.id { VDivider() }
                    }
                } else {
                    VEmptyState(
                        icon: "tray",
                        title: InvoiceCopy.emptyPool,
                        message: InvoiceCopy.emptyPoolHint
                    )
                    .padding(.bottom, VSpace.l)
                }
            }
        }
    }

    private var orderPickCard: some View {
        VCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(InvoiceCopy.selectOrders)
                    .font(.vHeadline)
                    .padding(VSpace.l)
                if let items = model.preview?.items, !items.isEmpty {
                    ForEach(items) { item in
                        Button {
                            guard item.isSelectable else { return }
                            Task { await model.toggleOrder(item.orderId) }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: model.selectedOrderIds.contains(item.orderId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isSelectable ? Color.vPrimary : Color.vTextTertiary)
                                itemRowContent(item)
                            }
                            .padding(.horizontal, VSpace.l)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(!item.isSelectable || !model.canStartApply)
                        if item.id != items.last?.id { VDivider() }
                    }
                } else {
                    VEmptyState(
                        icon: "tray",
                        title: InvoiceCopy.emptyPool,
                        message: InvoiceCopy.emptyPoolHint
                    )
                    .padding(.bottom, VSpace.l)
                }
            }
        }
    }

    private func itemRow(_ item: InvoiceRequestItem, selectable: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if selectable {
                Image(systemName: model.selectedOrderIds.contains(item.orderId) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.vPrimary)
            }
            itemRowContent(item)
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, 12)
    }

    private func itemRowContent(_ item: InvoiceRequestItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.orderNo.map { "订单 \($0)" } ?? "订单 #\(item.orderId)")
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vText)
                Text("成交 \(InvoiceLogic.yuanDisplay(item.gmv)) · 服务费 \(InvoiceLogic.yuanDisplay(item.platformFee))")
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                if let reason = item.blockReason {
                    Text(reason).font(.vMicro).foregroundStyle(Color.vGold)
                }
            }
            Spacer()
            Text(InvoiceLogic.yuanDisplay(item.invoiceableAmount))
                .font(.vMono(15))
                .foregroundStyle(Color.vText)
        }
    }

    @ViewBuilder
    private var offsetsCard: some View {
        if let preview = model.preview, preview.pendingOffsetTotal > 0 {
            VCard {
                HStack {
                    Text(InvoiceLogic.offsetLine(amountFen: preview.pendingOffsetTotal))
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vPrimary)
                    Spacer()
                }
            }
        }
    }

    private var amountCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                amountRow(InvoiceCopy.amountLabel, model.confirmAmount)
                amountRow(InvoiceCopy.taxLabel, model.confirmTax)
                VDivider()
                amountRow(InvoiceCopy.taxInclusiveTotal, model.confirmTotal, emphasize: true)
                if model.isOffsetOnly {
                    Text(InvoiceCopy.offsetOnlyNote)
                        .font(.vMicro)
                        .foregroundStyle(Color.vGold)
                }
                if let warn = model.preview?.lockWarning, !warn.isEmpty {
                    Text(warn).font(.vMicro).foregroundStyle(Color.vGold)
                }
            }
        }
    }

    private func amountRow(_ label: String, _ fen: Int64, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasize ? .vHeadline : .vCaption)
                .foregroundStyle(emphasize ? Color.vText : Color.vTextSecondary)
            Spacer()
            Text(InvoiceLogic.yuanDisplay(fen))
                .font(emphasize ? .vMono(18) : .vMono(15))
                .foregroundStyle(Color.vText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var submitBar: some View {
        VStack(spacing: 0) {
            VDivider()
            VPrimaryButton(
                title: InvoiceCopy.confirmSubmit,
                loading: model.submitting,
                disabled: !model.canSubmit
            ) {
                model.prepareConfirm()
            }
            .padding(VSpace.l)
        }
        .background(Color.vSurface)
    }

    private var confirmSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    Text("确认开票申请").font(.vTitle())
                    if let title = model.selectedTitle {
                        labeled("抬头", title.title)
                        if let tax = title.taxNoMasked { labeled("税号", tax) }
                        if !title.displayEmail.isEmpty { labeled("邮箱", title.displayEmail) }
                    }
                    labeled("账期", model.period)
                    labeled("方式", model.mode.displayLabel)
                    if let preview = model.preview {
                        labeled("口径", preview.resolvedBasisLabel)
                    }
                    amountCard
                    if let items = model.preview?.items {
                        let shown = model.mode == .perOrder
                            ? items.filter { model.selectedOrderIds.contains($0.orderId) }
                            : items
                        VCard(padding: 0) {
                            ForEach(shown) { item in
                                itemRow(item, selectable: false)
                                if item.id != shown.last?.id { VDivider() }
                            }
                        }
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("确认提交")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.showConfirm = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VPrimaryButton(
                    title: InvoiceCopy.confirmSubmit,
                    loading: model.submitting,
                    disabled: model.submitting
                ) {
                    Task { await model.submit() }
                }
                .padding(VSpace.l)
                .background(Color.vSurface)
            }
        }
        .presentationDetents([.large])
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.vCaption).foregroundStyle(Color.vTextSecondary).frame(width: 56, alignment: .leading)
            Text(v).font(.vBodyMedium).foregroundStyle(Color.vText)
            Spacer()
        }
    }

    private func historyRow(_ req: InvoiceRequest) -> some View {
        VCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(req.period).font(.vHeadline)
                        VTagChip(
                            text: req.status.displayLabel,
                            tint: statusTint(req.status),
                            background: statusTint(req.status).opacity(0.12)
                        )
                    }
                    Text(req.mode.displayLabel)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    if let no = req.invoiceNo {
                        Text("发票号 \(no)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    }
                    if req.isOffsetOnly {
                        Text(InvoiceCopy.offsetOnlyNote).font(.vMicro).foregroundStyle(Color.vGold)
                    }
                }
                Spacer()
                Text(InvoiceLogic.yuanDisplay(req.total))
                    .font(.vMono(16))
                    .foregroundStyle(Color.vText)
            }
        }
    }

    private func statusTint(_ status: InvoiceRequestStatus) -> Color {
        switch status {
        case .issued: return .vGreen
        case .rejected: return .vPrimary
        case .issuing, .submitted: return .vGold
        case .draft: return .vTextSecondary
        }
    }
}

// MARK: - Title editor

struct InvoiceTitleEditorView: View {
    let existing: [InvoiceTitle]
    var onDone: () -> Void

    @State private var title = ""
    @State private var taxNo = ""
    @State private var email = ""
    @State private var isDefault = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("企业名称 / 抬头", text: $title)
                TextField("统一社会信用代码", text: $taxNo)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("接收邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Toggle("设为默认", isOn: $isDefault)
            } footer: {
                Text("最多 \(InvoiceConfigDefaults.maxTitlesPerSeller) 个抬头；变更税号需运营审核后方可使用。")
                    .font(.vMicro)
            }
            if let error {
                Section { Text(error).foregroundStyle(Color.vPrimary).font(.vCaption) }
            }
            if !existing.isEmpty {
                Section("已有抬头") {
                    ForEach(existing) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.vBodyMedium)
                            Text([t.taxNoMasked, t.displayEmail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(InvoiceCopy.titlesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(saving || !InvoiceLogic.canAddTitle(existingCount: existing.count))
            }
        }
    }

    private func save() async {
        if let msg = InvoiceLogic.validateTitleForm(title: title, taxNo: taxNo, email: email) {
            error = msg
            return
        }
        if !InvoiceLogic.canAddTitle(existingCount: existing.count) {
            error = "最多维护 \(InvoiceConfigDefaults.maxTitlesPerSeller) 个抬头"
            return
        }
        saving = true
        defer { saving = false }
        do {
            _ = try await API.upsertInvoiceTitle(
                InvoiceTitleUpsertBody(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    taxNo: taxNo.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDefault: isDefault
                )
            )
            ToastCenter.shared.show("抬头已保存", .success)
            onDone()
        } catch let e as APIError {
            error = InvoiceErrorCode(rawValue: e.code)?.fallbackMessage ?? e.message
        } catch {
            self.error = "保存失败"
        }
    }
}
