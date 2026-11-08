import SwiftUI
import PhotosUI

/// 发布向导：直购 / 拍卖共用字段 + 图片规范 + 云草稿（DES-v1.3-02-05）。
struct PublishView: View {
    let tradeType: PublishTradeType

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var filters = FiltersStore.shared
    @StateObject private var model: PublishWizardModel
    @State private var productPicker: [PhotosPickerItem] = []
    @State private var flawPicker: [PhotosPickerItem] = []
    @State private var legalDoc: LegalDocument?
    @State private var showSuccess = false
    @State private var successCopy = ""
    @State private var showSubMerchantGate = false
    @State private var showSubMerchantProgress = false
    @State private var showSellerDeposit = false

    init(tradeType: PublishTradeType = .auction) {
        self.tradeType = tradeType
        _model = StateObject(wrappedValue: PublishWizardModel(tradeType: tradeType))
    }

    var body: some View {
        NavigationStack {
            formContent
                .background(Color.vBackground)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(tradeType == .fixed ? DirectZoneCopy.publishFixed : "发布拍品")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .onAppear { AppRouterProxy.router = router }
                .task { await onAppearTask() }
                .onChange(of: productPicker) { _, items in
                    Task { await loadPicker(items, flaw: false); productPicker = [] }
                }
                .onChange(of: flawPicker) { _, items in
                    Task { await loadPicker(items, flaw: true); flawPicker = [] }
                }
                .modifier(PublishDraftChangeModifier(model: model))
                .alert("发现云端草稿", isPresented: $model.showConflict) {
                    Button("恢复本地") { model.resolveConflict(.keepLocal) }
                    Button("使用云端") { model.resolveConflict(.useCloud) }
                } message: {
                    Text("本地与云端草稿不一致，请选择保留哪一份。")
                }
                .alert("提交成功", isPresented: $showSuccess) {
                    Button("好的") { dismiss() }
                } message: {
                    Text(successCopy)
                }
                .sheet(item: $legalDoc) { LegalDocumentView(document: $0) }
                .sheet(isPresented: $showSubMerchantGate) {
                    SubMerchantPublishGateSheet(
                        onOpen: {
                            showSubMerchantGate = false
                            showSubMerchantProgress = true
                        },
                        onDismiss: { showSubMerchantGate = false }
                    )
                }
                .sheet(isPresented: $showSubMerchantProgress) {
                    NavigationStack { SubMerchantProgressView(presentedAsSheet: true) }
                }
                .sheet(isPresented: $showSellerDeposit) {
                    NavigationStack { SellerDepositView(presentedAsSheet: true) }
                }
        }
    }

