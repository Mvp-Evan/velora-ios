import SwiftUI

/// Session risk strips for IM filter (DES-v1.3-10-01 §5.12 / §9 / N-24).
struct IMRiskBannerView: View {
    let banner: IMRiskBanner
    var onOfferCTA: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(banner.text)
                    .font(.vCaption)
                    .foregroundStyle(foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if banner.showsOfferCTA, let onOfferCTA {
                    Button(action: onOfferCTA) {
                        Text(IMRiskCopy.blockedCTA)
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, VSpace.l)
        .padding(.vertical, 10)
        .background(background)
        .accessibilityLabel(banner.accessibilityLabel)
        .accessibilityValue(banner.text)
    }

    private var iconName: String {
        switch banner.kind {
        case .intercept: return "exclamationmark.octagon.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .mute: return "mic.slash.fill"
        }
    }

    private var foreground: Color {
        switch banner.kind {
        case .intercept, .mute: return Color.vPrimary
        case .warn: return Color(hex: 0x8A5A00)
        }
    }

    private var background: Color {
        switch banner.kind {
        case .intercept, .mute: return Color.vPrimarySoft
        case .warn: return Color(hex: 0xFFF6E5)
        }
    }
}

/// Phase 3 RISK-03 stub — flag default off (design §5.6).
enum IMRiskImageScanPlaceholder {
    static var result: RiskImageScanResult {
        IMRiskLogic.imageScanPlaceholder(enabled: IMRiskConfigDefaults.imageScanEnabledDefault)
    }

    @MainActor
    static func presentDisabledToast() {
        ToastCenter.shared.show(IMRiskCopy.imageScanFeatureDisabled, .info)
    }
}
