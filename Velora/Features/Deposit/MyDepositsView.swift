import SwiftUI

/// 我的保证金列表（DES-v1.3-08-02 §6 / §9）— GET `/me/deposits`.
struct MyDepositsView: View {
    @State private var items: [Deposit] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var filter: DepositType? = nil

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty {
                VErrorView(message: errorMessage) { Task { await load() } }
            } else if items.isEmpty {
                VEmptyState(
                    icon: "lock.shield",
                    title: DepositCopy.emptyTitle,
                    message: DepositCopy.emptyHint
                )
            } else {
                list
            }
        }
        .background(Color.vBackground)
        .navigationTitle(DepositCopy.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部") { filter = nil; Task { await load() } }
                    ForEach(DepositType.allCases, id: \.self) { t in
                        Button(t.displayLabel) { filter = t; Task { await load() } }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: VSpace.m) {
                ForEach(items) { d in
                    depositRow(d)
                }
            }
            .padding(VSpace.l)
        }
    }

    private func depositRow(_ d: Deposit) -> some View {
        VCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(d.typeLabel)
                        .font(.vCaptionMedium)
                        .foregroundStyle(Color.vTextSecondary)
                    Spacer()
                    Text(d.statusLabel)
                        .font(.vCaptionMedium)
                        .foregroundStyle(statusColor(d.status))
                        .accessibilityLabel("状态 \(d.statusLabel)")
                }
                Text(d.title?.isEmpty == false ? (d.title ?? d.typeLabel) : d.typeLabel)
                    .font(.vBodyMedium)
                    .foregroundStyle(Color.vText)
                    .lineLimit(2)
                HStack {
                    Text(d.amount.display)
                        .font(.vHeadline)
                        .foregroundStyle(Color.vText)
                    Spacer()
                    Text(d.methodUserLabel)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
                if d.status.showsProcessing {
                    Text(DepositCopy.processingHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
                if d.status == .deducted || d.status == .partiallyDeducted {
                    Text(DepositCopy.deductProcessing)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
                if d.status == .released {
                    Text(DepositCopy.releaseArriveHint)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
        }
    }

    private func statusColor(_ status: DepositStatus) -> Color {
        switch status {
        case .frozen: return .vPrimary
        case .pending: return .vGold
        case .released: return .vTextSecondary
        case .deducted, .partiallyDeducted: return .vPrimary
        }
    }

    private func load() async {
        if items.isEmpty { loading = true }
        errorMessage = nil
        defer { loading = false }
        do {
            let resp = try await API.myDeposits(type: filter?.rawValue)
            items = resp.items
        } catch let e as APIError {
            errorMessage = e.message.isEmpty ? "加载失败" : e.message
        } catch {
            errorMessage = "加载失败"
        }
    }
}