    private var formContent: some View {
        ScrollView {
            VStack(spacing: VSpace.m) {
                PublishImagesSection(model: model, productPicker: $productPicker)
                if model.draft.effectiveCondition?.requiresFlaw == true || !model.draft.flawImages.isEmpty {
                    PublishFlawSection(model: model, flawPicker: $flawPicker)
                }
                PublishBasicSection(model: model)
                PublishAttributesSection(model: model, filters: filters.filters)
                if tradeType == .fixed {
                    PublishFixedSection(model: model)
                } else {
                    PublishAuctionSection(model: model)
                }
                PublishFeeSection(model: model, legalDoc: $legalDoc)
            }
            .padding(VSpace.l)
            .padding(.bottom, 100)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") {
                model.saveLocal()
                Task { try? await model.saveCloudDraft() }
                dismiss()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("保存云草稿") { saveCloud() }
                Button("清空", role: .destructive) {
                    model.reset()
                    productPicker = []
                    flawPicker = []
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let msg = model.validationMessage {
                Text(msg)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VPrimaryButton(
                title: submitTitle,
                loading: model.submitting,
                disabled: !model.canSubmit,
                action: submit
            )
            .frame(width: 140)
        }
        .padding(VSpace.l)
        .background(Color.vSurface.overlay(alignment: .top) {
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
        })
    }

    private var submitTitle: String {
        switch tradeType {
        case .fixed: return "发布"
        case .auction: return model.draft.startNow ? "立即开拍" : "定时上拍"
        }
    }

    private func onAppearTask() async {
        model.onSubMerchantRequired = { showSubMerchantGate = true }
        model.onSellerDepositRequired = { showSellerDeposit = true }
        await filters.load()
        model.applySellerAuctionKindDefaults()
        async let tiers: Void = model.loadBidIncrements()
        await model.reconcileCloudOnAppear()
        await tiers
        model.syncDepositDefault()
        model.syncIncrementFloor()
        model.scheduleFeeEstimate()
    }

    private func saveCloud() {
        Task {
            do {
                try await model.saveCloudDraft()
                ToastCenter.shared.show("云草稿已保存", .success)
            } catch let e as APIError where e.code == PublishErrorCode.draftLimitExceeded.rawValue {
                ToastCenter.shared.show(PublishErrorCode.draftLimitExceeded.fallbackMessage, .error)
            } catch {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func loadPicker(_ items: [PhotosPickerItem], flaw: Bool) async {
        var datas: [Data] = []
        for item in items {
            if let raw = try? await item.loadTransferable(type: Data.self) {
                datas.append(raw)
            }
        }
        if flaw {
            await model.importFlawPhotos(datas)
        } else {
            await model.importProductPhotos(datas)
        }
    }

    private func submit() {
        Task {
            guard let result = await model.submit() else { return }
            let status = result.listingStatus
            successCopy = status?.submitSuccessCopy ?? "已提交"
            if status == .pendingReview {
                showSuccess = true
                return
            }
            ToastCenter.shared.show(successCopy, .success)
            await session.refreshMe()
            dismiss()
            if let lotId = result.lotId {
                router.open(lot: lotId)
            } else if result.listingId > 0 {
                router.open(lot: result.listingId)
            }
        }
    }
}

// MARK: - Change observer (keeps body type-check light)

private struct PublishDraftChangeModifier: ViewModifier {
    @ObservedObject var model: PublishWizardModel

    func body(content: Content) -> some View {
        content
            .onChange(of: model.draft.startPriceYuan) { _, _ in
                model.syncDepositDefault()
                model.syncIncrementFloor()
                model.scheduleFeeEstimate()
                model.scheduleAutosave()
            }
            .onChange(of: model.draft.priceYuan) { _, _ in
                model.scheduleFeeEstimate()
                model.scheduleAutosave()
            }
            .onChange(of: model.draft.freeShipping) { _, _ in
                model.scheduleFeeEstimate()
                model.scheduleAutosave()
            }
            .onChange(of: model.draft.shippingFeeYuan) { _, _ in
                model.scheduleFeeEstimate()
                model.scheduleAutosave()
            }
            .onChange(of: model.draft.title) { _, v in
                if v.count > PublishLimits.titleMax {
                    model.draft.title = String(v.prefix(PublishLimits.titleMax))
                }
                model.scheduleAutosave()
            }
    }
}

// MARK: - Sections

private struct PublishImagesSection: View {
    @ObservedObject var model: PublishWizardModel
    @Binding var productPicker: [PhotosPickerItem]

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("商品图片").font(.vHeadline)
                    Text("\(model.draft.productImages.count)/\(PublishLimits.productImageMax) · \(PublishImageNorms.remainingProductCopy(current: model.draft.productImages.count))")
                        .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    Spacer()
                    if model.uploading { ProgressView().controlSize(.small) }
                }
                if let p = model.compressProgress {
                    Text(p).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(model.draft.productImages.enumerated()), id: \.element.id) { i, slot in
                        PublishImageCell(slot: slot, cover: i == 0) {
                            model.removeProductImage(at: i)
                        }
                    }
                    if model.draft.productImages.count < PublishLimits.productImageMax {
                        PhotosPicker(
                            selection: $productPicker,
                            maxSelectionCount: PublishLimits.productImageMax - model.draft.productImages.count,
                            matching: .images
                        ) {
                            PublishAddPhotoTile()
                        }
                    }
                }
                Text("长边压缩至 \(Int(PublishLimits.maxSidePx))px · 首图为封面 · 需 \(PublishLimits.productImageMin)–\(PublishLimits.productImageMax) 张")
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
        }
    }
}

private struct PublishFlawSection: View {
    @ObservedObject var model: PublishWizardModel
    @Binding var flawPicker: [PhotosPickerItem]

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("瑕疵图").font(.vHeadline)
                    Text("\(model.draft.flawImages.count)/\(PublishLimits.flawImageMax)")
                        .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(model.draft.flawImages.enumerated()), id: \.element.id) { i, slot in
                        PublishImageCell(slot: slot, cover: false) {
                            model.removeFlawImage(at: i)
                        }
                    }
                    if model.draft.flawImages.count < PublishLimits.flawImageMax {
                        PhotosPicker(
                            selection: $flawPicker,
                            maxSelectionCount: PublishLimits.flawImageMax - model.draft.flawImages.count,
                            matching: .images
                        ) {
                            PublishAddPhotoTile()
                        }
                    }
                }
                TextField("瑕疵说明（有瑕必填，≤200 字）", text: $model.draft.flawDesc, axis: .vertical)
                    .font(.vBody).lineLimit(2...4)
                    .onChange(of: model.draft.flawDesc) { _, v in
                        if v.count > PublishLimits.flawDescMax {
                            model.draft.flawDesc = String(v.prefix(PublishLimits.flawDescMax))
                        }
                        model.scheduleAutosave()
                    }
            }
        }
    }
}

