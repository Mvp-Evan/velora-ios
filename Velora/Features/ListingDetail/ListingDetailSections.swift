import SwiftUI

// MARK: - Condition & flaw (ITEM-02)

struct ConditionFlawSection: View {
    let detail: ListingDetail
    var onOpenFlaw: ((Int) -> Void)? = nil

    @State private var expandFlawDesc = false

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack(spacing: 8) {
                    Text("成色声明").font(.vHeadline)
                    conditionBadge
                    Spacer()
                }

                if detail.conditionIncomplete {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("成色信息不完整，暂不可购买")
                        Spacer(minLength: 0)
                    }
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vPrimary)
                    .padding(10)
                    .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }

                if detail.showsFlawSection {
                    Text("瑕疵说明").font(.vCaptionMedium).foregroundStyle(Color.vTextSecondary)
                    flawDescription
                    if !detail.flawImageURLs.isEmpty {
                        Text("瑕疵图").font(.vCaptionMedium).foregroundStyle(Color.vTextSecondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(detail.flawImageURLs.enumerated()), id: \.offset) { i, url in
                                    Button { onOpenFlaw?(i) } label: {
                                        RemoteImage(url, contentMode: .fill)
                                            .frame(width: 88, height: 88)
                                            .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var conditionBadge: some View {
        let flawed = detail.conditionGrade == .flawed
        return Text(detail.conditionLabel.isEmpty ? "—" : detail.conditionLabel)
            .font(.vMicro)
            .foregroundStyle(flawed ? Color.vPrimary : Color.vTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (flawed ? Color.vPrimary.opacity(0.12) : Color.vFill),
                in: Capsule()
            )
    }

    @ViewBuilder private var flawDescription: some View {
        let text = detail.flawDesc ?? ""
        if text.isEmpty {
            EmptyView()
        } else if text.count <= ListingDetailLimits.flawDescCollapseRunes || expandFlawDesc {
            Text(text).font(.vBody).foregroundStyle(Color.vTextSecondary).lineSpacing(4)
            if text.count > ListingDetailLimits.flawDescCollapseRunes {
                Button("收起") { expandFlawDesc = false }.font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
            }
        } else {
            Text(String(text.prefix(ListingDetailLimits.flawDescCollapseRunes)) + "…")
                .font(.vBody).foregroundStyle(Color.vTextSecondary).lineSpacing(4)
            Button("展开") { expandFlawDesc = true }.font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
        }
    }
}

// MARK: - Rules snapshot

struct ListingRulesSection: View {
    let snapshot: ListingRulesSnapshot?
    var extensionCount: Int? = nil
    var onOpenFullRules: (() -> Void)? = nil

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("交易规则摘要").font(.vHeadline)
                    Spacer()
                    if let onOpenFullRules {
                        Button("查看完整规则", action: onOpenFullRules)
                            .font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                    }
                }
                let lines = snapshot?.summaryLines ?? []
                if lines.isEmpty {
                    rule("checkmark.shield", "拍中后按时付款；卖家按规则发货并支持售后协商")
                    rule("percent", "买家无需支付佣金；卖家按成交价支付平台服务费")
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        rule("checkmark.shield", line)
                    }
                }
                if let extensionCount {
                    rule("timer", "截止前 2 分钟内如有出价，拍卖自动延时 2 分钟（已延时 \(extensionCount) 次）")
                }
            }
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vPrimary).frame(width: 16).padding(.top, 2)
            Text(text).font(.vCaption).foregroundStyle(Color.vTextSecondary)
        }
    }
}

// MARK: - Q&A

struct ListingQASection: View {
    @ObservedObject var model: ListingDetailModel
    var onRequireLogin: () -> Void

