import SwiftUI

/// 二级商户进件进度：draft → submitted → reviewing → to_sign → finished/failed（DES-v1.3-08-01 §4 / §9）。
struct SubMerchantProgressView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var presentedAsSheet = false

    @State private var model: SubMerchant?
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showSignStubAlert = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                intro
                progressStrip
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if let model {
                    statusCard(model)
                    actions(model)
                } else {
                    VEmptyState(
                        icon: "creditcard",
                        title: ProfitSharingCopy.publishGateTitle,
                        message: ProfitSharingCopy.draftHint,
                        actionTitle: ProfitSharingCopy.submitMaterials
                    ) { Task { await submit() } }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle(ProfitSharingCopy.progressTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentedAsSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onDisappear { pollTask?.cancel() }
        .alert(ProfitSharingCopy.channelSignStubTitle, isPresented: $showSignStubAlert) {
            Button("打开") { openSignStub() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(ProfitSharingCopy.channelSignStubMessage)
        }
    }

    private var intro: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(ProfitSharingCopy.publishGateTitle).font(.vHeadline)
                Text("按顺序完成提交、渠道审核与协议签约后即可收款发布。失败可修改资料重提。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var progressStrip: some View {
        let status = model?.status ?? .draft
        return HStack(spacing: 0) {
            ForEach(Array(SubMerchantProgressStep.allCases.enumerated()), id: \.element) { idx, step in
                let complete = SubMerchantProgressLogic.isStepComplete(step, status: status)
                    || (status == .finished && step == .done)
                let current = SubMerchantProgressLogic.isStepCurrent(step, status: status)
                    || (status == .failed && idx == SubMerchantProgressLogic.currentIndex(status: .failed))
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(complete ? Color.vGreen : (current ? (status == .failed ? Color.vPrimary : Color.vGold) : Color.vFill))
                            .frame(width: 28, height: 28)
                        if complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else if status == .failed && current {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(idx + 1)")
                                .font(.vMicro)
                                .foregroundStyle(current ? .white : Color.vTextTertiary)
                        }
                    }
                    Text(step.title)
                        .font(.vMicro)
                        .foregroundStyle(current ? Color.vPrimary : Color.vTextSecondary)
                }
                .frame(maxWidth: .infinity)
                if idx < SubMerchantProgressStep.allCases.count - 1 {
                    Rectangle()
                        .fill(complete ? Color.vGreen.opacity(0.5) : Color.vSeparator)
                        .frame(height: 2)
                        .padding(.bottom, 18)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusCard(_ sm: SubMerchant) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text(sm.status.displayLabel)
                        .font(.vHeadline)
                        .foregroundStyle(sm.status == .failed ? Color.vPrimary : Color.vText)
                    Spacer()
                    if let t = sm.merchantType {
                        Text(t.displayLabel)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                }
                Text(sm.statusHint)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if let masked = sm.nameMasked, !masked.isEmpty {
                    Text("主体 \(masked)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
                if sm.status == .failed, let next = sm.resolvedFailReason?.nextStepHint {
                    Text("下一步：\(next)")
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ sm: SubMerchant) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                switch sm.status {
                case .draft, .failed:
                    VPrimaryButton(title: sm.status == .failed ? ProfitSharingCopy.resubmit : ProfitSharingCopy.submitMaterials, loading: busy) {
                        Task { await submit() }
                    }
                case .submitted, .channelReviewing:
                    Text(ProfitSharingCopy.reviewingHint)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    VPrimaryButton(title: "刷新状态", style: .outline, loading: busy) {
                        Task { await load() }
                    }
                case .toSign:
                    VPrimaryButton(title: ProfitSharingCopy.openSign, loading: busy) {
                        openChannelSign(sm)
                    }
                    VPrimaryButton(title: ProfitSharingCopy.refreshAfterSign, style: .outline, loading: busy) {
                        Task { await load() }
                    }
                case .finished:
                    VPrimaryButton(title: "完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let sm = try await API.subMerchant()
            model = sm
            if sm.status.needsChannelSign || sm.status.isInReview {
                startPoll()
            } else {
                pollTask?.cancel()
            }
        } catch let e as APIError where e.code == ProfitSharingErrorCode.kycRequired.rawValue
            || e.trustCode == .realNameRequired || e.trustCode == .stepRealNameRequired {
            errorMessage = e.message.isEmpty ? ProfitSharingErrorCode.kycRequired.fallbackMessage : e.message
            AppRouterProxy.openRealName()
        } catch let e as APIError where e.code == "not_found" || e.status == 404 {
            model = SubMerchant(status: .draft)
        } catch let e as APIError {
            errorMessage = e.message.isEmpty ? "加载失败" : e.message
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func submit() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let body = SubMerchantSubmitRequest(merchantType: model?.merchantType ?? .personal)
            model = try await API.submitSubMerchant(body)
            if model?.status.needsChannelSign == true {
                openChannelSign(model!)
            }
        } catch let e as APIError {
            if let code = ProfitSharingErrorCode(rawValue: e.code) {
                errorMessage = e.message.isEmpty ? code.fallbackMessage : e.message
                if code.opensRealName { AppRouterProxy.openRealName() }
            } else {
                errorMessage = e.message.isEmpty ? "提交失败" : e.message
            }
        } catch {
            errorMessage = "提交失败"
        }
    }

    private func openChannelSign(_ sm: SubMerchant) {
        if let url = sm.effectiveSignURL {
            if url.absoluteString == ProfitSharingConfigDefaults.channelSignStubURL {
                showSignStubAlert = true
            } else {
                openURL(url)
            }
        } else {
            showSignStubAlert = true
        }
    }

    private func openSignStub() {
        if let url = URL(string: ProfitSharingConfigDefaults.channelSignStubURL) {
            openURL(url)
        }
    }

    private func startPoll() {
        pollTask?.cancel()
        pollTask = Task {
            let deadline = Date().addingTimeInterval(120)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                do {
                    let sm = try await API.subMerchant()
                    await MainActor.run { model = sm }
                    if sm.status.isTerminal { return }
                } catch {
                    return
                }
            }
        }
    }
}

/// Publish blocked half-sheet when `sub_merchant_required` (design §9).
struct SubMerchantPublishGateSheet: View {
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: VSpace.l) {
                Text(ProfitSharingCopy.publishGateTitle)
                    .font(.vTitle(22))
                Text(ProfitSharingCopy.publishGateMessage)
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
                Spacer()
                VPrimaryButton(title: ProfitSharingCopy.publishGateCTA, action: onOpen)
                Button(action: onDismiss) {
                    Text("稍后再说")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(VSpace.l)
            .background(Color.vBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onDismiss)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
