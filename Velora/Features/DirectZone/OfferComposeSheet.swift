import SwiftUI

/// Create / counter offer sheet (DES-v1.3-04-02 §5.1–5.2 / §9).
struct OfferComposeSheet: View {
    enum Mode: Equatable {
        case create
        case counter(offerId: Int64, asBuyer: Bool)
    }

    let listingId: Int64
    let listPriceFen: Int64
    let title: String
    let cover: String?
    let minPriceFen: Int64
    let mode: Mode
    var round: Int = 1
    var buyerQuoteCount: Int = 0
    var onDone: ((OfferCard?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OfferActionModel()
    @State private var yuan = ""
    @FocusState private var focused: Bool

    private var priceFen: Int64? {
        guard let v = Double(yuan.replacingOccurrences(of: ",", with: "")) else { return nil }
        return Int64((v * 100).rounded())
    }

    private var asBuyerQuote: Bool {
        switch mode {
        case .create: return true
        case .counter(_, let asBuyer): return asBuyer
        }
    }

    private var localError: String? {
        guard let priceFen else { return yuan.isEmpty ? nil : "请输入有效金额" }
        return OfferLogic.localPriceMessage(
            priceFen: priceFen,
            listPriceFen: listPriceFen,
            minPriceFen: minPriceFen,
            asBuyerQuote: asBuyerQuote
        )
    }

    private var canSubmit: Bool {
        priceFen != nil && localError == nil && !model.busy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    listingRow
                    rules
                    amountField
                    if let localError {
                        Text(localError)
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                    }
                    Text(OfferCopy.ttlRule + " · " + OfferCopy.lockPayRule)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle(mode == .create ? OfferCopy.sheetTitle : OfferCopy.counterTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .create ? OfferCopy.submitOffer : OfferCopy.submitCounter) {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                if yuan.isEmpty {
                    yuan = defaultYuan()
                }
                focused = true
            }
            .onChange(of: model.needsLogin) { _, need in
                if need { model.needsLogin = false }
            }
            .sheet(isPresented: $model.needsRealName) {
                NavigationStack { RealNameView() }
            }
        }
    }

    private var listingRow: some View {
        HStack(spacing: 10) {
            RemoteImage(cover ?? "")
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.vCaptionMedium).lineLimit(2)
                Text("\(OfferCopy.listPriceLabel) \(OfferLogic.yuanDisplay(listPriceFen))")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                Text(OfferCopy.roundLabel(round: round))
                    .font(.vMicro)
                    .foregroundStyle(Color.vBlue)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private var rules: some View {
        Text(OfferCopy.emptyBuyer(minPriceFen: minPriceFen))
            .font(.vCaption)
            .foregroundStyle(Color.vTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(OfferCopy.offerPriceLabel)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            HStack(spacing: 4) {
                Text("¥").font(.vPrice(24)).foregroundStyle(Color.vPrimary)
                TextField("0", text: $yuan)
                    .keyboardType(.decimalPad)
                    .font(.vPrice(30))
                    .foregroundStyle(Color.vPrimary)
                    .focused($focused)
                    .accessibilityLabel("报价金额")
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            HStack(spacing: 8) {
                chip("最低", fen: minPriceFen)
                chip("标价", fen: listPriceFen)
                if listPriceFen > minPriceFen {
                    let mid = (minPriceFen + listPriceFen) / 2
                    chip("折中", fen: mid)
                }
            }
        }
    }

    private func chip(_ title: String, fen: Int64) -> some View {
        Button {
            yuan = Self.formatYuan(fen)
            Haptics.light()
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.vMicro).opacity(0.85)
                Text(OfferLogic.yuanDisplay(fen)).font(.vMono(12, weight: .bold))
            }
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func defaultYuan() -> String {
        Self.formatYuan(max(minPriceFen, (minPriceFen + listPriceFen) / 2))
    }

    private static func formatYuan(_ fen: Int64) -> String {
        if fen % 100 == 0 { return String(fen / 100) }
        return String(format: "%.2f", Double(fen) / 100)
    }

    private func submit() async {
        guard let priceFen, localError == nil else { return }
        let card: OfferCard?
        switch mode {
        case .create:
            card = await model.createOffer(listingId: listingId, priceFen: priceFen)
        case .counter(let offerId, _):
            card = await model.counterOffer(offerId: offerId, priceFen: priceFen)
        }
        if let card {
            onDone?(card)
            dismiss()
        } else if model.lastCard != nil {
            onDone?(model.lastCard)
            dismiss()
        }
    }
}

/// Reject reason sheet (design §5.2).
struct OfferRejectSheet: View {
    let offerId: Int64
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = OfferActionModel()
    @State private var reason: OfferRejectReasonCode = .priceNotFit
    @State private var note = ""

    private var noteError: String? {
        OfferLogic.validateRejectNote(reason: reason, note: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(OfferRejectReasonCode.allCases, id: \.rawValue) { r in
                        Button {
                            reason = r
                        } label: {
                            HStack {
                                Text(r.title).foregroundStyle(Color.vText)
                                Spacer()
                                if reason == r {
                                    Image(systemName: "checkmark").foregroundStyle(Color.vPrimary)
                                }
                            }
                        }
                    }
                }
                if reason.requiresNote {
                    Section("补充说明") {
                        TextField("不超过 \(OfferConfigDefaults.rejectOtherMaxChars) 字", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                        if let noteError {
                            Text(noteError).font(.vCaption).foregroundStyle(Color.vPrimary)
                        }
                    }
                }
            }
            .navigationTitle(OfferCopy.rejectTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认拒绝") {
                        Task {
                            if await model.rejectOffer(offerId: offerId, reason: reason, note: note) {
                                onDone?()
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.busy || noteError != nil)
                }
            }
        }
    }
}