private struct PublishBasicSection: View {
    @ObservedObject var model: PublishWizardModel

    var body: some View {
        VCard(padding: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("标题（5–40 字：品牌 + 车型 + 亮点）", text: $model.draft.title, axis: .vertical)
                    .font(.vHeadline).lineLimit(1...2)
                Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                TextField("描述：成色细节、包装、附件、入手渠道…", text: $model.draft.description, axis: .vertical)
                    .font(.vBody).lineLimit(4...8)
                    .onChange(of: model.draft.description) { _, v in
                        if v.count > PublishLimits.descriptionMax {
                            model.draft.description = String(v.prefix(PublishLimits.descriptionMax))
                        }
                        model.scheduleAutosave()
                    }
                HStack {
                    Spacer()
                    Text("\(model.draft.description.count)/\(PublishLimits.descriptionMax)")
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                }
            }
            .padding(VSpace.l)
        }
    }
}

private struct PublishAttributesSection: View {
    @ObservedObject var model: PublishWizardModel
    let filters: Filters

    var body: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                PublishDictPicker(title: "品牌", options: filters.brands, value: $model.draft.brand, custom: $model.draft.customBrand, onChange: model.scheduleAutosave)
                VDivider()
                PublishDictPicker(title: "系列", options: filters.series, value: $model.draft.series, custom: $model.draft.customSeries, onChange: model.scheduleAutosave)
                VDivider()
                PublishDictPicker(title: "车型", options: [], value: $model.draft.model, custom: $model.draft.customModel, alwaysCustom: true, onChange: model.scheduleAutosave)
                VDivider()
                PublishSimplePicker(
                    title: "比例",
                    options: filters.effectiveScales.isEmpty ? [PublishLimits.defaultScale] : filters.effectiveScales,
                    value: $model.draft.scale,
                    onChange: model.scheduleAutosave
                )
                VDivider()
                VFormRow(title: "颜色") {
                    TextField("选填", text: $model.draft.color).font(.vBody).multilineTextAlignment(.trailing)
                        .onChange(of: model.draft.color) { _, _ in model.scheduleAutosave() }
                }
                VDivider()
                PublishMaterialRow(model: model)
                VDivider()
                VFormRow(title: "限量编号") {
                    TextField("如 12/500", text: $model.draft.limitedNo).font(.vBody).multilineTextAlignment(.trailing)
                        .onChange(of: model.draft.limitedNo) { _, _ in model.scheduleAutosave() }
                }
                VDivider()
                PublishConditionRow(model: model)
                if model.draft.tradeType == .fixed {
                    Text("个人闲置（二手）或全新未拆（一手）均可发布直购")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VSpace.l)
                        .padding(.vertical, 8)
                }
                VDivider()
                PublishShippingRow(model: model)
                VDivider()
                VFormRow(title: "发货地") {
                    HStack(spacing: 8) {
                        TextField("省", text: $model.draft.shipProvince).font(.vBody).multilineTextAlignment(.trailing)
                        TextField("市", text: $model.draft.shipCity).font(.vBody).multilineTextAlignment(.trailing)
                    }
                    .onChange(of: model.draft.shipProvince) { _, _ in model.scheduleAutosave() }
                    .onChange(of: model.draft.shipCity) { _, _ in model.scheduleAutosave() }
                }
                VDivider()
                PublishMoneyRow(title: "成本价", text: $model.draft.costPriceYuan, hint: "¥", placeholder: "选填，仅自己可见", onChange: model.scheduleAutosave)
            }
        }
    }
}

private struct PublishFixedSection: View {
    @ObservedObject var model: PublishWizardModel

