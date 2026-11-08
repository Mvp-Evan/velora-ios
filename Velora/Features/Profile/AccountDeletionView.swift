import SwiftUI

/// Account deletion request + 15-day cool-off messaging (DES-v1.3-01 ACC-07).
struct AccountDeletionView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var precheck: DeletionPrecheckResponse?
    @State private var status: DeletionStatusResponse?
    @State private var confirmText = ""
    @State private var loading = true
    @State private var submitting = false
    @State private var cancelling = false
    @State private var errorMessage: String?

    private let confirmWord = "注销"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.l) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if let status, status.isPending {
                        pendingCard(status)
                    } else {
                        disclosure
                        if let blockers = precheck?.blockers, !blockers.isEmpty {
                            blockersCard(blockers)
                        } else {
                            confirmCard
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.vCaption).foregroundStyle(Color.vPrimary)
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("注销账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var disclosure: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("注销须知").font(.vHeadline)
                Text("提交后进入约 15 天冷静期。期间可登录并取消注销；到期后手机号释放，昵称与头像匿名，订单等法定账本按法规保留。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                    .lineSpacing(4)
            }
        }
    }

    private func blockersCard(_ blockers: [DeletionBlocker]) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("暂时无法注销").font(.vHeadline)
                Text("请先处理以下事项后再试：")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                ForEach(blockers) { b in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(Color.vPrimary)
                        Text(b.message)
                            .font(.vBody)
                            .foregroundStyle(Color.vText)
                    }
                }
            }
        }
    }

    private var confirmCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("二次确认").font(.vHeadline)
                Text("请输入「\(confirmWord)」以确认注销申请")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                TextField(confirmWord, text: $confirmText)
                    .padding(12)
                    .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if submitting { ProgressView().tint(.white) }
                        Text("申请注销")
                            .font(.vBodyMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(
                        confirmText == confirmWord && !submitting ? Color.vPrimary : Color.vTextTertiary,
                        in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                    )
                }
                .disabled(confirmText != confirmWord || submitting)
                .buttonStyle(.plain)
            }
        }
    }

    private func pendingCard(_ status: DeletionStatusResponse) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                Text("注销冷静期中").font(.vHeadline)
                if let at = status.executeAt {
                    Text("账号将于 \(at.fullText) 完成注销。此前可随时取消。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .lineSpacing(4)
                } else {
                    Text("账号已进入约 15 天冷静期，到期后将匿名化处理。此前可随时取消。")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .lineSpacing(4)
                }
                Button {
                    Task { await cancel() }
                } label: {
                    HStack {
                        if cancelling { ProgressView() }
                        Text("取消注销")
                            .font(.vBodyMedium)
                    }
                    .foregroundStyle(Color.vPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Color.vPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }
                .disabled(cancelling)
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        if let s = try? await API.deletionStatus(), s.isPending {
            status = s
            return
        }
        status = nil
        do {
            precheck = try await API.deletionPrecheck()
        } catch let e as APIError where e.status == 404 {
            // Precheck not shipped yet — allow confirm path; server will enforce on POST.
            precheck = nil
        } catch {
            errorMessage = (error as? APIError)?.message ?? "加载失败"
        }
    }

    private func submit() async {
        submitting = true
        errorMessage = nil
        defer { submitting = false }
        do {
            let result = try await API.requestDeletion(confirm: confirmWord)
            status = result
            session.noteDeletion(AuthDeletionHint(status: result.status, executeAt: result.executeAt))
            ToastCenter.shared.show("已进入注销冷静期", .success)
        } catch let e as APIError where e.authCode == .deletionBlocked {
            errorMessage = e.message
            if let refreshed = try? await API.deletionPrecheck() {
                precheck = refreshed
            }
        } catch let e as APIError where e.status == 404 {
            errorMessage = "注销接口即将开放，请稍后再试"
        } catch {
            errorMessage = (error as? APIError)?.message ?? "提交失败"
        }
    }

    private func cancel() async {
        cancelling = true
        errorMessage = nil
        defer { cancelling = false }
        do {
            try await session.cancelAccountDeletion()
            status = nil
            ToastCenter.shared.show("已取消注销", .success)
            dismiss()
        } catch let e as APIError where e.status == 404 {
            errorMessage = "当前没有进行中的注销申请"
        } catch {
            errorMessage = (error as? APIError)?.message ?? "取消失败"
        }
    }
}
