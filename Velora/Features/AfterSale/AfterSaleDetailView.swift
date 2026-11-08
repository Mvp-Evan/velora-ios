import SwiftUI

/// After-sale status, seller respond, escalate, evidence / ruling / appeal entry (DES-v1.3-09-02).
struct AfterSaleDetailView: View {
    @StateObject private var model: AfterSaleDetailModel
    @ObservedObject private var ticker = Ticker.shared
    @State private var showAppeal = false
    @State private var showEvidence = false
    @State private var showRuling = false
    @State private var showOfferForm = false
    @State private var showRejectForm = false

    init(afterSaleId: Int64, isSeller: Bool) {
        _model = StateObject(wrappedValue: AfterSaleDetailModel(afterSaleId: afterSaleId, isSeller: isSeller))
    }

    init(orderId: Int64, isSeller: Bool, lookupByOrder: Bool = true) {
        _ = lookupByOrder
        _model = StateObject(wrappedValue: AfterSaleDetailModel(orderId: orderId, isSeller: isSeller))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let a = model.afterSale {
                    content(a)
                } else {
                    VEmptyState(
                        icon: "wrench.and.screwdriver",
                        title: AfterSaleCopy.applyTitle,
                        message: AfterSaleCopy.applyEmptyHint
                    )
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(AfterSaleCopy.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showAppeal) {
            if let arb = model.arbitration {
                NavigationStack {
                    ArbitrationAppealView(arbitrationId: arb.id) {
                        showAppeal = false
                        Task { await model.load() }
                    }
                }
            }
        }
        .sheet(isPresented: $showEvidence) {
            if let arb = model.arbitration {
                NavigationStack {
                    ArbitrationEvidenceAttachView(arbitrationId: arb.id) {
                        showEvidence = false
                        Task { await model.load() }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showRuling) {
            if let arb = model.arbitration {
                ArbitrationRulingView(arbitration: arb)
            }
        }
    }

    @ViewBuilder
    private func content(_ a: AfterSale) -> some View {
        ScrollView {
            VStack(spacing: VSpace.m) {
                statusCard(a)
                if let offer = a.sellerOffer {
                    offerCard(offer, afterSale: a)
                }
                if a.status == .agreed || a.status == .returnShipping, a.claim == .returnRefund {
                    returnTrackingCard(a)
                }
                if let arb = model.arbitration {
                    courtCard(arb)
                }
            }
            .padding(VSpace.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.canSellerRespond || model.canEscalate || model.canWithdraw {
                bottomBar(a)
            }
        }
        .sheet(isPresented: $showOfferForm) {
            NavigationStack { offerSheet }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showRejectForm) {
            NavigationStack { rejectSheet }
                .presentationDetents([.medium])
        }
    }

    private func statusCard(_ a: AfterSale) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(a.statusLabel).font(.vHeadline)
                    if a.showsTimeoutAgreeBadge {
                        Text(AfterSaleCopy.timeoutAgreeBadge)
                            .font(.vMicro)
                            .foregroundStyle(Color.vGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.vGold.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                }
                VKeyValue(key: "类型", value: a.typeLabel)
                VKeyValue(key: "诉求", value: a.claimLabel)
                VKeyValue(key: "金额", value: a.claimAmountCents.display)
                if let reason = a.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if a.status == .requested, a.sellerDueAt != nil {
                    let remain = model.sellerRemain(now: ticker.now)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text("\(AfterSaleCopy.sellerRemainPrefix) ")
                            .font(.vCaption)
                        Text(AfterSaleLogic.formatCountdown(remain))
                            .font(.vMono(13))
                    }
                    .foregroundStyle(Color.vText)
                    Text(AfterSaleCopy.serverTimeHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func offerCard(_ offer: SellerOffer, afterSale: AfterSale) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("卖家方案").font(.vHeadline)
                VKeyValue(key: "诉求", value: offer.claim.displayLabel)
                VKeyValue(key: "金额", value: offer.amountCents.display)
                if let note = offer.note, !note.isEmpty {
                    Text(note).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                if !model.isSeller, afterSale.status == .requested {
                    VPrimaryButton(title: AfterSaleCopy.acceptOfferCTA, loading: model.working) {
                        Task { await model.acceptOffer() }
                    }
                }
            }
        }
    }

    private func returnTrackingCard(_ a: AfterSale) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(AfterSaleCopy.returnTrackingCTA).font(.vHeadline)
                if let existing = a.returnTracking, !existing.isEmpty {
                    Text(existing).font(.vMono(14))
                } else if !model.isSeller {
                    TextField("运单号", text: $model.returnTracking)
                        .font(.vMono(14))
                        .textInputAutocapitalization(.never)
                    VPrimaryButton(title: "提交单号", loading: model.working) {
                        Task { await model.submitReturnTracking() }
                    }
                } else {
                    Text("等待买家填写退货单号")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
            }
        }
    }

    private func courtCard(_ arb: Arbitration) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(AfterSaleCopy.courtTitle).font(.vHeadline)
                    Spacer()
                    Text(arb.statusLabel)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vGold)
                }
                if arb.packetIncomplete == true {
                    Text(AfterSaleCopy.packetIncomplete)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }
                if arb.status == .evidence {
                    let remain = model.evidenceRemain(now: ticker.now)
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text("\(AfterSaleCopy.evidenceRemainPrefix) ")
                        Text(AfterSaleLogic.formatCountdown(remain)).font(.vMono(13))
                    }
                    .font(.vCaption)
                    Text(AfterSaleCopy.serverTimeHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                    if arb.buyerAbsent == true || arb.sellerAbsent == true {
                        Text(AfterSaleCopy.absentFlagLabel)
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                    }
                }
                if arb.showsAdverseBanner {
                    Text(AfterSaleCopy.adverseInferenceBanner)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(AfterSaleCopy.adverseInferenceShort)
                }
                if arb.status == .closed || arb.status == .appealReview {
                    if let label = arb.templateLabel {
                        VKeyValue(key: "裁定", value: label)
                    }
                    if arb.final {
                        Text(AfterSaleCopy.finalBadge)
                            .font(.vMicro)
                            .foregroundStyle(Color.vGreen)
                    } else if model.canAppeal {
                        let remain = model.appealRemain(now: ticker.now)
                        Text("\(AfterSaleCopy.appealRemainPrefix) \(AfterSaleLogic.formatCountdown(remain))")
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                }
                HStack(spacing: 10) {
                    if model.canAttachEvidence {
                        Button(AfterSaleCopy.attachEvidenceCTA) { showEvidence = true }
                            .font(.vCaptionMedium)
                    }
                    if arb.rulingTemplate != nil {
                        Button(AfterSaleCopy.viewRulingCTA) { showRuling = true }
                            .font(.vCaptionMedium)
                    }
                    if model.canAppeal {
                        Button(AfterSaleCopy.appealCTA) { showAppeal = true }
                            .font(.vCaptionMedium)
                    }
                }
            }
        }
    }

    private func bottomBar(_ a: AfterSale) -> some View {
        VStack(spacing: 8) {
            if model.canSellerRespond {
                HStack(spacing: 8) {
                    Button("拒绝") { showRejectForm = true }
                        .font(.vCaptionMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    Button("方案") { showOfferForm = true }
                        .font(.vCaptionMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    VPrimaryButton(title: "同意", loading: model.working) {
                        Task { await model.respond(action: .agree) }
                    }
                }
            }
            HStack(spacing: 8) {
                if model.canWithdraw {
                    Button(AfterSaleCopy.withdrawCTA) {
                        Task { await model.withdraw() }
                    }
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
                }
                if model.canEscalate {
                    VPrimaryButton(title: AfterSaleCopy.escalateCTA, icon: "building.columns", loading: model.working) {
                        Task { await model.escalate() }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, VSpace.m)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) {
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
        })
        .accessibilityLabel(a.statusLabel)
    }

    private var offerSheet: some View {
        Form {
            Section("提出方案") {
                Picker("诉求", selection: $model.offerClaim) {
                    ForEach(AfterSaleClaim.allCases) { c in
                        Text(c.displayLabel).tag(c)
                    }
                }
                TextField("金额（元）", text: $model.offerAmountYuan)
                    .keyboardType(.decimalPad)
            }
            Section {
                Button("提交方案") {
                    showOfferForm = false
                    Task { await model.respond(action: .offer) }
                }
                .disabled(model.working)
            }
        }
        .navigationTitle("卖家方案")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { showOfferForm = false }
            }
        }
    }

    private var rejectSheet: some View {
        Form {
            Section("拒绝理由") {
                TextField("请填写理由", text: $model.rejectReason, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section {
                Button("确认拒绝") {
                    showRejectForm = false
                    Task { await model.respond(action: .reject) }
                }
                .disabled(model.rejectReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.working)
            }
        }
        .navigationTitle("拒绝售后")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { showRejectForm = false }
            }
        }
    }
}
