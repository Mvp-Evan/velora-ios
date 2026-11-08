import SwiftUI

/// Blocked users list + unblock (DES-v1.3-10-02 RISK-07 / §9).
struct BlockListView: View {
    @State private var items: [UserBlock] = []
    @State private var state: LoadState = .idle
    @State private var nextCursor: String?
    @State private var loadingMore = false
    @State private var pendingUnblock: UserBlock?

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load(reset: true) } }
            case .loaded:
                if items.isEmpty {
                    VEmptyState(icon: "hand.raised", title: RiskCopy.blockListEmpty)
                } else {
                    ScrollView {
                        LazyVStack(spacing: VSpace.m) {
                            ForEach(items) { block in
                                row(block)
                                    .onAppear {
                                        if block.id == items.last?.id, nextCursor != nil {
                                            Task { await loadMore() }
                                        }
                                    }
                            }
                            if loadingMore {
                                ProgressView().padding(.vertical, 8)
                            }
                        }
                        .padding(VSpace.l)
                    }
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(RiskCopy.blockListTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if items.isEmpty { await load(reset: true) } }
        .refreshable { await load(reset: true) }
        .confirmationDialog(
            RiskCopy.unblockAction,
            isPresented: Binding(
                get: { pendingUnblock != nil },
                set: { if !$0 { pendingUnblock = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(RiskCopy.unblockAction, role: .destructive) {
                if let b = pendingUnblock {
                    Task { await unblock(b) }
                }
            }
            Button("取消", role: .cancel) { pendingUnblock = nil }
        }
    }

    private func row(_ block: UserBlock) -> some View {
        VCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.blockedUser?.displayName ?? "用户\(block.blockedId % 10_000)")
                        .font(.vHeadline)
                        .foregroundStyle(Color.vText)
                    if let at = block.createdAt {
                        Text(at.relativeText)
                            .font(.vMicro)
                            .foregroundStyle(Color.vTextTertiary)
                    }
                }
                Spacer()
                Button(RiskCopy.unblockAction) {
                    pendingUnblock = block
                }
                .font(.vCaptionMedium)
                .foregroundStyle(Color.vPrimary)
            }
        }
    }

    private func load(reset: Bool) async {
        if reset {
            if items.isEmpty { state = .loading }
            nextCursor = nil
        }
        do {
            let page = try await API.myBlocks(cursor: reset ? nil : nextCursor)
            if reset {
                items = page.items
            } else {
                let existing = Set(items.map(\.blockedId))
                items.append(contentsOf: page.items.filter { !existing.contains($0.blockedId) })
            }
            nextCursor = page.nextCursor
            state = .loaded
        } catch {
            state = .failed((error as? APIError)?.message ?? "加载失败")
        }
    }

    private func loadMore() async {
        guard !loadingMore, nextCursor != nil else { return }
        loadingMore = true
        defer { loadingMore = false }
        await load(reset: false)
    }

    private func unblock(_ block: UserBlock) async {
        pendingUnblock = nil
        do {
            try await API.unblockUser(block.blockedId)
            items.removeAll { $0.blockedId == block.blockedId }
            ToastCenter.shared.show(RiskCopy.unblockSuccess, .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}
