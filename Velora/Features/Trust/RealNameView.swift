import SwiftUI

/// Real-name KYC: three-channel jump only — no in-app ID capture (DES-v1.3-01-02 §5.1 / §9).
struct RealNameView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var status: RealNameStatusResponse?
    @State private var loading = true
    @State private var launching: RealNameChannel?
    @State private var completing = false
    @State private var installPrompt: InstallPrompt?
    @State private var errorMessage: String?
    @State private var lastSessionId: String?
    @State private var lastChannel: RealNameChannel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                headerCard
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if status?.statusValue.isVerified == true {
                    verifiedCard
                } else {
                    channelButtons
                    refreshRow
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.vCaption)
                        .foregroundStyle(Color.vPrimary)
                }
                footerNote
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle("实名认证")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .kycReturn)) { note in
            guard let payload = note.object as? KYCReturnPayload else { return }
            Task { await complete(payload) }
        }
        .alert(
            "未检测到该 App",
            isPresented: Binding(
                get: { installPrompt != nil },
                set: { if !$0 { installPrompt = nil } }
            )
        ) {
            if let url = installPrompt?.url {
                Button("前往安装") { openURL(url); installPrompt = nil }
            }
            Button("换其他方式", role: .cancel) { installPrompt = nil }
        } message: {
            Text("请安装\(installPrompt?.channel.title ?? "")后返回重试。毂毂不会在 App 内拍摄证件。")
        }
    }

    private var headerCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("跳转完成实名").font(.vHeadline)
                Text("将打开对应 App 完成实名，\(AppConfig.brandDisplayName)不会拍摄你的证件，也不申请相机权限用于实名。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .lineSpacing(3)
            }
        }
    }

    private var verifiedCard: some View {
        VCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.vGreen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("已完成实名").font(.vHeadline)
                    if let name = status?.nameMasked {
                        Text(name).font(.vBody).foregroundStyle(Color.vTextSecondary)
                    }
                    if let id = status?.idNoMasked {
                        Text(id).font(.vCaption).foregroundStyle(Color.vTextTertiary)
                    }
                }
                Spacer()
            }
        }
    }

    private var channelButtons: some View {
        VStack(spacing: VSpace.m) {
            ForEach(RealNameChannel.allCases) { channel in
                Button {
                    Task { await start(channel) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: channel.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.vPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.vPrimarySoft, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.title).font(.vBodyMedium).foregroundStyle(Color.vText)
                            Text("打开\(channel.title.replacingOccurrences(of: "认证", with: ""))完成核身")
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                        Spacer()
                        if launching == channel {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.vTextTertiary)
                        }
                    }
                    .padding(14)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(launching != nil || completing)
            }

            if let fail = status?.failCode {
                Text(fail.fallbackMessage)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            } else if let reason = status?.failReason, !reason.isEmpty {
                Text(TrustErrorCode(rawValue: reason)?.fallbackMessage ?? "认证未通过，可换通道重试")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var refreshRow: some View {
        VPrimaryButton(
            title: completing ? "核验中…" : "我已完成，刷新状态",
            style: .outline,
            loading: completing,
            disabled: launching != nil
        ) {
            Task { await refreshAfterReturn() }
        }
    }

    private var footerNote: some View {
        Text("单通道失败不会自动改打其他通道；请自行另选支付宝、微信或国家网络身份认证。")
            .font(.vMicro)
            .foregroundStyle(Color.vTextTertiary)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            status = try await API.realNameStatus()
            lastSessionId = status?.sessionId
        } catch let e as APIError where e.status == 404 {
            status = nil
        } catch {
            errorMessage = (error as? APIError)?.trustMessage ?? "加载失败"
        }
    }

    private func start(_ channel: RealNameChannel) async {
        launching = channel
        lastChannel = channel
        errorMessage = nil
        defer { launching = nil }
        do {
            let sessionResp = try await API.createRealNameSession(channel: channel)
            if sessionResp.isAlreadyVerified {
                status = RealNameStatusResponse(
                    status: "verified",
                    channel: sessionResp.channel,
                    nameMasked: sessionResp.nameMasked,
                    idNoMasked: sessionResp.idNoMasked,
                    sessionId: sessionResp.sessionId
                )
                await session.refreshBootstrap()
                ToastCenter.shared.show("已完成实名", .success)
                return
            }
            lastSessionId = sessionResp.sessionId
            guard let jumpURL = sessionResp.jump?.openURL else {
                errorMessage = "未返回跳转地址，请稍后重试"
                return
            }
            if !canOpen(channel: channel, jump: jumpURL) {
                installPrompt = InstallPrompt(channel: channel, url: sessionResp.jump?.installURL ?? defaultInstallURL(channel))
                return
            }
            await MainActor.run { openURL(jumpURL) }
        } catch let e as APIError {
            if e.trustCode == .appNotInstalled {
                installPrompt = InstallPrompt(channel: channel, url: defaultInstallURL(channel))
            } else {
                errorMessage = e.trustMessage
                ToastCenter.shared.show(e.trustMessage, .error)
            }
        } catch {
            errorMessage = "发起认证失败"
        }
    }

    private func refreshAfterReturn() async {
        if let sid = lastSessionId, let pending = pendingCodeFromClipboardHint() {
            await complete(KYCReturnPayload(channel: lastChannel?.rawValue, sessionId: sid, code: pending))
            return
        }
        await load()
        if status?.statusValue.isVerified == true {
            await session.refreshBootstrap()
            ToastCenter.shared.show("实名已生效", .success)
        } else if status?.statusValue == .pendingJump || status?.statusValue == .verifying {
            ToastCenter.shared.show("认证处理中，请稍候再刷新", .info)
        } else {
            ToastCenter.shared.show("尚未收到认证结果，可返回三方 App 完成或换通道", .info)
        }
    }

    private func complete(_ payload: KYCReturnPayload) async {
        completing = true
        errorMessage = nil
        defer { completing = false }
        lastSessionId = payload.sessionId
        do {
            let result = try await API.completeRealNameSession(id: payload.sessionId, code: payload.code)
            status = result
            if result.statusValue.isVerified {
                await session.refreshBootstrap()
                Haptics.success()
                ToastCenter.shared.show("实名认证成功", .success)
            } else if let fail = result.failCode {
                errorMessage = fail.fallbackMessage
            }
        } catch let e as APIError {
            errorMessage = e.trustMessage
            ToastCenter.shared.show(e.trustMessage, .error)
            await load()
        } catch {
            errorMessage = "核验失败"
        }
    }

    private func canOpen(channel: RealNameChannel, jump: URL) -> Bool {
        if UIApplication.shared.canOpenURL(jump) { return true }
        for scheme in channel.probeSchemes {
            if let u = URL(string: "\(scheme)://"), UIApplication.shared.canOpenURL(u) { return true }
        }
        // Simulator / missing LSApplicationQueriesSchemes: still attempt openURL.
        #if targetEnvironment(simulator)
        return true
        #else
        return jump.scheme?.hasPrefix("http") == true
        #endif
    }

    private func defaultInstallURL(_ channel: RealNameChannel) -> URL? {
        switch channel {
        case .alipay: return URL(string: "https://apps.apple.com/app/id333206289")
        case .wechat: return URL(string: "https://apps.apple.com/app/id414478124")
        case .nationalNid: return URL(string: "https://www.nppa.gov.cn/")
        }
    }

    /// Deep link is preferred; clipboard is not used for secrets — stub returns nil.
    private func pendingCodeFromClipboardHint() -> String? { nil }
}

private struct InstallPrompt: Equatable {
    let channel: RealNameChannel
    let url: URL?
}