    var body: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                PublishMoneyRow(title: "售价", required: true, text: $model.draft.priceYuan, hint: "¥", onChange: model.scheduleAutosave)
                VDivider()
                VFormRow(title: "数量") {
                    Spacer()
                    Text("1 件")
                        .font(.vBody)
                        .foregroundStyle(Color.vTextSecondary)
                        .onAppear {
                            if model.draft.stock != PublishLimits.personalStock {
                                model.draft.stock = PublishLimits.personalStock
                                model.scheduleAutosave()
                            }
                        }
                }
                VDivider()
                VFormRow(title: "可议价") {
                    Spacer()
                    Toggle("", isOn: $model.draft.negotiable).labelsHidden().tint(Color.vPrimary)
                }
            }
        }
    }
}

private struct PublishAuctionSection: View {
    @ObservedObject var model: PublishWizardModel

    private var kind: AuctionKind { model.resolvedAuctionKind }
    private var tips: PublishAuctionLiveTips { model.liveTips }
    private var showsFreeEndSchedule: Bool { kind.usesFreeEndSchedule }

    var body: some View {
        VStack(spacing: VSpace.m) {
            if model.auctionSellerType.showsAuctionKindPicker {
                auctionKindCard
            }
            paramsCard
            PublishAuctionTipsCard(tips: tips, ladderVersion: model.bidTiers.version)
        }
    }

