import SwiftUI

/// Seller CRD-03 metrics: good_rate / sold_count / avg_ship_hours / after_sale_rate.
/// Empty or no-sales → 「—」; stale snapshot shows soft hint (design §5.4 / §9 / §11).
struct SellerCardMetricsView: View {
    let metrics: SellerCardMetrics
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Text(ReviewCreditCopy.sellerMetricsTitle)
                    .font(compact ? .vCaptionMedium : .vHeadline)
                Text(ReviewCreditCopy.sellerWindowHint)
                    .font(.vMicro)
                    .foregroundStyle(Color.vTextTertiary)
                Spacer()
                if metrics.stale {
                    Text(ReviewCreditCopy.sellerStaleHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vGold)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                cell(ReviewCreditCopy.sellerGoodRate, metrics.goodRateDisplay)
                cell(ReviewCreditCopy.sellerSoldCount, metrics.soldCountDisplay)
                cell(ReviewCreditCopy.sellerAvgShip, metrics.avgShipHoursDisplay)
                cell(ReviewCreditCopy.sellerAfterSale, metrics.afterSaleRateDisplay)
            }
            if let score = metrics.score {
                Text("信用 \(score)")
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextSecondary)
            }
        }
    }

    private func cell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.vMicro).foregroundStyle(Color.vTextTertiary)
            Text(value)
                .font(.vBodyMedium)
                .foregroundStyle(Color.vText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.vFill, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}

/// Loads `GET /users/{id}/seller-card` and renders metrics (or dashes on failure/empty).
struct SellerCardMetricsLoader: View {
    let userId: Int64
    @State private var metrics: SellerCardMetrics?
    @State private var failed = false

    var body: some View {
        Group {
            if let metrics {
                SellerCardMetricsView(metrics: metrics, compact: true)
            } else if failed {
                SellerCardMetricsView(metrics: SellerCardMetrics(userId: userId, soldCount: 0), compact: true)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task(id: userId) { await load() }
    }

    private func load() async {
        do {
            metrics = try await API.sellerCard(userId: userId)
            failed = false
        } catch {
            // Soft degrade — show empty dashes rather than hard fail on listing cards.
            metrics = SellerCardMetrics(userId: userId, soldCount: 0, stale: true)
            failed = true
        }
    }
}
