import SwiftUI

/// B-side seller application with dual progress: 资质审核 + 收款开通 (DES-v1.3-01-02 §5.4 / §9).
struct MerchantApplicationView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var application: MerchantApplicationResponse?
    @State private var inviteCode = ""
    @State private var applyType = "proxy_agent"
    @State private var loading = true
    @State private var submitting = false
    @State private var errorMessage: String?
    @State private var showRealName = false

    private let types: [(String, String)] = [
        ("proxy_agent", "金牌代拍"),
        ("brand", "品牌官方")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                intro
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 24)
                } else if let application, application.id != nil || application.reviewStatus != nil {
                    dualProgress(application)
                } else {
                    applyForm
                }
                if let errorMessage {
                    Text(errorMessage).font(.vCaption).foregroundStyle(Color.vPrimary)
                }
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle("商家入驻")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .navigationDestination(isPresented: $showRealName) {
            RealNameView()
        }
    }

    private var intro: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("代拍 / 品牌入驻").font(.vHeadline)
                Text("需有效卖家邀请码与实名。资质审核与收款进件并行推进，两侧都成功后才算开通完成。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private var applyForm: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("提交申请").font(.vHeadline)
                Picker("身份", selection: $applyType) {
                    ForEach(types, id: \.0) { t in
                        Text(t.1).tag(t.0)
                    }
                }
                .pickerStyle(.segmented)

                TextField("邀请码", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))

                Text("邀请码忽略大小写与空格；过期或不匹配时提示「邀请码无效或已过期」。")
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)

                Text("资质材料上传将在下一迭代完善；当前先提交邀请码占位申请。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)

                VPrimaryButton(title: "提交申请", loading: submitting, disabled: normalizedInvite.isEmpty) {
                    Task { await submit() }
                }
            }
        }
    }

    private func dualProgress(_ app: MerchantApplicationResponse) -> some View {
        VStack(spacing: VSpace.m) {
            if app.isFinished {
                VCard {
                    Label("入驻完成", systemImage: "checkmark.seal.fill")
                        .font(.vHeadline)
                        .foregroundStyle(Color.vGreen)
                }
            }

            // DES-v1.3-05-01 §9: 资料 / 保证金 / 审核 / 进件
            if app.applyType == ProxyAgentConfigDefaults.sellerType || applyType == ProxyAgentConfigDefaults.sellerType {
                proxyOnboardingStrip(app)
            }

            VCard {
                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text("进度").font(.vHeadline)
                    progressRow(
                        title: "资质审核",
                        subtitle: typeLabel(app.applyType),
                        status: app.reviewLabel,
                        tint: tint(for: app.reviewStatus ?? app.status)
                    )
                    VDivider()
                    progressRow(
                        title: "收款开通",
                        subtitle: "二级商户进件",
                        status: app.subMerchantLabel,
                        tint: tint(for: app.subMerchantStatus)
                    )
                    if let reason = app.rejectReason, !reason.isEmpty {
                        Text(reason)
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                            .padding(.top, 4)
                    }
                }
            }

            if let urlStr = app.signUrl, let url = URL(string: urlStr) {
                VPrimaryButton(title: "打开签约页") { openURL(url) }
            }

            VPrimaryButton(title: "刷新进度", style: .outline, loading: loading) {
                Task { await load() }
            }

            if app.subMerchantStatus == "failed" || app.reviewStatus == "rejected" {
                Text(app.reviewStatus == "rejected"
                     ? "审核驳回后请按原因补材料；进件成功也不会启用商户号。"
                     : "进件失败时可重提进件，无需重新审核资质（资料未变更时）。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private func proxyOnboardingStrip(_ app: MerchantApplicationResponse) -> some View {
        let idx = ProxyOnboardingProgress.currentIndex(
            reviewStatus: app.reviewStatus ?? app.status,
            subMerchantStatus: app.subMerchantStatus,
            depositDone: true
        )
        return VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("入驻进度").font(.vHeadline)
                HStack(spacing: 0) {
                    ForEach(Array(ProxyOnboardingProgress.stepTitles.enumerated()), id: \.offset) { i, title in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(i <= idx ? Color.vPrimary : Color.vFillStrong)
                                .frame(width: 10, height: 10)
                            Text(title)
                                .font(.vMicro)
                                .foregroundStyle(i <= idx ? Color.vText : Color.vTextTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        if i < ProxyOnboardingProgress.stepTitles.count - 1 {
                            Rectangle()
                                .fill(i < idx ? Color.vPrimary.opacity(0.5) : Color.vFillStrong)
                                .frame(height: 2)
                                .padding(.bottom, 18)
                        }
                    }
                }
            }
        }
    }

    private func progressRow(title: String, subtitle: String, status: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Circle().fill(tint.opacity(0.15)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.vBodyMedium)
                Text(subtitle).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
            Spacer()
            Text(status)
                .font(.vCaptionMedium)
                .foregroundStyle(tint)
        }
    }

    private var normalizedInvite: String {
        inviteCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    private func typeLabel(_ raw: String?) -> String {
        types.first { $0.0 == raw }?.1 ?? (raw ?? "申请")
    }

    private func tint(for status: String?) -> Color {
        switch status {
        case "approved", "passed", "finished", "succeeded", "active": return .vGreen
        case "rejected", "failed": return .vPrimary
        case "submitted", "pending", "reviewing", "applying", "processing", "to_sign", "pending_sign": return .vGold
        default: return .vTextSecondary
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            application = try await API.myMerchantApplication()
            if application?.isFinished == true {
                await session.refreshBootstrap()
            }
        } catch let e as APIError where e.status == 404 {
            application = nil
        } catch let e as APIError {
            errorMessage = e.trustMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        let code = normalizedInvite
        guard !code.isEmpty else { return }
        do {
            application = try await API.createMerchantApplication(inviteCode: code, applyType: applyType)
            ToastCenter.shared.show("申请已提交", .success)
        } catch let e as APIError {
            errorMessage = e.trustMessage
            if e.trustCode == .stepRealNameRequired || e.trustCode == .realNameRequired {
                showRealName = true
            }
            ToastCenter.shared.show(e.trustMessage, .error)
        } catch {
            errorMessage = "提交失败"
        }
    }
}