    private var auctionKindCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                VFormRow(title: "拍卖类型", required: true) {
                    Spacer()
                    Picker("", selection: Binding(
                        get: { model.resolvedAuctionKind },
                        set: { model.setAuctionKind($0) }
                    )) {
                        ForEach(model.allowedAuctionKinds, id: \.self) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .tint(Color.vText)
                }
                VDivider()
                Text(kind.shortHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VSpace.l)
                    .padding(.vertical, 10)
                if kind.requiresEditionNo {
                    VDivider()
                    VFormRow(title: "限量编号", required: true) {
                        TextField("例 01/99", text: $model.draft.limitedNo)
                            .multilineTextAlignment(.trailing)
                            .font(.vBody)
                            .onChange(of: model.draft.limitedNo) { _, _ in model.scheduleAutosave() }
                    }
                }
            }
        }
    }

    private var paramsCard: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                PublishMoneyRow(title: "起拍价", required: true, text: $model.draft.startPriceYuan, hint: "¥", onChange: model.scheduleAutosave)
                VDivider()
                PublishMoneyRow(title: "竞拍押金", required: true, text: $model.draft.depositYuan, hint: "¥", placeholder: "默认起拍×10%", onChange: model.scheduleAutosave)
                VDivider()
                PublishMoneyRow(title: "保留价", text: $model.draft.reservePriceYuan, hint: "¥", placeholder: "选填，买家不可见", onChange: {
                    model.scheduleAutosave()
                })
                VDivider()
                PublishMoneyRow(title: "加价幅度", required: true, text: $model.draft.incrementYuan, hint: "¥", onChange: model.scheduleAutosave)
                if showsFreeEndSchedule {
                    VDivider()
                    VFormRow(title: "拍卖时长", required: true) {
                        Spacer()
                        if model.draft.useCustomEndAt {
                            Text("指定结束").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        } else {
                            Picker("", selection: $model.draft.durationDays) {
                                ForEach(PublishLimits.auctionDurationDays, id: \.self) { d in
                                    Text("\(d) 天").tag(d)
                                }
                            }
                            .tint(Color.vText)
                            .onChange(of: model.draft.durationDays) { _, _ in model.scheduleAutosave() }
                        }
                    }
                    VDivider()
                    VFormRow(title: "结束方式") {
                        Spacer()
                        Toggle("指定时刻", isOn: $model.draft.useCustomEndAt).labelsHidden().tint(Color.vPrimary)
                            .onChange(of: model.draft.useCustomEndAt) { _, _ in model.scheduleAutosave() }
                    }
                    if model.draft.useCustomEndAt {
                        VDivider()
                        DatePicker(
                            "",
                            selection: $model.draft.endAt,
                            in: Date().addingTimeInterval(PublishLimits.minEndAfterPublishSeconds)...Date().addingTimeInterval(PublishLimits.personalMaxEndSeconds),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact).labelsHidden()
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .onChange(of: model.draft.endAt) { _, _ in model.scheduleAutosave() }
                    }
                } else {
                    VDivider()
                    Text("专场拍品结束时间由运营排期，提交后等待排期通知")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VSpace.l)
                        .padding(.vertical, 10)
                }
                VDivider()
                VFormRow(title: "开拍时间") {
                    Spacer()
                    Toggle("立即开拍", isOn: $model.draft.startNow).labelsHidden().tint(Color.vPrimary)
                    Text(model.draft.startNow ? "立即开拍" : "定时").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                if !model.draft.startNow {
                    VDivider()
                    DatePicker(
                        "",
                        selection: $model.draft.startAt,
                        in: Date().addingTimeInterval(600)...Date().addingTimeInterval(30 * 86400)
                    )
                    .datePickerStyle(.compact).labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

private struct PublishAuctionTipsCard: View {
    let tips: PublishAuctionLiveTips
    let ladderVersion: Int

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.s) {
                HStack {
                    Text("参数提示").font(.vHeadline)
                    Spacer()
                    Text("阶梯 v\(ladderVersion)")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
                tipRow(tips.depositTip, ok: tips.depositOK)
                tipRow(tips.incrementTip, ok: tips.incrementOK)
                tipRow(tips.durationTip, ok: tips.durationOK)
                Text("保留价仅卖家可见；买家侧只显示「有保留价 / 已达保留价」")
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    private func tipRow(_ text: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(ok ? Color.vTextTertiary : Color.vPrimary)
                .padding(.top, 1)
            Text(text)
                .font(.vCaption)
                .foregroundStyle(ok ? Color.vTextSecondary : Color.vPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PublishFeeSection: View {
    @ObservedObject var model: PublishWizardModel
    @Binding var legalDoc: LegalDocument?

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("到手预估").font(.vHeadline)
                    Spacer()
                    if model.feeLoading { ProgressView().controlSize(.small) }
                    if let q = model.feeQuote {
                        Text("规则 \(q.ruleVersion)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    }
                }
                feeBody
            }
        }
    }

    @ViewBuilder
    private var feeBody: some View {
        if model.feeFailed && model.feeQuote == nil {
            Text(PublishErrorCode.feeUnavailable.fallbackMessage)
                .font(.vCaption).foregroundStyle(Color.vPrimary)
        } else if let fee = model.feeQuote {
            VKeyValue(key: "成交价（输入）", value: moneyDisplay(fee.price ?? model.draft.priceFen ?? 0))
            VKeyValue(key: "平台服务费（\(fee.ratePercentText)）", value: "-\(moneyDisplay(fee.platformFee))", valueColor: .vTextSecondary)
            Rectangle().fill(Color.vSeparator).frame(height: 0.5)
            VKeyValue(key: "预计到手", value: moneyDisplay(fee.sellerNet), valueColor: .vPrimary, bold: true)
            Text(fee.disclaimer).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            HStack(spacing: 16) {
                Button("完整拍卖规则") { legalDoc = .auctionRules }
                Button("免责声明") { legalDoc = .disclaimer }
            }
            .font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
        } else {
            Text("填写价格后自动估算到手金额（客户端不本地乘算费率）")
                .font(.vCaption).foregroundStyle(Color.vTextTertiary)
        }
    }

    private func moneyDisplay(_ fen: Int64) -> String {
        fen % 100 == 0 ? "¥\(fen / 100)" : String(format: "¥%.2f", Double(fen) / 100)
    }
}

// MARK: - Small shared rows

private struct PublishAddPhotoTile: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill").font(.system(size: 22)).foregroundStyle(Color.vTextTertiary)
            Text("添加照片").font(.vMicro).foregroundStyle(Color.vTextTertiary)
        }
        .frame(maxWidth: .infinity).frame(height: 104)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                .strokeBorder(Color.vSeparator, style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

private struct PublishImageCell: View {
    let slot: PublishImageSlot
    let cover: Bool
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let url = slot.url {
                    RemoteImage(url).frame(height: 104)
                } else {
                    Color.vFill.frame(height: 104)
                        .overlay(Image(systemName: "photo").foregroundStyle(Color.vTextTertiary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 20, height: 20).background(.black.opacity(0.55), in: Circle())
            }
            .padding(5)
            if cover {
                Text("封面").font(.vMicro).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.vPrimary, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(5)
            }
        }
    }
}

private struct PublishDictPicker: View {
    let title: String
    let options: [String]
    @Binding var value: String
    @Binding var custom: String?
    var alwaysCustom: Bool = false
    let onChange: () -> Void

    var body: some View {
        VFormRow(title: title) {
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in
                    Button(o) {
                        value = o
                        custom = nil
                        onChange()
                    }
                }
                Divider()
                Button("其他…") {
                    value = ""
                    if custom == nil { custom = "" }
                    onChange()
                }
            } label: {
                HStack(spacing: 4) {
                    if alwaysCustom || (value.isEmpty && custom != nil) || (!options.contains(value) && !value.isEmpty) {
                        TextField("没有找到？提交后进入词库审核", text: Binding(
                            get: { custom ?? value },
                            set: { custom = $0; value = ""; onChange() }
                        ))
                        .font(.vBody).multilineTextAlignment(.trailing).frame(maxWidth: 180)
                    } else {
                        Text(value.isEmpty ? "请选择" : value)
                            .font(.vBody)
                            .foregroundStyle(value.isEmpty ? Color.vTextTertiary : Color.vText)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }
}

private struct PublishSimplePicker: View {
    let title: String
    let options: [String]
    @Binding var value: String
    let onChange: () -> Void

    var body: some View {
        VFormRow(title: title) {
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in
                    Button(o) { value = o; onChange() }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(value.isEmpty ? "请选择" : value)
                        .font(.vBody)
                        .foregroundStyle(value.isEmpty ? Color.vTextTertiary : Color.vText)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }
}

private struct PublishMaterialRow: View {
    @ObservedObject var model: PublishWizardModel

    var body: some View {
        VFormRow(title: "材质") {
            Spacer()
            Menu {
                ForEach(PublishMaterial.allCases, id: \.rawValue) { m in
                    Button(m.label) {
                        model.draft.material = m.rawValue
                        if m != .other { model.draft.customMaterial = nil }
                        model.scheduleAutosave()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if model.draft.material == PublishMaterial.other.rawValue {
                        TextField("没有找到？提交后进入词库审核", text: Binding(
                            get: { model.draft.customMaterial ?? "" },
                            set: { model.draft.customMaterial = $0; model.scheduleAutosave() }
                        ))
                        .font(.vBody).multilineTextAlignment(.trailing).frame(maxWidth: 180)
                    } else {
                        Text(PublishMaterial(rawValue: model.draft.material)?.label
                             ?? (model.draft.material.isEmpty ? "请选择" : model.draft.material))
                            .font(.vBody)
                            .foregroundStyle(model.draft.material.isEmpty ? Color.vTextTertiary : Color.vText)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }
}

private struct PublishConditionRow: View {
    @ObservedObject var model: PublishWizardModel

    var body: some View {
        VFormRow(title: "成色", required: true) {
            Spacer()
            Menu {
                ForEach(PublishConditionGrade.allCases, id: \.rawValue) { g in
                    Button(g.label) {
                        model.draft.condition = g.rawValue
                        model.scheduleAutosave()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(PublishConditionGrade.normalize(model.draft.condition)?.label ?? "请选择")
                        .font(.vBody)
                        .foregroundStyle(model.draft.condition.isEmpty ? Color.vTextTertiary : Color.vText)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }
}

private struct PublishShippingRow: View {
    @ObservedObject var model: PublishWizardModel

    var body: some View {
        VStack(spacing: 0) {
            VFormRow(title: "运费") {
                Spacer()
                Toggle("包邮", isOn: $model.draft.freeShipping).labelsHidden().tint(Color.vPrimary)
                Text(model.draft.freeShipping ? "包邮" : "固定额").font(.vCaption).foregroundStyle(Color.vTextSecondary)
            }
            if !model.draft.freeShipping {
                VDivider()
                PublishMoneyRow(title: "运费金额", text: $model.draft.shippingFeeYuan, hint: "¥", placeholder: "元", onChange: model.scheduleAutosave)
            }
        }
    }
}

private struct PublishMoneyRow: View {
    let title: String
    var required: Bool = false
    @Binding var text: String
    let hint: String
    var placeholder: String = "0"
    let onChange: () -> Void

    var body: some View {
        VFormRow(title: title, required: required) {
            Spacer()
            HStack(spacing: 2) {
                Text(hint).foregroundStyle(Color.vTextTertiary)
                TextField(placeholder, text: $text)
                    .keyboardType(.decimalPad)
                    .font(.vMono(16))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150)
                    .onChange(of: text) { _, _ in onChange() }
            }
        }
    }
}