    @State private var showAsk = false

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("问答").font(.vHeadline)
                    Spacer()
                    if !model.qaLocked, !model.isSeller {
                        Button("提问") {
                            if model.requireLogin() { showAsk = true } else { onRequireLogin() }
                        }
                        .font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                    }
                }

                if model.qaLocked {
                    Text("已结束，问答已关闭")
                        .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }

                if model.visibleQuestions.isEmpty {
                    Text("还没有人问，成色细节可直接问卖家")
                        .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.visibleQuestions.prefix(ListingDetailLimits.questionsPageSize).enumerated()), id: \.element.id) { i, q in
                            questionRow(q)
                            if i < min(model.visibleQuestions.count, ListingDetailLimits.questionsPageSize) - 1 {
                                VDivider().padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAsk) {
            AskQuestionSheet(model: model)
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                onRequireLogin()
                model.needsLogin = false
            }
        }
    }

    private func questionRow(_ q: ListingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(q.askerId == model.me ? "我" : (q.askerNickname ?? "买家"))
                    .font(.vCaptionMedium)
                statusChip(q)
                Spacer()
            }
            Text(q.content).font(.vBody).foregroundStyle(Color.vText)
            if q.isRejected, let reason = q.rejectReason, !reason.isEmpty {
                Text(reason).font(.vCaption).foregroundStyle(Color.vPrimary)
            } else if q.hasAnswer {
                HStack(alignment: .top, spacing: 6) {
                    Text("卖家").font(.vMicro).foregroundStyle(Color.vGold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.vGold.opacity(0.12), in: Capsule())
                    Text(q.answer ?? "").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                }
            } else if q.isPending {
                Text("审核中，仅自己可见").font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
        }
    }

    @ViewBuilder private func statusChip(_ q: ListingQuestion) -> some View {
        switch q.status {
        case .pendingMod:
            Text("待审").font(.vMicro).foregroundStyle(Color.vTextTertiary)
        case .rejected:
            Text("未通过").font(.vMicro).foregroundStyle(Color.vPrimary)
        case .locked:
            Text("已锁定").font(.vMicro).foregroundStyle(Color.vTextTertiary)
        case .visible:
            EmptyView()
        }
    }
}

struct AskQuestionSheet: View {
    @ObservedObject var model: ListingDetailModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var remaining: Int {
        ListingDetailLimits.maxQuestionRunes - model.draftQuestion.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VSpace.l) {
            Text("向卖家提问").font(.vTitle(20))
            Text("每件商品最多 \(ListingDetailLimits.maxQuestionsPerListingUser) 条（含未通过），禁止留联系方式")
                .font(.vCaption).foregroundStyle(Color.vTextSecondary)
            TextField("例如：底盘编号清晰吗？", text: $model.draftQuestion, axis: .vertical)
                .lineLimit(3...5)
                .focused($focused)
                .padding(12)
                .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            HStack {
                Text("还可写 \(max(remaining, 0)) 字").font(.vMicro).foregroundStyle(Color.vTextTertiary)
                Spacer()
                Text("已问 \(model.myQuestionCount)/\(ListingDetailLimits.maxQuestionsPerListingUser)")
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
            VPrimaryButton(title: "提交提问", loading: model.asking, disabled: model.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                Task {
                    if await model.submitQuestion() { dismiss() }
                }
            }
        }
        .padding(VSpace.xl)
        .background(Color.vSurface)
        .onAppear { focused = true }
    }
}

// MARK: - Photo request

struct PhotoRequestSection: View {
    @ObservedObject var model: ListingDetailModel
    var onRequireLogin: () -> Void
    var onOpenCamera: () -> Void

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("补图请求").font(.vHeadline)
                    Spacer()
                    if model.isSeller, !model.qaLocked {
                        Button("拍摄补图") { onOpenCamera() }
                            .font(.vCaptionMedium).foregroundStyle(Color.vPrimary)
                    }
                }

                Text("请拍清晰，水印不可裁")
                    .font(.vMicro).foregroundStyle(Color.vTextTertiary)

                if !model.photoRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.photoRequests.filter { $0.status == .open || $0.status == .merged || $0.status == .fulfilled }) { row in
                            HStack {
                                Text(row.progressText).font(.vCaptionMedium)
                                Spacer()
                                Text(statusLabel(row.status)).font(.vMicro).foregroundStyle(Color.vTextTertiary)
                            }
                        }
                    }
                }

                if !model.isSeller, !model.qaLocked {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(PhotoRequestPart.allCases, id: \.self) { part in
                                Button {
                                    if model.requireLogin() {
                                        Task { await model.requestPhoto(part: part) }
                                    } else {
                                        onRequireLogin()
                                    }
                                } label: {
                                    Text("想看\(part.title)")
                                        .font(.vCaptionMedium)
                                        .foregroundStyle(Color.vText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.vFill, in: Capsule())
                                }
                                .disabled(model.requestingPhoto)
                            }
                        }
                    }
                } else if model.qaLocked {
                    Text("商品已结束，无法再请求补图")
                        .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                }
            }
        }
        .onChange(of: model.needsLogin) { _, need in
            if need {
                onRequireLogin()
                model.needsLogin = false
            }
        }
    }

    private func statusLabel(_ s: PhotoRequestStatus) -> String {
        switch s {
        case .open, .merged: return "待补"
        case .fulfilled: return "已补"
        case .closed: return "已关闭"
        }
    }
}

// MARK: - Flaw badge before title

struct FlawConditionTitleBadge: View {
    let detail: ListingDetail
    var body: some View {
        if detail.conditionGrade == .flawed {
            Text("有瑕疵")
                .font(.vMicro)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.vPrimary, in: Capsule())
        }
    }
}
