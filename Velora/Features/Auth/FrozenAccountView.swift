import SwiftUI

/// Full-screen account gate after `account_frozen` / WS `session_revoked` (DES-v1.3-01-03 §9).
struct FrozenAccountView: View {
    let notice: AccountGateNotice
    var onDismiss: () -> Void
    var onLogin: (() -> Void)?

    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()
            VGradient.brand.frame(height: 280).ignoresSafeArea()
                .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom))

            VStack(spacing: 0) {
                Spacer(minLength: 48)

                VStack(spacing: VSpace.l) {
                    Image(systemName: notice.kind == .frozen ? "lock.shield.fill" : "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    Text(notice.title)
                        .font(.vLargeTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.vBody)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, VSpace.xl)
                }

                VCard(padding: VSpace.xl, radius: VRadius.xl) {
                    VStack(alignment: .leading, spacing: VSpace.l) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("说明").font(.vHeadline).foregroundStyle(Color.vText)
                            Text(notice.detailText)
                                .font(.vBody)
                                .foregroundStyle(Color.vTextSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("申诉").font(.vHeadline).foregroundStyle(Color.vText)
                            Text("如需了解处理进度或提出申诉，请通过应用内客服或邮件联系平台，勿相信私下解冻渠道。")
                                .font(.vCaption)
                                .foregroundStyle(Color.vTextSecondary)
                                .lineSpacing(3)
                        }

                        VPrimaryButton(title: notice.kind == .frozen ? "我知道了" : "重新登录", action: {
                            onDismiss()
                            if notice.kind == .sessionRevoked {
                                onLogin?()
                            }
                        })
                    }
                }
                .padding(.horizontal, VSpace.l)
                .padding(.top, VSpace.xl)
                .vFloatingShadow()

                Spacer()
            }
        }
    }

    private var subtitle: String {
        switch notice.kind {
        case .frozen:
            return "账号已被限制登录与交易操作"
        case .sessionRevoked:
            return "当前设备登录态已失效，请重新登录"
        }
    }
}
