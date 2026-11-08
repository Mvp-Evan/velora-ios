import SwiftUI

/// 代拍考核：四指标、阈值、近 30 天预测（DES-v1.3-05-01 §5.5 / §9）。
struct ProxyAssessmentView: View {
    @StateObject private var model = ProxyAssessmentModel()

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VErrorView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .background(Color.vBackground)
        .navigationTitle(ProxyAgentCopy.assessmentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $model.showDowngrade) {
            if let notice = model.downgradeNotice() {
                ProxyDowngradeSheet(notice: notice) { model.showDowngrade = false }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                levelHeader
                if let latest = model.latest {
                    monthCard(latest, title: "上月考核 \(latest.yearMonth)")
                } else {
                    emptyMonth
                }
                if let forecast = model.forecast {
                    forecastCard(forecast)
                }
                thresholdsHelp
            }
            .padding(VSpace.l)
        }
    }

    private var levelHeader: some View {
        VCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.badgeLabel)
                        .font(.vHeadline)
                        .foregroundStyle(Color.vText)
                    Text("考核等级 · \(model.currentLevel.displayLabel)")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                }
                Spacer()
                NavigationLink {
                    ProxyAgentBadgeView(
                        level: model.currentLevel,
                        badgeLabel: model.badgeLabel,
                        capabilities: model.profile?.capabilities ?? .goldDefaults
                    )
                } label: {
                    Text("标识说明")
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vPrimary)
                }
            }
        }
    }

    private var emptyMonth: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("暂无月报").font(.vHeadline)
                Text("每月 1 日出具上月考核；样本不足 5 单不参与降级。")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private func monthCard(_ month: ProxyAssessmentMonth, title: String) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text(title).font(.vHeadline)
                    Spacer()
                    if let result = month.result {
                        Text(result.displayLabel)
                            .font(.vCaptionMedium)
                            .foregroundStyle(resultColor(result))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(resultColor(result).opacity(0.12), in: Capsule())
                    }
                }
                ForEach(ProxyMetricKind.allCases, id: \.rawValue) { kind in
                    metricRow(
                        kind: kind,
                        rate: month.rate(for: kind),
                        ok: month.meets(kind)
                    )
                }
                if let count = month.orderCount {
                    Text("样本 \(count) 单")
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func forecastCard(_ forecast: ProxyAssessmentForecast) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: VSpace.m) {
                HStack {
                    Text("本月预测").font(.vHeadline)
                    Spacer()
                    if forecast.showsNonFinalBanner {
                        Text(ProxyAgentCopy.forecastHint)
                            .font(.vMicro)
                            .foregroundStyle(Color.vGold)
                    }
                }
                ForEach(ProxyMetricKind.allCases, id: \.rawValue) { kind in
                    metricRow(
                        kind: kind,
                        rate: forecast.rate(for: kind),
                        ok: ProxyMetricLogic.meetsThreshold(kind: kind, rate: forecast.rate(for: kind))
                    )
                }
            }
        }
    }

    private var thresholdsHelp: some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("达标阈值").font(.vHeadline)
                ForEach(ProxyMetricKind.allCases, id: \.rawValue) { kind in
                    HStack {
                        Text(kind.title).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        Spacer()
                        Text(kind.thresholdLabel).font(.vCaptionMedium).foregroundStyle(Color.vText)
                    }
                    Text(kind.definition)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func metricRow(kind: ProxyMetricKind, rate: Double?, ok: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.vBodyMedium).foregroundStyle(Color.vText)
                Text(kind.thresholdLabel).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            }
            Spacer()
            Text(ProxyMetricLogic.formatRate(rate))
                .font(.vBodyMedium)
                .foregroundStyle(ok ? Color.vGreen : Color.vPrimary)
        }
        .padding(.vertical, 4)
    }

    private func resultColor(_ result: ProxyAssessmentResult) -> Color {
        switch result {
        case .pass: return .vGreen
        case .warn: return .vGold
        case .fail: return .vPrimary
        case .insufficientSample: return .vTextSecondary
        }
    }
}
