import SwiftUI

/// 税务中心：实名/税务信息 + 收入记录 + 季度申报
struct TaxCenterView: View {
    @State private var profile: TaxProfile?
    @State private var profileLoaded = false
    @State private var records: [TaxRecord] = []
    @State private var reports: [TaxReport] = []
    @State private var state: LoadState = .idle
    @State private var tab = 0
    @State private var editProfile = false
    @State private var exporting: Int64?
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: VSpace.l) {
                profileCard
                VPillSegments(items: [(0, "收入记录"), (1, "季度申报")], selection: $tab)
                switch state {
                case .idle, .loading: VLoadingView()
                case .failed(let m): VErrorView(message: m) { Task { await load() } }
                case .loaded: if tab == 0 { recordList } else { reportList }
                }
                notice
            }
            .padding(.vertical, VSpace.m)
        }
        .background(Color.vBackground)
        .navigationTitle("税务中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $editProfile) { TaxProfileForm(existing: profile) { Task { await load() } } }
        .sheet(item: Binding(get: { exportURL.map(URLBox.init) }, set: { exportURL = $0?.url })) { box in
            ShareSheet(items: [box.url])
        }
    }

    private var profileCard: some View {
        Button { editProfile = true } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: VRadius.xl, style: .continuous).fill(profile == nil ? AnyShapeStyle(Color.vSurface) : AnyShapeStyle(VGradient.carbon))
                HStack(spacing: 14) {
                    Image(systemName: profile == nil ? "person.text.rectangle" : "checkmark.shield.fill")
                        .font(.system(size: 28)).foregroundStyle(profile == nil ? Color.vPrimary : Color.vGold)
                        .frame(width: 54, height: 54).background((profile == nil ? Color.vPrimarySoft : Color.white.opacity(0.1)), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        if let p = profile {
                            Text(p.realName).font(.vHeadline).foregroundStyle(.white)
                            Text("\(p.taxpayerType.label) · \(p.idNumberMasked ?? "") · \(p.taxRegion)").font(.vCaption).foregroundStyle(.white.opacity(0.7))
                            Text(p.verifiedAt == nil ? "待核验" : "已核验").font(.vMicro).foregroundStyle(p.verifiedAt == nil ? Color.vGold : Color.vGreen)
                        } else {
                            Text("完善实名与税务信息").font(.vHeadline)
                            Text("卖出拍品前需实名；平台将依据《个人所得税法》协助申报").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(profile == nil ? Color.vTextTertiary : .white.opacity(0.6))
                }
                .padding(VSpace.l)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, VSpace.l)
    }

    private var recordList: some View {
        VCard(padding: 0) {
            if records.isEmpty { VEmptyState(icon: "doc.text", title: "暂无收入记录", message: "订单完成后自动生成") }
            else {
                VStack(spacing: 0) {
                    ForEach(records) { r in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.incomeTypeLabel).font(.vBodyMedium)
                                Text("订单 #\(r.orderId) · \(r.settledAt.relativeText) · 所属期 \(r.period)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(r.netIncome.display).font(.vMono(15))
                                Text("毛收入 \(r.grossIncome.display) · 费 \(r.platformFee.display)").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                                if r.withheldAmount > 0 { Text("预提税 \(r.withheldAmount.display)").font(.vMicro).foregroundStyle(Color.vGold) }
                            }
                        }
                        .padding(.horizontal, VSpace.l).padding(.vertical, 12)
                        if r.id != records.last?.id { VDivider() }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private var reportList: some View {
        VCard(padding: 0) {
            if reports.isEmpty { VEmptyState(icon: "calendar.badge.clock", title: "暂无季度申报", message: "每季度结束后由平台自动汇总生成") }
            else {
                VStack(spacing: 0) {
                    ForEach(reports) { r in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(r.quarter).font(.vHeadline)
                                VTagChip(text: r.statusLabel, tint: r.status == "accepted" ? .vGreen : .vGold, background: (r.status == "accepted" ? Color.vGreen : Color.vGold).opacity(0.1))
                                Spacer()
                                Button {
                                    exporting = r.id
                                    Task { await export(r) }
                                } label: {
                                    if exporting == r.id { ProgressView().controlSize(.small) }
                                    else { Label("导出", systemImage: "square.and.arrow.up").font(.vCaptionMedium) }
                                }
                            }
                            HStack(spacing: 16) {
                                kv("收入", r.totalIncome); kv("服务费", r.totalFee); kv("净收入", r.totalNet); kv("预提", r.totalWithheld)
                            }
                            Text("\(r.recordsCount) 笔 · " + (r.submittedAt.map { "提交于 \($0.shortText)" } ?? "待提交") + (r.submissionRef.map { " · 回执 \($0)" } ?? ""))
                                .font(.vMicro).foregroundStyle(Color.vTextTertiary)
                        }
                        .padding(VSpace.l)
                        if r.id != reports.last?.id { VDivider() }
                    }
                }
            }
        }
        .padding(.horizontal, VSpace.l)
    }

    private func kv(_ k: String, _ v: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            Text(v.display).font(.vMono(13))
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("关于税务", systemImage: "info.circle").font(.vCaptionMedium).foregroundStyle(Color.vTextSecondary)
            Text("依据《中华人民共和国个人所得税法》及电商平台涉税信息报送规定，平台会记录您在 Velora 的销售收入，并按季度生成申报汇总；自然人出售自用闲置物品一般免征，经营性所得需依法申报。具体以税务机关要求为准。")
                .font(.vMicro).foregroundStyle(Color.vTextTertiary).lineSpacing(3)
        }
        .padding(.horizontal, VSpace.xl)
    }

    private func load() async {
        if !profileLoaded { state = .loading }
        do {
            async let p = API.taxProfile()
            async let rec = API.taxRecords()
            async let rep = API.taxReports()
            profile = try await p; records = try await rec.items; reports = try await rep
            profileLoaded = true; state = .loaded
        } catch { state = .failed((error as? APIError)?.message ?? "加载失败") }
    }

    private func export(_ r: TaxReport) async {
        defer { exporting = nil }
        do {
            let data = try await API.exportTaxReport(r.id)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("velora-tax-\(r.quarter).csv")
            try data.write(to: url)
            exportURL = url
        } catch { ToastCenter.shared.error(error) }
    }
}

