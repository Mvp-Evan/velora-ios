import SwiftUI
import PhotosUI

/// 发布拍品：图片 → 基本信息 → 拍卖参数 → 费用预估 → 预览提交
struct PublishView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var filters = FiltersStore.shared
    @StateObject private var draft = PublishDraft.load()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var submitting = false
    @State private var fee: FeeBreakdown?
    @State private var showPreview = false
    @State private var feeTask: Task<Void, Never>?
    @State private var legalDoc: LegalDocument?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.m) {
                    imagesSection
                    basicSection
                    attributesSection
                    auctionSection
                    feeSection
                }
                .padding(VSpace.l)
                .padding(.bottom, 100)
            }
            .background(Color.vBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("发布拍品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { draft.save(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("清空") { draft.reset(); pickerItems = [] }.foregroundStyle(Color.vTextSecondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    VPrimaryButton(title: "预览", style: .outline) { showPreview = true }.frame(width: 110)
                    VPrimaryButton(title: draft.startNow ? "立即开拍" : "定时上拍", loading: submitting, disabled: !draft.isValid, action: submit)
                }
                .padding(VSpace.l)
                .background(Color.vSurface.overlay(alignment: .top) { Rectangle().fill(Color.vSeparator).frame(height: 0.5) })
            }
            .sheet(isPresented: $showPreview) {
                if let lot = draft.previewLot(seller: session.user) {
                    NavigationStack { LotDetailView(lotId: 0, preload: lot) }
                }
            }
            .onChange(of: pickerItems) { _, items in Task { await importPhotos(items) } }
            .onChange(of: draft.startPriceYuan) { _, _ in scheduleFee() }
            .onChange(of: draft.category) { _, _ in scheduleFee() }
            .task { await filters.load(); scheduleFee() }
            .sheet(item: $legalDoc) { LegalDocumentView(document: $0) }
        }
    }

    // MARK: Sections

    private var imagesSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("拍品图片").font(.vHeadline)
                    Text("\(draft.images.count)/9 · 第一张为封面").font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    Spacer()
                    if uploading { ProgressView().controlSize(.small) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(Array(draft.images.enumerated()), id: \.offset) { i, url in
                        ZStack(alignment: .topTrailing) {
                            RemoteImage(url).frame(height: 104).clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            Button { draft.images.remove(at: i) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 20, height: 20).background(.black.opacity(0.55), in: Circle())
                            }.padding(5)
                            if i == 0 {
                                Text("封面").font(.vMicro).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.vPrimary, in: Capsule())
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(5)
                            }
                        }
                    }
                    if draft.images.count < 9 {
                        PhotosPicker(selection: $pickerItems, maxSelectionCount: 9 - draft.images.count, matching: .images) {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.fill").font(.system(size: 22)).foregroundStyle(Color.vTextTertiary)
                                Text("添加照片").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                            .frame(maxWidth: .infinity).frame(height: 104)
                            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous).strokeBorder(Color.vSeparator, style: StrokeStyle(lineWidth: 1, dash: [5])))
                        }
                    }
                }
            }
        }
    }

    private var basicSection: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("标题：品牌 + 车型 + 比例 + 亮点（60 字内）", text: $draft.title, axis: .vertical)
                        .font(.vHeadline).lineLimit(1...2)
                        .onChange(of: draft.title) { _, v in if v.count > 60 { draft.title = String(v.prefix(60)) } }
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    TextField("描述：成色细节、包装、附件、瑕疵说明、入手渠道…", text: $draft.description, axis: .vertical)
                        .font(.vBody).lineLimit(4...8)
                    HStack { Spacer(); Text("\(draft.description.count)/1000").font(.vMicro).foregroundStyle(Color.vTextTertiary) }
                }
                .padding(VSpace.l)
            }
        }
    }

    private var attributesSection: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                pickerRow("分类", required: true, options: filters.filters.categories, value: $draft.category)
                VDivider()
                pickerRow("品牌", options: filters.filters.brands, value: $draft.brand, allowCustom: true)
                VDivider()
                pickerRow("比例", options: filters.filters.scales, value: $draft.scale)
                VDivider()
                pickerRow("系列", options: filters.filters.series, value: $draft.series, allowCustom: true)
                VDivider()
                pickerRow("成色", options: filters.filters.conditions, value: $draft.condition)
                VDivider()
                pickerRow("包装", options: filters.filters.boxStatus, value: $draft.boxStatus)
                VDivider()
                VFormRow(title: "所在地") {
                    TextField("如：上海", text: $draft.location).font(.vBody).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func pickerRow(_ title: String, required: Bool = false, options: [String], value: Binding<String>, allowCustom: Bool = false) -> some View {
        VFormRow(title: title, required: required) {
            Spacer()
            Menu {
                ForEach(options, id: \.self) { o in Button(o) { value.wrappedValue = o } }
                if allowCustom {
                    Divider()
                    Button("其他…") { value.wrappedValue = "" }
                }
            } label: {
                HStack(spacing: 4) {
                    if allowCustom && !options.contains(value.wrappedValue) {
                        TextField("请选择或输入", text: value).font(.vBody).multilineTextAlignment(.trailing).frame(maxWidth: 160)
                    } else {
                        Text(value.wrappedValue.isEmpty ? "请选择" : value.wrappedValue).font(.vBody)
                            .foregroundStyle(value.wrappedValue.isEmpty ? Color.vTextTertiary : Color.vText)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private var auctionSection: some View {
        VCard(padding: 0) {
            VStack(spacing: 0) {
                moneyRow("起拍价", required: true, text: $draft.startPriceYuan, hint: "¥")
                VDivider()
                moneyRow("保留价", text: $draft.reservePriceYuan, hint: "¥", placeholder: "选填，未达则流拍")
                VDivider()
                moneyRow("加价幅度", required: true, text: $draft.incrementYuan, hint: "¥")
                VDivider()
                VFormRow(title: "拍卖时长", required: true) {
                    Spacer()
                    Picker("", selection: $draft.durationSeconds) {
                        ForEach(filters.filters.durations.isEmpty ? [3600, 21600, 86400, 259200, 604800] : filters.filters.durations, id: \.self) { d in
                            Text(durationLabel(d)).tag(d)
                        }
                    }
                    .tint(Color.vText)
                }
                VDivider()
                VFormRow(title: "防狙击") {
                    Text("平台规则：截止前 2 分钟内出价，自动延时 2 分钟")
                        .font(.vCaption).foregroundStyle(Color.vTextSecondary).multilineTextAlignment(.trailing)
                }
                VDivider()
                VFormRow(title: "开拍时间") {
                    Spacer()
                    Toggle("立即开拍", isOn: $draft.startNow).labelsHidden().tint(Color.vPrimary)
                    Text(draft.startNow ? "立即开拍" : "定时").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
                if !draft.startNow {
                    VDivider()
                    DatePicker("", selection: $draft.startAt, in: Date().addingTimeInterval(600)...Date().addingTimeInterval(30 * 86400))
                        .datePickerStyle(.compact).labelsHidden().environment(\.locale, Locale(identifier: "zh_CN"))
                        .padding(.horizontal, VSpace.l).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private func moneyRow(_ title: String, required: Bool = false, text: Binding<String>, hint: String, placeholder: String = "0") -> some View {
        VFormRow(title: title, required: required) {
            Spacer()
            HStack(spacing: 2) {
                Text(hint).foregroundStyle(Color.vTextTertiary)
                TextField(placeholder, text: text).keyboardType(.decimalPad).font(.vMono(16)).multilineTextAlignment(.trailing).frame(maxWidth: 150)
            }
        }
    }

    private var feeSection: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("费用预估").font(.vHeadline)
                    Spacer()
                    if let fee { Text("规则：\(fee.ruleName)").font(.vMicro).foregroundStyle(Color.vTextTertiary) }
                }
                if let fee {
                    VKeyValue(key: "若以起拍价成交", value: fee.hammerPrice.display)
                    VKeyValue(key: "平台服务费（\(fee.sellerRateText)）", value: "-\(fee.sellerCommission.display)", valueColor: .vTextSecondary)
                    Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                    VKeyValue(key: "预计到账", value: fee.sellerNet.display, valueColor: .vPrimary, bold: true)
                    Text("实际服务费按最终成交价计算，买家确认收货后入账钱包；收入可能涉及个人所得税，平台将按规定协助申报。")
                        .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                    HStack(spacing: 16) {
                        Button("完整拍卖规则") { legalDoc = .auctionRules }
                        Button("免责声明") { legalDoc = .disclaimer }
                    }
                    .font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                } else {
                    Text("填写起拍价后自动计算平台服务费").font(.vCaption).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func durationLabel(_ s: Int) -> String {
        s >= 86400 ? "\(s / 86400) 天" : "\(s / 3600) 小时"
    }

    // MARK: Actions

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        uploading = true
        defer { uploading = false; pickerItems = [] }
        var datas: [Data] = []
        for item in items {
            if let raw = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: raw) {
                let resized = img.resized(maxSide: 1600)
                if let jpg = resized.jpegData(compressionQuality: 0.85) { datas.append(jpg) }
            }
        }
        guard !datas.isEmpty else { return }
        do {
            let urls = try await API.upload(images: datas)
            draft.images.append(contentsOf: urls)
            draft.images = Array(draft.images.prefix(9))
        } catch { ToastCenter.shared.error(error) }
    }

    private func scheduleFee() {
        feeTask?.cancel()
        guard let price = draft.startPrice, price >= 100 else { fee = nil; return }
        let cat = draft.category
        feeTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            fee = try? await API.estimateFee(category: cat, price: price)
        }
    }

    private func submit() {
        guard let body = draft.body() else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do {
                let lot = try await API.createLot(body)
                draft.reset()
                ToastCenter.shared.show(lot.isLive ? "已上拍，祝一拍即中" : "已定时上拍", .success)
                await session.refreshMe()
                dismiss()
                router.open(lot: lot.id)
            } catch { ToastCenter.shared.error(error) }
        }
    }
}

// MARK: - Draft (persisted)

@MainActor
final class PublishDraft: ObservableObject {
    struct Snapshot: Codable {
        var images: [String] = []
        var title = ""
        var description = ""
        var category = ""
        var brand = ""
        var scale = ""
        var series = ""
        var condition = ""
        var boxStatus = ""
        var location = ""
        var startPriceYuan = ""
        var reservePriceYuan = ""
        var incrementYuan = "50"
        var durationSeconds = 86400
        var antiSnipeSeconds = 120
        var startNow = true
        var startAt = Date().addingTimeInterval(3600)
    }

    @Published var images: [String] = []
    @Published var title = ""
    @Published var description = ""
    @Published var category = ""
    @Published var brand = ""
    @Published var scale = ""
    @Published var series = ""
    @Published var condition = ""
    @Published var boxStatus = ""
    @Published var location = ""
    @Published var startPriceYuan = ""
    @Published var reservePriceYuan = ""
    @Published var incrementYuan = "50"
    @Published var durationSeconds = 86400
    @Published var antiSnipeSeconds = 120
    @Published var startNow = true
    @Published var startAt = Date().addingTimeInterval(3600)

    private static let key = "publish_draft_v1"

    init() {}

    private var snapshot: Snapshot {
        get {
            Snapshot(images: images, title: title, description: description, category: category, brand: brand, scale: scale, series: series,
                     condition: condition, boxStatus: boxStatus, location: location, startPriceYuan: startPriceYuan, reservePriceYuan: reservePriceYuan,
                     incrementYuan: incrementYuan, durationSeconds: durationSeconds, antiSnipeSeconds: antiSnipeSeconds, startNow: startNow, startAt: startAt)
        }
        set {
            images = newValue.images; title = newValue.title; description = newValue.description; category = newValue.category
            brand = newValue.brand; scale = newValue.scale; series = newValue.series; condition = newValue.condition; boxStatus = newValue.boxStatus
            location = newValue.location; startPriceYuan = newValue.startPriceYuan; reservePriceYuan = newValue.reservePriceYuan
            incrementYuan = newValue.incrementYuan; durationSeconds = newValue.durationSeconds; antiSnipeSeconds = newValue.antiSnipeSeconds
            startNow = newValue.startNow; startAt = max(newValue.startAt, Date().addingTimeInterval(3600))
        }
    }

    static func load() -> PublishDraft {
        let d = PublishDraft()
        if let raw = UserDefaults.standard.data(forKey: key), let snap = try? JSONDecoder().decode(Snapshot.self, from: raw) { d.snapshot = snap }
        return d
    }

    func save() {
        if let raw = try? JSONEncoder().encode(snapshot) { UserDefaults.standard.set(raw, forKey: Self.key) }
    }

    func reset() {
        images = []; title = ""; description = ""; category = ""; brand = ""; scale = ""; series = ""; condition = ""; boxStatus = ""; location = ""
        startPriceYuan = ""; reservePriceYuan = ""; incrementYuan = "50"; durationSeconds = 86400; antiSnipeSeconds = 120; startNow = true
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    var startPrice: Money? { Double(startPriceYuan).map { Money(($0 * 100).rounded()) } }
    var reservePrice: Money? { Double(reservePriceYuan).map { Money(($0 * 100).rounded()) } }
    var increment: Money? { Double(incrementYuan).map { Money(($0 * 100).rounded()) } }

    var isValid: Bool {
        !images.isEmpty && !title.isBlank && !category.isEmpty && (startPrice ?? 0) >= 100 && (increment ?? 0) >= 100
            && (reservePrice == nil || reservePrice! >= startPrice!)
    }

    func body() -> JSONDict? {
        guard isValid, let sp = startPrice, let inc = increment else { return nil }
        let iso = ISO8601DateFormatter()
        return JSONDict([
            "title": title.trimmingCharacters(in: .whitespaces), "description": description, "images": images,
            "category": category, "brand": brand, "scale": scale, "series": series, "condition": condition,
            "box_status": boxStatus, "location": location,
            "start_price": sp, "reserve_price": reservePrice, "bid_increment": inc,
            "start_at": startNow ? nil : iso.string(from: startAt),
            "duration_seconds": durationSeconds, "anti_snipe_seconds": antiSnipeSeconds,
        ])
    }

    /// 本地预览用的 Lot 对象
    func previewLot(seller: User?) -> Lot? {
        guard let sp = startPrice, let inc = increment, let seller else { return nil }
        let start = startNow ? Date() : startAt
        return Lot(id: 0, sellerId: seller.id, title: title, description: description, images: images, category: category, brand: brand,
                   scale: scale, series: series, condition: condition, boxStatus: boxStatus, location: location, startPrice: sp, bidIncrement: inc,
                   currentPrice: sp, currentBidderId: nil, bidCount: 0, startAt: start, endAt: start.addingTimeInterval(TimeInterval(durationSeconds)),
                   durationSeconds: durationSeconds, antiSnipeSeconds: antiSnipeSeconds, extensionCount: 0, status: startNow ? .live : .scheduled,
                   followCount: 0, viewCount: 0, winnerId: nil, orderId: nil, createdAt: Date(), seller: seller, currentBidder: nil,
                   cover: images.first ?? "", displayPrice: sp, minNextBid: sp, isFollowing: false, myBid: .init(), recentBids: [],
                   hasReserve: reservePrice != nil, reserveMet: reservePrice == nil)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let r = UIGraphicsImageRenderer(size: newSize, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
