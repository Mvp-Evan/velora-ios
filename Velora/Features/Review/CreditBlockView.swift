import SwiftUI

/// Credit threshold interstitial — score / threshold / next steps (design §5.8 / §9).
/// Branch only by `error.code` (`credit_below_80|60|40`), never by Chinese copy.
struct CreditBlockView: View {
    let info: CreditBlockInfo
    var onDismiss: () -> Void = {}
    var onOpenCredit: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: VSpace.l) {
                Spacer(minLength: 24)
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.vPrimary)
                Text(info.title)
                    .font(.vTitle(22))
                    .foregroundStyle(Color.vText)
                Text(info.message)
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VSpace.l)

                VCard {
                    VStack(spacing: 10) {
                        metric("当前信用分", info.score.map(String.init) ?? ReviewCreditConfigDefaults.metricEmpty)
                        metric("触发阈值", "\(info.threshold)")
                        metric("错误码", info.code.rawValue)
                    }
                }
                .padding(.horizontal, VSpace.l)

                Text("\(ReviewCreditCopy.nextStepFulfill)，\(ReviewCreditCopy.nextStepSupport)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, VSpace.l)

                Spacer()

                VStack(spacing: 10) {
                    VPrimaryButton(title: ReviewCreditCopy.creditTitle) {
                        onOpenCredit()
                        onDismiss()
                    }
                    Button("知道了") { onDismiss() }
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vTextSecondary)
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { onDismiss() }
                }
            }
        }
    }

    private func metric(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.vCaption).foregroundStyle(Color.vTextSecondary)
            Spacer()
            Text(v).font(.vBodyMedium).foregroundStyle(Color.vText).monospacedDigit()
        }
    }
}
