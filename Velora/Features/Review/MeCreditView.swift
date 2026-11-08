import SwiftUI

/// Personal credit score + month plus + 90d logs (DES-v1.3-12-02 CRD-02 / §9).
struct MeCreditView: View {
    @State private var credit: MeCreditResponse?
    @State private var state: LoadState = .idle

    var body: some View {
        ScrollView {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load() } }
            case .loaded:
                if let credit {
                    content(credit)
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(ReviewCreditCopy.creditTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func content(_ c: MeCreditResponse) -> some View {
        VStack(spacing: VSpace.l) {
            VCard {
                VStack(spacing: 8) {
                    // Integer score only — no exaggerate animation (client duty).
                    Text("\(c.score)")
                        .font(.vTitle(44))
                        .foregroundStyle(Color.vText)
                        .monospacedDigit()
                    Text(ReviewCreditCopy.creditTitle)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                    Text(ReviewCreditLogic.monthPlusCaption(used: c.monthPlusUsed, cap: c.monthPlusCap))
                        .font(.vCaptionMedium)
                        .foregroundStyle(c.isMonthPlusExhausted ? Color.vGold : Color.vTextSecondary)
                    if c.isMonthPlusExhausted {
                        Text(ReviewCreditCopy.monthCapReached)
                            .font(.vMicro)
                            .foregroundStyle(Color.vGold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, VSpace.s)
            }

            VCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ReviewCreditCopy.thresholdsTitle).font(.vHeadline)
                    thresholdRow(ReviewCreditCopy.threshold80Hint, active: c.score < c.thresholds.th80)
                    thresholdRow(ReviewCreditCopy.threshold60Hint, active: c.score < c.thresholds.th60)
                    thresholdRow(ReviewCreditCopy.threshold40Hint, active: c.score < c.thresholds.th40)
                    Text("\(ReviewCreditCopy.nextStepFulfill)，\(ReviewCreditCopy.nextStepSupport)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }

            VCard {
                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text(ReviewCreditCopy.logsTitle).font(.vHeadline)
                    if c.logs.isEmpty {
                        Text(ReviewCreditCopy.logsEmpty)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextTertiary)
                    } else {
                        ForEach(c.logs) { log in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(log.displayTitle)
                                        .font(.vBodyMedium)
                                        .foregroundStyle(Color.vText)
                                    if let at = log.eventAt {
                                        Text(at.relativeText)
                                            .font(.vMicro)
                                            .foregroundStyle(Color.vTextTertiary)
                                    }
                                }
                                Spacer()
                                Text(log.deltaDisplay)
                                    .font(.vBodyMedium)
                                    .foregroundStyle(
                                        log.delta == 0
                                            ? Color.vTextTertiary
                                            : (log.delta > 0 ? Color.vGreen : Color.vPrimary)
                                    )
                                    .monospacedDigit()
                            }
                            if log.id != c.logs.last?.id {
                                Rectangle().fill(Color.vSeparator).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
        .padding(VSpace.l)
    }

    private func thresholdRow(_ text: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(active ? Color.vPrimary : Color.vGreen)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            Text(text)
                .font(.vCaption)
                .foregroundStyle(active ? Color.vPrimary : Color.vTextSecondary)
        }
    }

    private func load() async {
        state = credit == nil ? .loading : state
        do {
            credit = try await API.meCredit()
            state = .loaded
        } catch let e as APIError where e.status == 404 {
            // Soft fallback until server ships endpoint.
            let score = SessionStore.shared.bootstrap?.me?.creditScore
                ?? SessionStore.shared.user?.creditScore
                ?? ReviewCreditConfigDefaults.creditInitial
            credit = MeCreditResponse(score: score)
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }
}
