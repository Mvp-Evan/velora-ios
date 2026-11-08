import SwiftUI

/// Brand-seller Me landing for D26: App does not export / reconcile / compare — open merchant Web.
struct PresaleMerchantRedirectView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                VCard {
                    VStack(alignment: .leading, spacing: VSpace.m) {
                        Text(PresaleSummaryCopy.useMerchantWeb)
                            .font(.vHeadline)
                            .foregroundStyle(Color.vText)
                        Text(PresaleSummaryCopy.hint)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                            .lineSpacing(3)
                    }
                }

                Button {
                    openMerchant()
                } label: {
                    HStack {
                        Text(PresaleSummaryCopy.openMerchantWeb)
                            .font(.vBodyMedium)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(VGradient.brand, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle(PresaleSummaryCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openMerchant() {
        guard let url = PresaleSummaryLogic.merchantPresaleURL(
            baseURLString: AppConfig.merchantWebBaseURL.absoluteString
        ) else {
            ToastCenter.shared.show(PresaleSummaryCopy.useMerchantWeb, .info)
            return
        }
        ToastCenter.shared.show(PresaleSummaryCopy.useMerchantWeb, .info)
        openURL(url)
    }
}
