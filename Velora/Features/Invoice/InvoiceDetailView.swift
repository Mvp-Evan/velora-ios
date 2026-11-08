import SwiftUI

/// 开票详情：状态时间轴、驳回原因、下载（DES-v1.3-05-02 §5.5 / §9）。
struct InvoiceDetailView: View {
    let requestId: Int64
    var seed: InvoiceRequest?

    @State private var request: InvoiceRequest?
    @State private var state: LoadState = .idle
    @State private var downloading = false
    @State private var shareURL: URL?

    init(requestId: Int64, seed: InvoiceRequest? = nil) {
        self.requestId = requestId
        self.seed = seed
        _request = State(initialValue: seed)
    }

    var body: some View {
        Group {
            switch state {
            case .idle where request == nil, .loading where request == nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where request == nil:
                VErrorView(message: message) { Task { await load() } }
            default:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(InvoiceCopy.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: Binding(
            get: { shareURL.map(IdentifiableURL.init) },
            set: { shareURL = $0?.url }
        )) { box in
            ShareSheet(items: [box.url])
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if let req = request {
                    statusHeader(req)
                    timelineCard(req)
                    if req.status == .rejected {
                        rejectCard(req)
                    }
                    if InvoiceLogic.showsIssuingStall(
                        status: req.status,
                        enteredIssuingAt: req.updatedAt ?? req.submittedAt
                    ) {
                        stallCard
                    }
                    amountCard(req)
                    if let items = req.items, !items.isEmpty {
                        itemsCard(items)
                    }
                    if req.mailDelivered == false {
                        Text(InvoiceCopy.mailFailedHint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vGold)
                            .padding(.horizontal, 4)
                    }
                    if req.canDownload {
                        VPrimaryButton(
                            title: InvoiceCopy.download,
                            icon: "square.and.arrow.down",
                            loading: downloading
                        ) {
                            Task { await download(req) }
                        }
                    } else if req.isOffsetOnly {
                        Text(InvoiceCopy.offsetOnlyNote)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                }
            }
            .padding(VSpace.l)
        }
    }

    private func statusHeader(_ req: InvoiceRequest) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(req.period).font(.vHeadline)
                    Spacer()
                    VTagChip(
                        text: req.status.displayLabel,
                        tint: tint(req.status),
                        background: tint(req.status).opacity(0.12)
                    )
                }
                Text("\(req.mode.displayLabel) · \(req.basisSnapshot?.basisLabel ?? "")")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if let no = req.invoiceNo {
                    Text("发票号 \(no)").font(.vBodyMedium)
                }
                if let title = req.title {
                    Text(title).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }

    private func timelineCard(_ req: InvoiceRequest) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("进度").font(.vHeadline)
                ForEach(InvoiceLogic.timeline(for: req.status), id: \.0) { step, done in
                    HStack(spacing: 10) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Color.vGreen : Color.vTextTertiary)
                        Text(step.title)
                            .font(.vBodyMedium)
                            .foregroundStyle(done ? Color.vText : Color.vTextTertiary)
                        Spacer()
                    }
                }
            }
        }
    }

    private func rejectCard(_ req: InvoiceRequest) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("驳回原因").font(.vHeadline)
                Text(req.rejectReason?.isEmpty == false ? (req.rejectReason ?? "") : "未填写原因")
                    .font(.vBody)
                    .foregroundStyle(Color.vText)
                Text(InvoiceCopy.rejectNextStep)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var stallCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(InvoiceCopy.issuingStall).font(.vHeadline)
                Text(InvoiceCopy.contactSupport)
                    .font(.vCaption)
                    .foregroundStyle(Color.vPrimary)
            }
        }
    }

    private func amountCard(_ req: InvoiceRequest) -> some View {
        VCard {
            VStack(spacing: 10) {
                row(InvoiceCopy.amountLabel, req.amount)
                row(InvoiceCopy.taxLabel, req.taxAmount)
                VDivider()
                row(InvoiceCopy.taxInclusiveTotal, req.total, emphasize: true)
            }
        }
    }

    private func itemsCard(_ items: [InvoiceRequestItem]) -> some View {
        VCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("明细")
                    .font(.vHeadline)
                    .padding(VSpace.l)
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.orderNo.map { "订单 \($0)" } ?? "订单 #\(item.orderId)")
                                .font(.vBodyMedium)
                            Text("成交 \(InvoiceLogic.yuanDisplay(item.gmv))")
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                        Spacer()
                        Text(InvoiceLogic.yuanDisplay(item.invoiceableAmount))
                            .font(.vMono(15))
                    }
                    .padding(.horizontal, VSpace.l)
                    .padding(.vertical, 12)
                    if item.id != items.last?.id { VDivider() }
                }
            }
        }
    }

    private func row(_ label: String, _ fen: Int64, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasize ? .vHeadline : .vCaption)
                .foregroundStyle(emphasize ? Color.vText : Color.vTextSecondary)
            Spacer()
            Text(InvoiceLogic.yuanDisplay(fen))
                .font(emphasize ? .vMono(18) : .vMono(15))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func tint(_ status: InvoiceRequestStatus) -> Color {
        switch status {
        case .issued: return .vGreen
        case .rejected: return .vPrimary
        case .issuing, .submitted: return .vGold
        case .draft: return .vTextSecondary
        }
    }

    private func load() async {
        if request == nil { state = .loading }
        do {
            request = try await API.invoiceRequest(requestId)
            state = .loaded
        } catch let e as APIError {
            if request == nil { state = .failed(e.message) }
            else { ToastCenter.shared.show(e.message, .error) }
        } catch {
            if request == nil { state = .failed("加载失败") }
        }
    }

    private func download(_ req: InvoiceRequest) async {
        downloading = true
        defer { downloading = false }
        do {
            let file = try await API.invoiceFile(req.id)
            guard let urlStr = file.url, let url = URL(string: urlStr) else {
                ToastCenter.shared.show(InvoiceErrorCode.invoiceFileNotReady.fallbackMessage, .error)
                return
            }
            // Prefer sharing the signed URL; system sheet handles open/save.
            shareURL = url
        } catch let e as APIError {
            ToastCenter.shared.show(
                InvoiceErrorCode(rawValue: e.code)?.fallbackMessage ?? e.message,
                .error
            )
        } catch {
            ToastCenter.shared.show("下载失败", .error)
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
