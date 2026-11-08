import SwiftUI

/// Phase 3 empty / coming-soon shells for 产品库 / 模型柜 / 图鉴 (DES-v1.3-12-04 / D42).
/// Curve UI is never shown while `library.curve` is off.

struct LibraryIndexView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var items: [ProductSKU] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private var libraryCurveEnabled: Bool {
        session.bootstrap?.flag(LibraryConfigDefaults.curveFlagKey)
            ?? LibraryConfigDefaults.curveEnabledDefault
    }

    private var placeholder: LibraryPlaceholderKind {
        items.isEmpty ? .libraryBuilding : .empty
    }

    var body: some View {
        Group {
            if items.isEmpty {
                LibraryEmptyPlaceholder(
                    kind: .libraryBuilding,
                    detail: loadError
                )
            } else {
                skuList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBackground)
        .navigationTitle(LibraryCopy.libraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private var skuList: some View {
        List(items) { sku in
            NavigationLink {
                SkuDetailPlaceholderView(skuId: sku.id, libraryCurveEnabled: libraryCurveEnabled)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sku.displayName)
                        .font(.vBodyMedium)
                        .foregroundStyle(Color.vText)
                    if let code = sku.skuCode {
                        Text(code)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }

    private func refresh() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        _ = isLoading
        do {
            let page = try await API.listSKUs()
            items = page.items
        } catch {
            items = []
            loadError = (error as? APIError)?.message
        }
    }
}

struct CabinetWallView: View {
    let userId: Int64?
    var isSelf: Bool = true
    var entryKind: LibraryPlaceholderKind = .cabinetComingSoon

    @EnvironmentObject private var session: SessionStore
    @State private var wall: CabinetWallResponse?
    @State private var lastErrorCode: String?
    @State private var isLoading = false

    private var placeholder: LibraryPlaceholderKind {
        if lastErrorCode == LibraryErrorCode.cabinetPrivate.rawValue {
            return .cabinetPrivate
        }
        if (wall?.items.isEmpty ?? true) { return entryKind }
        return .empty
    }

    var body: some View {
        Group {
            if let items = wall?.items, !items.isEmpty {
                cabinetGrid(items)
            } else {
                LibraryEmptyPlaceholder(kind: placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBackground)
        .navigationTitle(
            entryKind == .atlasComingSoon ? LibraryCopy.atlasTitle : LibraryCopy.cabinetTitle
        )
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func cabinetGrid(_ items: [CabinetItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                            .fill(Color.vFill)
                            .frame(height: 100)
                            .overlay {
                                Image(systemName: "cube.transparent")
                                    .foregroundStyle(Color.vTextTertiary)
                            }
                        if item.showsManualMark {
                            Text(LibraryCopy.manualMark)
                                .font(.vMicro)
                                .foregroundStyle(Color.vTextSecondary)
                        }
                    }
                }
            }
            .padding(VSpace.l)
        }
    }

    private func refresh() async {
        isLoading = true
        lastErrorCode = nil
        defer { isLoading = false }
        _ = isLoading
        do {
            if let userId {
                wall = try await API.userCabinet(userId: userId)
            } else if isSelf, let me = session.user?.id {
                wall = try await API.userCabinet(userId: me)
            } else {
                wall = CabinetWallResponse()
            }
        } catch let err as APIError {
            lastErrorCode = err.code
            wall = nil
        } catch {
            wall = nil
        }
    }
}

struct AtlasSummaryView: View {
    @State private var summary: CabinetSummaryResponse?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let summary, !summary.completion.isEmpty {
                summaryContent(summary)
            } else {
                LibraryEmptyPlaceholder(
                    kind: .atlasComingSoon,
                    detail: loadError
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBackground)
        .navigationTitle(LibraryCopy.atlasTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func summaryContent(_ summary: CabinetSummaryResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                ForEach(summary.completion, id: \.seriesId) { row in
                    HStack {
                        Text(row.seriesName ?? "系列 \(row.seriesId)")
                            .font(.vBodyMedium)
                            .foregroundStyle(Color.vText)
                        Spacer()
                        Text(row.label)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                    .padding(14)
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
                }
                // Design §5.8 — disclaimer always rendered when summary present.
                if summary.showsDisclaimer {
                    Text(summary.displayDisclaimer)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                        .padding(.top, 4)
                }
            }
            .padding(VSpace.l)
        }
    }

    private func refresh() async {
        loadError = nil
        do {
            summary = try await API.meCabinetSummary()
        } catch {
            summary = nil
            loadError = (error as? APIError)?.message
        }
    }
}

/// SKU detail shell — curve section hidden when `library.curve` is off.
struct SkuDetailPlaceholderView: View {
    let skuId: Int64
    var libraryCurveEnabled: Bool

    @State private var sku: ProductSKU?
    @State private var curve: SkuCurveResponse?
    @State private var loadError: String?

    private var curvePlaceholder: LibraryPlaceholderKind? {
        LibraryLogic.curvePlaceholder(
            libraryCurveEnabled: libraryCurveEnabled,
            skuCurveEnabled: sku?.isCurveEnabled ?? false,
            sampleN: curve?.resolvedSampleN ?? 0
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.l) {
                if let sku {
                    Text(sku.displayName)
                        .font(.vTitle(20))
                        .foregroundStyle(Color.vText)
                    if let code = sku.skuCode {
                        Text(code)
                            .font(.vCaption)
                            .foregroundStyle(Color.vTextSecondary)
                    }
                } else if let loadError {
                    Text(loadError)
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }

                curveSection
            }
            .padding(VSpace.l)
        }
        .background(Color.vBackground)
        .navigationTitle(LibraryCopy.libraryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
    }

    @ViewBuilder
    private var curveSection: some View {
        // Phase 3 / design §13: never paint curve while flag off.
        if let kind = curvePlaceholder {
            VStack(alignment: .leading, spacing: 8) {
                Text(LibraryCopy.curveTitle)
                    .font(.vHeadline)
                    .foregroundStyle(Color.vText)
                Text(LibraryLogic.placeholderTitle(kind))
                    .font(.vBody)
                    .foregroundStyle(Color.vTextSecondary)
                Text(LibraryLogic.placeholderHint(kind))
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        } else if let curve, !curve.points.isEmpty {
            // Points are display-only — never deep-link to listing (LIB-02 / HOME-13).
            VStack(alignment: .leading, spacing: 8) {
                Text(LibraryCopy.curveTitle)
                    .font(.vHeadline)
                ForEach(Array(curve.points.enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text(p.date).font(.vCaption).foregroundStyle(Color.vTextSecondary)
                        Spacer()
                        Text("¥\(p.price)")
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vText)
                    }
                }
            }
            .padding(14)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.l, style: .continuous))
        }
    }

    private func refresh() async {
        loadError = nil
        do {
            sku = try await API.skuDetail(skuId)
            if libraryCurveEnabled {
                do {
                    curve = try await API.skuCurve(skuId)
                } catch {
                    curve = nil
                }
            } else {
                curve = nil
            }
        } catch {
            sku = nil
            loadError = (error as? APIError)?.message ?? LibraryCopy.skuNotFound
        }
    }
}

struct LibraryEmptyPlaceholder: View {
    let kind: LibraryPlaceholderKind
    var detail: String? = nil

    var body: some View {
        VStack(spacing: VSpace.l) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.vTextTertiary)
            Text(LibraryLogic.placeholderTitle(kind))
                .font(.vTitle(20))
                .foregroundStyle(Color.vText)
            Text(LibraryLogic.placeholderHint(kind))
                .font(.vBody)
                .foregroundStyle(Color.vTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, VSpace.xl)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.vCaption)
                    .foregroundStyle(Color.vTextTertiary)
            }
            Spacer()
        }
    }

    private var iconName: String {
        switch kind {
        case .libraryBuilding: return "books.vertical"
        case .cabinetComingSoon, .empty: return "cube.box"
        case .atlasComingSoon: return "square.grid.3x3"
        case .cabinetPrivate: return "lock"
        case .curveNotReady, .curveHiddenByFlag: return "chart.xyaxis.line"
        }
    }
}
