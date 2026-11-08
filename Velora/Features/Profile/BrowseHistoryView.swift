import SwiftUI

/// 90-day browse footprint (DES-v1.3-12-01 ME-06 / D39).
struct BrowseHistoryView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter

    @State private var items: [BrowseHistoryItem] = []
    @State private var state: LoadState = .idle
    @State private var nextCursor: String?
    @State private var loadingMore = false
    @State private var showClearConfirm = false
    @State private var pendingDelete: BrowseHistoryItem?
    @State private var saveBrowseHistory = true

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                VLoadingView()
            case .failed(let m):
                VErrorView(message: m) { Task { await load(reset: true) } }
            case .loaded:
                if items.isEmpty {
                    VEmptyState(icon: "clock", title: MeCopy.historyEmpty, message: MeCopy.historyEmptyHint)
                } else {
                    list
                }
            }
        }
        .background(Color.vBackground)
        .navigationTitle(MeCopy.historyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button(MeCopy.historyClear) { showClearConfirm = true }
                        .foregroundStyle(Color.vPrimary)
                }
            }
        }
        .task { if items.isEmpty { await load(reset: true) } }
        .refreshable { await load(reset: true) }
        .confirmationDialog(MeCopy.historyClearConfirm, isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button(MeCopy.historyClear, role: .destructive) { Task { await clearAll() } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            MeCopy.historyDeleteConfirm,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete { Task { await delete(item) } }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: VSpace.m) {
                if !saveBrowseHistory {
                    Text(MeCopy.historySaveOffHint)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                ForEach(items) { item in
                    row(item)
                        .onAppear {
                            if item.id == items.last?.id, nextCursor != nil {
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

    @ViewBuilder
    private func row(_ item: BrowseHistoryItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if item.isUnavailable || item.targetId <= 0 {
                    Button {
                        ToastCenter.shared.show(MeCopy.historyUnavailable, .info)
                    } label: {
                        historyCard(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        ListingDetailView(listingId: item.targetId)
                    } label: {
                        historyCard(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                pendingDelete = item
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除")
        }
        .padding(12)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
    }

    private func historyCard(_ item: BrowseHistoryItem) -> some View {
        HStack(spacing: 12) {
            RemoteImage(item.cover ?? "")
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                .opacity(item.isUnavailable ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.vBodyMedium)
                    .foregroundStyle(item.isUnavailable ? Color.vTextTertiary : Color.vText)
                    .lineLimit(2)
                if item.isUnavailable {
                    Text(MeCopy.historyUnavailable)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                } else if let price = item.priceSnapshot {
                    Text(price.display)
                        .font(.vMono(15, weight: .semibold))
                        .foregroundStyle(Color.vPrimary)
                }
                if let at = item.lastViewedAt {
                    Text(at.shortText)
                        .font(.vMicro)
                        .foregroundStyle(Color.vTextTertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vTextTertiary)
        }
    }

    private func load(reset: Bool) async {
        if reset {
            if items.isEmpty { state = .loading }
            nextCursor = nil
        }
        do {
            if let settings = try? await API.meSettings() {
                saveBrowseHistory = settings.saveBrowseHistory
            }
            let page = try await API.meHistory(cursor: reset ? nil : nextCursor)
            items = reset ? page.items : items + page.items
            nextCursor = page.nextCursor
            state = .loaded
        } catch let e as APIError where e.status == 401 {
            state = .loaded
            items = []
            router.showLogin = true
        } catch {
            if items.isEmpty {
                state = .failed((error as? APIError)?.message ?? "加载失败")
            } else {
                ToastCenter.shared.error(error)
            }
        }
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await API.meHistory(cursor: cursor)
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private func delete(_ item: BrowseHistoryItem) async {
        pendingDelete = nil
        do {
            try await API.deleteMeHistory(id: item.id)
            items.removeAll { $0.id == item.id }
            ToastCenter.shared.show("已删除", .success)
        } catch let e as APIError where e.code == MeErrorCode.historyNotFound.rawValue {
            items.removeAll { $0.id == item.id }
        } catch {
            ToastCenter.shared.error(error)
        }
    }

    private func clearAll() async {
        do {
            try await API.clearMeHistory()
            items = []
            nextCursor = nil
            ToastCenter.shared.show("已清空", .success)
        } catch {
            ToastCenter.shared.error(error)
        }
    }
}

// MARK: - Client recorder (detail ≥2s)

@MainActor
enum BrowseHistoryRecorder {
    private static var lastSent: [Int64: Date] = [:]

    static func recordIfNeeded(
        listingId: Int64,
        sellerId: Int64?,
        meId: Int64?,
        saveBrowseHistory: Bool,
        isLoggedIn: Bool,
        appearedAt: Date
    ) async {
        let exposure = Date().timeIntervalSince(appearedAt)
        let isOwn = (sellerId != nil && sellerId == meId)
        guard MeLogic.shouldRecordHistory(
            isLoggedIn: isLoggedIn,
            saveBrowseHistory: saveBrowseHistory,
            isOwnListing: isOwn,
            exposureSeconds: exposure
        ) else { return }
        guard MeLogic.throttleAllows(lastSentAt: lastSent[listingId]) else { return }
        lastSent[listingId] = Date()
        do {
            try await API.recordMeHistory(listingId: listingId)
        } catch {
            // Design §11: history write failure must not affect detail browsing.
            #if DEBUG
            print("[history] record failed: \(error)")
            #endif
        }
    }
}
