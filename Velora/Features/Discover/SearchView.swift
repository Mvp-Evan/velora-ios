import SwiftUI

struct SearchView: View {
    var initialQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = LotListModel(query: .init(status: "all"))
    @StateObject private var filters = FiltersStore.shared
    @State private var text = ""
    @State private var submitted = false
    @State private var showFilter = false
    @State private var sort = ""
    @AppStorage("search_history") private var historyRaw = ""
    @FocusState private var focused: Bool

    private var history: [String] { historyRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if submitted {
                sortBar
                results
            } else {
                suggestions
            }
        }
        .background(Color.vBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await filters.load()
            text = initialQuery
            if !initialQuery.isEmpty { submit() } else { focused = true }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(query: $model.query, filters: filters.filters) { Task { await model.load() } }
                .presentationDetents([.large])
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.vText) }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vTextTertiary)
                TextField("搜索品牌、车型、比例", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { submit() }
                    .onChange(of: text) { _, v in if v.isEmpty { submitted = false } }
                if !text.isEmpty {
                    Button { text = ""; submitted = false; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.vTextTertiary) }
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.vSurface, in: Capsule())
            Button("搜索") { submit() }.font(.vBodyMedium).foregroundStyle(Color.vPrimary)
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, VSpace.s)
    }

    private var sortBar: some View {
        HStack {
            VPillSegments(items: [("", "综合")] + filters.filters.sorts.map { ($0.key, $0.name) }, selection: $sort)
                .onChange(of: sort) { _, v in model.query.sort = v.isEmpty ? nil : v; Task { await model.load() } }
            Button { showFilter = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease.circle" + (hasFilters ? ".fill" : ""))
                    Text("筛选")
                }
                .font(.vCaptionMedium).foregroundStyle(hasFilters ? Color.vPrimary : Color.vTextSecondary)
                .padding(.trailing, VSpace.l)
            }
        }
        .padding(.vertical, VSpace.s)
    }

    private var hasFilters: Bool {
        let q = model.query
        return q.category != nil || q.brand != nil || q.scale != nil || q.condition != nil || q.minPrice != nil || q.maxPrice != nil || q.series != nil
    }

    private var results: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if model.items.isEmpty {
                    VEmptyState(icon: "magnifyingglass", title: "没有找到相关拍品", message: "试试别的关键词或放宽筛选条件")
                } else {
                    VStack(spacing: VSpace.m) {
                        Text("共 \(model.total) 件").font(.vCaption).foregroundStyle(Color.vTextTertiary).frame(maxWidth: .infinity, alignment: .leading)
                        WaterfallGrid(items: model.items, height: { LotCard.estimatedHeight(for: $0, imageHeight: LotCard.imageHeight(for: $0)) }) { lot in
                            NavigationLink(value: lot) { LotCard(lot: lot, imageHeight: LotCard.imageHeight(for: lot)) }
                                .buttonStyle(.plain)
                                .onAppear { if model.shouldLoadMore(lot) { Task { await model.loadMore() } } }
                        }
                        if model.loadingMore { ProgressView().padding() }
                    }
                    .padding(.horizontal, VSpace.m)
                    .padding(.bottom, VSpace.xl)
                }
            }
        }
        .navigationDestination(for: Lot.self) { LotDetailView(lotId: $0.id, preload: $0) }
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.xl) {
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: VSpace.m) {
                        HStack {
                            Text("搜索历史").font(.vHeadline)
                            Spacer()
                            Button { historyRaw = "" } label: { Image(systemName: "trash").foregroundStyle(Color.vTextTertiary) }
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(history, id: \.self) { h in
                                Button { text = h; submit() } label: {
                                    Text(h).font(.vCaption).foregroundStyle(Color.vText).padding(.horizontal, 12).padding(.vertical, 7).background(Color.vSurface, in: Capsule())
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: VSpace.m) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundStyle(Color.vPrimary)
                        Text("热门搜索").font(.vHeadline)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(Array(filters.filters.hotKeywords.enumerated()), id: \.offset) { i, k in
                            Button { text = k; submit() } label: {
                                HStack(spacing: 5) {
                                    Text("\(i + 1)").font(.vMono(11)).foregroundStyle(i < 3 ? Color.vPrimary : Color.vTextTertiary)
                                    Text(k).font(.vCaption).foregroundStyle(Color.vText)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7).background(Color.vSurface, in: Capsule())
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text("按品牌").font(.vHeadline)
                    FlowLayout(spacing: 8) {
                        ForEach(filters.filters.brands, id: \.self) { b in
                            Button { model.query.brand = b; text = b; submit(keyword: false) } label: {
                                Text(b).font(.vCaption).foregroundStyle(Color.vText).padding(.horizontal, 12).padding(.vertical, 7).background(Color.vSurface, in: Capsule())
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text("按比例").font(.vHeadline)
                    FlowLayout(spacing: 8) {
                        ForEach(filters.filters.scales, id: \.self) { s in
                            Button { model.query.scale = s; text = s; submit(keyword: false) } label: {
                                Text(s).font(.vMono(12)).foregroundStyle(Color.vText).padding(.horizontal, 12).padding(.vertical, 7).background(Color.vSurface, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(VSpace.l)
        }
        .onTapGesture { focused = false }
    }

    private func submit(keyword: Bool = true) {
        focused = false
        let q = text.trimmingCharacters(in: .whitespaces)
        if keyword {
            model.query.q = q.isEmpty ? nil : q
            if !q.isEmpty {
                var h = history.filter { $0 != q }; h.insert(q, at: 0)
                historyRaw = h.prefix(10).joined(separator: "\n")
            }
        }
        submitted = true
        Task { await model.load() }
    }
}

// MARK: - Filter sheet

struct FilterSheet: View {
    @Binding var query: API.LotQuery
    let filters: Filters
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: API.LotQuery = .init()
    @State private var minText = ""
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VSpace.xl) {
                    group("价格区间") {
                        HStack(spacing: 10) {
                            priceField("最低价", $minText)
                            Rectangle().fill(Color.vSeparator).frame(width: 12, height: 1)
                            priceField("最高价", $maxText)
                        }
                    }
                    optionGroup("分类", filters.categories, $draft.category)
                    optionGroup("品牌", filters.brands, $draft.brand)
                    optionGroup("比例", filters.scales, $draft.scale)
                    optionGroup("系列", filters.series, $draft.series)
                    optionGroup("成色", filters.conditions, $draft.condition)
                    group("状态") {
                        VPillSegments(items: [("all", "全部"), ("live", "竞拍中"), ("upcoming", "即将开始"), ("ended", "已结束")],
                                      selection: Binding(get: { draft.status ?? "all" }, set: { draft.status = $0 }))
                        .padding(.horizontal, -VSpace.l)
                    }
                }
                .padding(VSpace.l)
            }
            .background(Color.vBackground)
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    VPrimaryButton(title: "重置", style: .outline) {
                        draft = .init(status: query.status, q: query.q); minText = ""; maxText = ""
                    }
                    VPrimaryButton(title: "确定") {
                        draft.minPrice = Double(minText).map { Money($0 * 100) }
                        draft.maxPrice = Double(maxText).map { Money($0 * 100) }
                        draft.page = 1
                        query = draft
                        apply(); dismiss()
                    }
                }
                .padding(VSpace.l).background(Color.vSurface)
            }
        }
        .onAppear {
            draft = query
            minText = query.minPrice.map { String(Int($0 / 100)) } ?? ""
            maxText = query.maxPrice.map { String(Int($0 / 100)) } ?? ""
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: VSpace.m) { Text(title).font(.vHeadline); c() }
    }

    private func optionGroup(_ title: String, _ options: [String], _ sel: Binding<String?>) -> some View {
        group(title) {
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    let on = sel.wrappedValue == o
                    Button { sel.wrappedValue = on ? nil : o } label: {
                        Text(o).font(on ? .vCaptionMedium : .vCaption)
                            .foregroundStyle(on ? Color.vPrimary : Color.vText)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? Color.vPrimarySoft : Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: VRadius.m, style: .continuous).stroke(on ? Color.vPrimary : .clear, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func priceField(_ ph: String, _ t: Binding<String>) -> some View {
        HStack(spacing: 4) {
            Text("¥").foregroundStyle(Color.vTextTertiary)
            TextField(ph, text: t).keyboardType(.numberPad).font(.vMono(15))
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
    }
}

// MARK: - Flow layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: w == .infinity ? x : w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
