import SwiftUI

/// 流拍页：公开「未成交」原因 + 一键重新上拍（DES-v1.3-03-05 §9 AUC-11）
struct AuctionUnsoldView: View {
    let lotId: Int64
    var preload: Lot? = nil
    var presentedAsSheet = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore
    @StateObject private var model: AuctionUnsoldModel
    @State private var showRelistSheet = false
    @State private var newLotId: Int64?

    init(lotId: Int64, preload: Lot? = nil, presentedAsSheet: Bool = false) {
        self.lotId = lotId
        self.preload = preload
        self.presentedAsSheet = presentedAsSheet
        _model = StateObject(wrappedValue: AuctionUnsoldModel(lotId: lotId, preload: preload))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if let lot = model.lot { content(lot) }
            }
        }
        .background(Color.vBackground)
        .navigationTitle("流拍")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            }
        }
        .task { await model.load() }
        .onAppear { if !presentedAsSheet { router.hideTabBar = true } }
        .onDisappear { if !presentedAsSheet { router.hideTabBar = false } }
        .sheet(isPresented: $showRelistSheet) {
            if let prefill = model.prefill {
                RelistSheet(prefill: prefill) { resp in
                    showRelistSheet = false
                    newLotId = resp.lotId
                    Task { await model.load() }
                }
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: Binding(get: { newLotId.map(IDBox.init) }, set: { newLotId = $0?.id })) { box in
            NavigationStack { LotDetailView(lotId: box.id) }
        }
    }

    private func content(_ lot: Lot) -> some View {
        let isSeller = lot.sellerId == session.user?.id
        return ScrollView {
            VStack(spacing: VSpace.l) {
                hero(lot)
                VCard {
                    HStack(spacing: 12) {
                        RemoteImage(lot.cover)
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lot.title).font(.vBodyMedium).lineLimit(2)
                            HStack(spacing: 4) {
                                ForEach(lot.tags.prefix(3), id: \.self) { VTagChip(text: $0) }
                            }
                            HStack {
                                Text("当前价").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                Spacer()
                                VPriceText(amount: lot.displayPrice, size: 16, color: .vText)
                            }
                        }
                    }
                }
                VCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("结果").font(.vHeadline)
                        Text(AuctionSettlementLogic.publicUnsoldReason(reserveNotMet: lot.hasReserve && !lot.reserveMet))
                            .font(.vBody)
                            .foregroundStyle(Color.vTextSecondary)
                        if isSeller {
                            Text(AuctionSettlementCopy.unsoldSellerHint)
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                    }
                }
                if let linked = lot.relistedToLotId ?? model.relistedToLotId {
                    Button {
                        newLotId = linked
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("\(AuctionSettlementCopy.relistedLink) · #\(linked)")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vPrimary)
                        .padding(14)
                        .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(VSpace.l)
            .padding(.bottom, isSeller ? 100 : 24)
        }
        .refreshable { await model.load() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSeller { sellerBar(lot) }
        }
    }

    private func hero(_ lot: Lot) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8E939E), Color(hex: 0x6B7280)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 22, weight: .semibold))
                    Text(AuctionSettlementCopy.unsoldTitle).font(.vTitle(22))
                    Spacer()
                }
                .foregroundStyle(.white)
                Text(lot.endAt.shortText + " 结束")
                    .font(.vCaption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(VSpace.xl)
        }
        .frame(minHeight: 120)
    }

    private func sellerBar(_ lot: Lot) -> some View {
        let can = AuctionSettlementLogic.canRelist(status: lot.status.rawValue, secondChancePending: model.secondChancePending)
        return VStack(spacing: 8) {
            if let reason = AuctionSettlementLogic.relistBlockedReason(
                status: lot.status.rawValue,
                secondChancePending: model.secondChancePending
            ) {
                Text(reason.fallbackMessage)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VPrimaryButton(
                title: AuctionSettlementCopy.relistAction,
                icon: "arrow.triangle.2.circlepath",
                loading: model.working,
                disabled: !can
            ) {
                showRelistSheet = true
            }
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, VSpace.m)
        .background(Color.vSurface.ignoresSafeArea(edges: .bottom).overlay(alignment: .top) {
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
        })
    }
}

