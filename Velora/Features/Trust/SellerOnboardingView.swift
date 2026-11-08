import SwiftUI

/// Personal seller 4-step funnel: real_name → protocol → deposit → sub_merchant (DES-v1.3-01-02 §5.2).
struct SellerOnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var model: SellerOnboardingResponse?
    @State private var loading = true
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showRealName = false
    @State private var protocolScrolled = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                intro
                stepStrip
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if model?.isFinished == true {
                    finishedCard
                } else if let key = model?.currentStepKey {
                    stepDetail(key)
                } else {
                    VEmptyState(
                        icon: "storefront",
                        title: "准备入驻",
                        message: "点击下方开始开通个人卖家",
                        actionTitle: "开始开通"
                    ) { Task { await start() } }
                }
                if let errorMessage {
                    Text(errorMessage).font(.vCaption).foregroundStyle(Color.vPrimary)
                }
                NavigationLink {
                    MerchantApplicationView()
                } label: {
                    HStack {
                        Image(systemName: "building.2")
                        Text("代拍 / 品牌入驻（邀请码）")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .padding(.top, 8)
                }
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle("开通卖家")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(startIfNeeded: true) }
        .refreshable { await load(startIfNeeded: false) }
        .onDisappear { pollTask?.cancel() }
        .navigationDestination(isPresented: $showRealName) {
            RealNameView()
        }
    }

    private var intro: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("个人卖家开通").font(.vHeadline)
                Text("按顺序完成实名、协议、保证金与收款进件后即可发布。中途可回看已完成步骤。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var stepStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(SellerOnboardingStepKey.allCases.enumerated()), id: \.element.id) { idx, key in
                let st = model?.step(key)?.statusValue ?? .pending
                let current = model?.currentStepKey == key
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(st.isComplete ? Color.vGreen : (current ? Color.vPrimary : Color.vFill))
                            .frame(width: 28, height: 28)
                        if st.isComplete {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        } else if st == .failed {
                            Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(idx + 1)").font(.vMicro).foregroundStyle(current ? .white : Color.vTextTertiary)
                        }
                    }
                    Text(key.title)
                        .font(.vMicro)
                        .foregroundStyle(current ? Color.vPrimary : Color.vTextSecondary)
                }
                .frame(maxWidth: .infinity)
                if idx < SellerOnboardingStepKey.allCases.count - 1 {
                    Rectangle()
                        .fill(st.isComplete ? Color.vGreen.opacity(0.5) : Color.vSeparator)
                        .frame(height: 2)
                        .padding(.bottom, 18)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var finishedCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("入驻完成", systemImage: "checkmark.seal.fill")
                    .font(.vHeadline)
                    .foregroundStyle(Color.vGreen)
                Text("已开通个人卖家，可发布直购与拍卖。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    @ViewBuilder
    private func stepDetail(_ key: SellerOnboardingStepKey) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text(key.detail).font(.vHeadline)
                if let err = model?.step(key)?.trustError {
                    Text(err.fallbackMessage).font(.vCaption).foregroundStyle(Color.vPrimary)
                }
                switch key {
                case .realName:
                    Text("需先完成实名认证。").font(.vCaption).foregroundStyle(Color.vTextSecondary)
                    VPrimaryButton(title: "去实名", loading: busy) { showRealName = true }
                case .protocolStep:
                    protocolBlock
                case .deposit:
                    depositBlock
                case .subMerchant:
                    subMerchantBlock
                }
            }
        }
    }

    private var protocolBlock: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            let code = model?.protocolCode ?? model?.protocolInfo?.protocolCode ?? "seller_service"
            let version = model?.protocolVersion ?? model?.protocolInfo?.protocolVersion ?? "—"
            Text("《卖家服务协议》 \(code) · v\(version)")
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            ScrollView {
                Text(model?.protocolInfo?.contentMarkdown ?? defaultProtocolBody)
                    .font(.vCaption)
                    .foregroundStyle(Color.vText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ProtocolScrollKey.self, value: geo.size.height)
                        }
                    )
            }
            .frame(maxHeight: 220)
            .padding(10)
            .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            .onPreferenceChange(ProtocolScrollKey.self) { _ in protocolScrolled = true }

            Toggle("我已阅读并同意协议", isOn: $protocolScrolled)
                .font(.vCaption)

            VPrimaryButton(title: "确认签署", loading: busy, disabled: !protocolScrolled) {
                Task { await signProtocol() }
            }
        }
    }

    private var depositBlock: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            Text("个人卖家默认保证金 500 元（以服务端配置为准）。冻结成功后进入下一步。")
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            if let ds = model?.depositStatus {
                Text("保证金状态：\(ds)")
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
            }
            VPrimaryButton(title: busy ? "处理中…" : DepositCopy.freezeVerb, loading: busy) {
                Task { await freezeDeposit() }
            }
        }
    }

    private var subMerchantBlock: some View {
        VStack(alignment: .leading, spacing: VSpace.m) {
            Text("开通收款账户。查看进件进度、渠道签约与失败原因。")
                .font(.vCaption)
                .foregroundStyle(Color.vTextSecondary)
            if let raw = model?.subMerchantStatus,
               let st = SubMerchantStatus.normalize(raw) {
                Text("当前：\(st.displayLabel)")
                    .font(.vCaptionMedium)
                    .foregroundStyle(Color.vTextSecondary)
            }
            NavigationLink {
                SubMerchantProgressView()
            } label: {
                Text(ProfitSharingCopy.progressTitle)
                    .font(.vHeadline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.vPrimary, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
            }
            .buttonStyle(.plain)
            if let urlStr = model?.signUrl, let url = URL(string: urlStr) {
                VPrimaryButton(title: ProfitSharingCopy.openSign, style: .outline) { openURL(url) }
            }
            VPrimaryButton(title: ProfitSharingCopy.refreshAfterSign, style: .outline, loading: busy) {
                Task { await load(startIfNeeded: false) }
            }
            VPrimaryButton(title: "继续进件", loading: busy) {
                Task { await continueSubMerchant() }
            }
        }
    }

    // MARK: - Networking

    private func load(startIfNeeded: Bool) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            var resp = try await API.sellerOnboarding()
            if startIfNeeded, resp.steps.isEmpty || resp.onboardingStatus == nil || resp.onboardingStatus == "none" {
                resp = try await API.sellerAction(action: "start")
            }
            model = resp
            if resp.step(.deposit)?.statusValue == .pending || resp.depositStatus == "pending" || resp.depositStatus == "deposit_pending" {
                startDepositPoll()
            }
            if resp.isFinished {
                await session.refreshBootstrap()
            }
        } catch let e as APIError where e.trustCode == .stepRealNameRequired || e.trustCode == .realNameRequired {
            model = nil
            errorMessage = e.trustMessage
            showRealName = true
        } catch let e as APIError {
            errorMessage = e.trustMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func start() async {
        busy = true
        defer { busy = false }
        do {
            model = try await API.sellerAction(action: "start")
        } catch let e as APIError {
            errorMessage = e.trustMessage
            if e.trustCode == .stepRealNameRequired || e.trustCode == .realNameRequired {
                showRealName = true
            }
        } catch {
            errorMessage = "无法开始入驻"
        }
    }

    private func signProtocol() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        let code = model?.protocolCode ?? "seller_service"
        let version = model?.protocolVersion ?? "1"
        do {
            model = try await API.sellerAction(action: "sign", protocolCode: code, protocolVersion: version, scrollEnd: protocolScrolled)
        } catch let e as APIError {
            errorMessage = e.trustMessage
        } catch {
            errorMessage = "签署失败"
        }
    }

    private func freezeDeposit() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let dep = try await API.freezeSellerDeposit()
            if dep.isFrozen {
                await load(startIfNeeded: false)
            } else {
                startDepositPoll()
                ToastCenter.shared.show("保证金处理中", .info)
            }
        } catch let e as APIError {
            errorMessage = e.trustMessage
        } catch {
            errorMessage = "保证金发起失败"
        }
    }

    private func continueSubMerchant() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            // Idempotent POST returns current step; server advances sub_merchant when ready.
            model = try await API.sellerAction(action: "start")
            if let urlStr = model?.signUrl, let url = URL(string: urlStr) {
                openURL(url)
            }
        } catch let e as APIError {
            errorMessage = e.trustMessage
        } catch {
            errorMessage = "进件失败"
        }
    }

    private func startDepositPoll() {
        pollTask?.cancel()
        pollTask = Task {
            let deadline = Date().addingTimeInterval(120)
            while !Task.isCancelled, Date() < deadline {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                do {
                    let resp = try await API.sellerOnboarding()
                    await MainActor.run { model = resp }
                    if resp.step(.deposit)?.statusValue.isComplete == true || resp.depositStatus == "frozen" {
                        return
                    }
                } catch {
                    return
                }
            }
        }
    }

    private var defaultProtocolBody: String {
        """
        卖家服务协议（摘要）

        一、卖家应如实描述拍品成色与附件，遵守平台规则。
        二、保证金用于履约担保；被扣后须补足后方可继续开通状态。
        三、平台服务费以订单快照为准；税务义务由卖家依法履行。
        四、签署即表示已阅读全文（完整文本以服务端下发版本与 content_hash 为准）。
        """
    }
}

private struct ProtocolScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
