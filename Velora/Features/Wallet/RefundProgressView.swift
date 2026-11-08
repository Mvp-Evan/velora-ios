import SwiftUI

/// 买家退款两阶段进度：回退中 / 退款中 / 到账（DES-v1.3-08-03 §5.8 / §9）。
struct RefundProgressView: View {
    let progress: RefundProgress

    var body: some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text(progress.headline).font(.vHeadline)
                    Spacer()
                    Text(progress.amount.display)
                        .font(.vMono(15))
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                }
                if progress.isPartial == true {
                    Text(OrderCenterCopy.partialRefundBadge)
                        .font(.vMicro)
                        .foregroundStyle(Color.vGold)
                }
                progressStrip
                Text(progress.status.displayLabel)
                    .font(.vCaption)
                    .foregroundStyle(statusColor)
                    .accessibilityLabel("退款状态 \(progress.status.displayLabel)")
                if let reason = progress.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var progressStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(RefundProgressStep.allCases.enumerated()), id: \.element) { idx, step in
                let complete = RefundProgressLogic.isStepComplete(
                    step,
                    status: progress.status,
                    needsShareReturn: progress.needsShareReturn
                )
                let current = RefundProgressLogic.isStepCurrent(
                    step,
                    status: progress.status,
                    needsShareReturn: progress.needsShareReturn
                )
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(complete ? Color.vGreen : (current ? stepCurrentFill : Color.vFill))
                            .frame(width: 28, height: 28)
                        if complete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        } else if progress.status == .refundFailed && current {
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
                        .foregroundStyle(current || complete ? Color.vText : Color.vTextTertiary)
                }
                .frame(maxWidth: .infinity)
                if idx < RefundProgressStep.allCases.count - 1 {
                    Rectangle()
                        .fill(complete ? Color.vGreen.opacity(0.5) : Color.vSeparator)
                        .frame(height: 2)
                        .padding(.bottom, 18)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("退款进度 \(progress.headline)")
    }

    private var stepCurrentFill: Color {
        progress.status == .refundFailed ? Color.vPrimary : Color.vGold
    }

    private var statusColor: Color {
        switch progress.status {
        case .succeeded: return .vGreen
        case .refundFailed: return .vPrimary
        case .created, .waitingShareReturn, .blockedWaitingShare, .refunding: return .vGold
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        RefundProgressView(
            progress: RefundProgress(
                id: 1,
                orderId: 9,
                amount: 10_000,
                status: .waitingShareReturn,
                isPartial: true,
                shareReturnId: 3
            )
        )
        RefundProgressView(
            progress: RefundProgress(
                id: 2,
                amount: 25_000,
                status: .succeeded
            )
        )
    }
    .padding()
    .background(Color.vBackground)
}
#endif