struct URLBox: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Profile form

struct TaxProfileForm: View {
    let existing: TaxProfile?
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type: TaxpayerType = .individual
    @State private var realName = ""
    @State private var idType = "id_card"
    @State private var idNumber = ""
    @State private var uscc = ""
    @State private var region = ""
    @State private var bankName = ""
    @State private var bankAccount = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: VSpace.m) {
                    VCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("纳税人类型").font(.vHeadline)
                            HStack(spacing: 8) {
                                ForEach(TaxpayerType.allCases) { t in
                                    Button { type = t; if t == .enterprise { idType = "uscc" } else if idType == "uscc" { idType = "id_card" } } label: {
                                        Text(t.label).font(type == t ? .vCaptionMedium : .vCaption)
                                            .foregroundStyle(type == t ? .white : Color.vText)
                                            .frame(maxWidth: .infinity).frame(height: 36)
                                            .background(type == t ? Color.vCarbon : Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                                    }
                                }
                            }
                        }
                    }
                    VCard(padding: 0) {
                        VStack(spacing: 0) {
                            VFormRow(title: type == .enterprise ? "企业名称" : "真实姓名", required: true) { TextField("与证件一致", text: $realName).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "证件类型", required: true) {
                                Spacer()
                                Picker("", selection: $idType) {
                                    if type != .enterprise { Text("身份证").tag("id_card"); Text("护照").tag("passport") }
                                    Text("统一社会信用代码").tag("uscc")
                                }.tint(Color.vText)
                            }
                            VDivider()
                            VFormRow(title: "证件号码", required: true) {
                                TextField(existing?.idNumberMasked ?? "加密存储，仅用于税务申报", text: $idNumber).font(.vMono(14)).multilineTextAlignment(.trailing).textInputAutocapitalization(.characters)
                            }
                            if type != .individual {
                                VDivider()
                                VFormRow(title: "信用代码") { TextField("统一社会信用代码", text: $uscc).font(.vMono(14)).multilineTextAlignment(.trailing) }
                            }
                            VDivider()
                            VFormRow(title: "税务属地") { TextField("如：上海市浦东新区", text: $region).multilineTextAlignment(.trailing) }
                        }
                    }
                    VCard(padding: 0) {
                        VStack(spacing: 0) {
                            VFormRow(title: "开户行") { TextField("用于结算与提现（选填）", text: $bankName).multilineTextAlignment(.trailing) }
                            VDivider()
                            VFormRow(title: "银行账号") { TextField(existing?.bankAccountMasked ?? "选填", text: $bankAccount).keyboardType(.numberPad).font(.vMono(14)).multilineTextAlignment(.trailing) }
                        }
                    }
                    Text("证件号与银行账号采用 AES-256 加密存储，仅在税务申报与结算时解密使用。").font(.vMicro).foregroundStyle(Color.vTextTertiary).padding(.horizontal, VSpace.s)
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("实名与税务信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid || saving) }
            }
            .onAppear {
                if let e = existing { type = e.taxpayerType; realName = e.realName; idType = e.idType; uscc = e.uscc ?? ""; region = e.taxRegion; bankName = e.bankName ?? "" }
            }
        }
    }

    private var valid: Bool { !realName.isBlank && idNumber.trimmingCharacters(in: .whitespaces).count >= 6 }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try await API.putTaxProfile(JSONDict([
                    "taxpayer_type": type.rawValue, "real_name": realName, "id_type": idType,
                    "id_number": idNumber.trimmingCharacters(in: .whitespaces),
                    "uscc": uscc, "tax_region": region, "bank_name": bankName, "bank_account": bankAccount,
                ]))
                ToastCenter.shared.show("已保存", .success); done(); dismiss()
            } catch { ToastCenter.shared.error(error) }
        }
    }
}