/// Empty state for「我的出售」流拍列表（design §9）
struct UnsoldLotsEmptyView: View {
    var body: some View {
        VEmptyState(icon: "tray", title: AuctionSettlementCopy.unsoldEmpty, message: "流拍拍品会出现在这里，可一键重新上拍")
    }
}

// MARK: - Relist sheet

struct RelistSheet: View {
    let prefill: RelistPrefill
    let onDone: (RelistLotResponse) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var endAt: Date = Date().addingTimeInterval(TimeInterval(AuctionSettlementConfig.minRelistEndHours * 3600 + 3600))
    @State private var working = false
    @State private var errorMessage: String?

    private var endValid: Bool {
        AuctionSettlementLogic.isRelistEndAtValid(endAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text(AuctionSettlementCopy.relistAction).font(.vTitle(20))
            Text(AuctionSettlementCopy.relistNeedNewEnd)
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            VCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(prefill.title).font(.vBodyMedium).lineLimit(2)
                    VKeyValue(key: "起拍价", value: Money(prefill.startPrice).display)
                    VKeyValue(key: "加价幅度", value: Money(prefill.bidIncrement).display)
                    VKeyValue(key: "保证金", value: Money(prefill.depositAmount).display)
                    if let r = prefill.reservePrice {
                        VKeyValue(key: "保留价", value: Money(r).display)
                    }
                }
            }
            DatePicker("结束时间", selection: $endAt, in: Date().addingTimeInterval(3600)..., displayedComponents: [.date, .hourAndMinute])
                .font(.vBody)
            if !endValid {
                Text(AuctionSettlementCopy.relistNeedNewEnd)
                    .font(.vCaption)
                    .foregroundStyle(Color.vPrimary)
            }
            if let errorMessage {
                Text(errorMessage).font(.vCaption).foregroundStyle(Color.vPrimary)
            }
            Spacer(minLength: 0)
            VPrimaryButton(title: "确认重新上拍", loading: working, disabled: !endValid) {
                Task { await submit() }
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
    }

    private func submit() async {
        working = true
        defer { working = false }
        errorMessage = nil
        do {
            let resp = try await API.relistLot(prefill.sourceLotId, body: prefill.makeRequest(endAt: endAt))
            ToastCenter.shared.show("已重新上拍", .success)
            onDone(resp)
            dismiss()
        } catch let e as APIError {
            let code = AuctionSettlementErrorCode(rawValue: e.code)
            errorMessage = code?.fallbackMessage ?? e.message
            ToastCenter.shared.error(e)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

@MainActor
final class AuctionUnsoldModel: ObservableObject {
    let lotId: Int64
    @Published var lot: Lot?
    @Published var state: LoadState = .idle
    @Published var working = false
    @Published var secondChancePending = false
    /// When server returns outbound relist link on the old lot.
    @Published var relistedToLotId: Int64?

    init(lotId: Int64, preload: Lot?) {
        self.lotId = lotId
        self.lot = preload
        if preload != nil { state = .loaded }
    }

    var prefill: RelistPrefill? {
        guard let lot else { return nil }
        // Reserve amount is not exposed on public lot payloads; server copies from the old row.
        return RelistPrefill(
            sourceLotId: lot.id,
            title: lot.title,
            startPrice: lot.startPrice,
            bidIncrement: lot.bidIncrement,
            reservePrice: nil,
            depositAmount: lot.depositAmount,
            coverURL: lot.cover
        )
    }

    func load() async {
        if lot == nil { state = .loading }
        do {
            let l = try await API.lot(lotId)
            lot = l
            relistedToLotId = l.relistedToLotId
            state = .loaded
        } catch {
            if lot == nil { state = .failed((error as? APIError)?.message ?? "加载失败") }
        }
    }
}
