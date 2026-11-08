import SwiftUI

/// Buyer/seller ruling result page (DES-v1.3-09-02 §5.5 / §9).
struct ArbitrationRulingView: View {
    let arbitration: Arbitration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                header
                if arbitration.showsAdverseBanner {
                    adverseBanner
                } else if arbitration.adverseInferenceOverridden == true {
                    Text(AfterSaleCopy.adverseInferenceOverridden)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                reasonCard
                penaltiesCard
                Text(AfterSaleCopy.noBuyerVideoPresumption)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(VSpace.xl)
        }
        .background(Color.vBackground)
        .navigationTitle(AfterSaleCopy.rulingTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(arbitration.templateLabel ?? arbitration.statusLabel)
                        .font(.vTitle(22))
                        .foregroundStyle(Color.vText)
                        .accessibilityLabel("裁定 \(arbitration.templateLabel ?? arbitration.statusLabel)")
                    Spacer()
                    if arbitration.final {
                        Text(AfterSaleCopy.finalBadge)
                            .font(.vMicro)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.vGreen, in: Capsule())
                    }
                }
                Text(arbitration.statusLabel)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
                if let decided = arbitration.decidedAt {
                    Text(decided.fullText)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private var adverseBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.vPrimary)
            Text(AfterSaleCopy.adverseInferenceBanner)
                .font(.vCaption)
                .foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        .accessibilityLabel(AfterSaleCopy.adverseInferenceShort)
    }

    private var reasonCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(AfterSaleCopy.rulingReasonLabel).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                Text(arbitration.rulingReason ?? "—")
                    .font(.vBody)
                    .foregroundStyle(Color.vText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var penaltiesCard: some View {
        VCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(AfterSaleCopy.penaltiesLabel).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                if let items = arbitration.penalties, !items.isEmpty {
                    ForEach(items) { item in
                        HStack {
                            Text(item.displayLabel).font(.vBody)
                            Spacer()
                            Text(item.status.displayLabel)
                                .font(.vCaption)
                                .foregroundStyle(statusColor(item.status))
                        }
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextTertiary)
                        }
                    }
                } else {
                    Text("暂无处罚条目")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func statusColor(_ s: PenaltyExecutionStatus) -> Color {
        switch s {
        case .succeeded: return .vGreen
        case .failed: return .vPrimary
        case .skipped: return .vTextTertiary
        case .pending: return .vGold
        }
    }
}
