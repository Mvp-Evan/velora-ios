import SwiftUI

/// Search / filter / ending-soon / sold / saved-search (DES-v1.3-02-02).
struct SearchView: View {
    var initialQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var session: SessionStore

    @StateObject private var model = SearchListModel()
    @StateObject private var filters = FiltersStore.shared
    @StateObject private var meta = SearchMetaStore.shared

    @State private var text = ""
    @State private var submitted = false
    @State private var showFilter = false
    @State private var showSubscribe = false
    @State private var resultTab: ResultTab = .onsale
    @State private var sort: ListingSearchSort = .comprehensive
    @AppStorage("search_history") private var historyRaw = ""
    @FocusState private var focused: Bool

    private enum ResultTab: String, Hashable {
        case onsale, sold
        var title: String { self == .onsale ? "在售" : "已成交" }
    }

    private var history: [String] { SearchHistoryStore.parse(historyRaw) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if model.networkDegraded {
                Text("网络不佳")
                    .font(.vCaption).foregroundStyle(Color.vPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.vPrimarySoft)
            }
            if submitted {
                ListRealtimeBanner(
                    endTimeText: model.realtime.endTimeChanges.showsBanner
                        ? model.realtime.endTimeChanges.bannerText : nil,
                    offline: model.realtime.realtimePaused && resultTab == .onsale && !model.items.isEmpty
                ) {
                    Task { await model.refreshFromBanner() }
                }
                resultChrome
                results
            } else {
                suggestions
            }
        }
        .background(Color.vBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.activateRealtime()
            await filters.load()
            await meta.loadHotWords()
            await meta.loadShortcuts()
            text = initialQuery
            if !initialQuery.isEmpty { submit() } else { focused = true }
        }
        .onDisappear { model.deactivateRealtime() }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            Task {
                await meta.loadShortcuts()
                if loggedIn { await meta.refreshSavedCount() }
            }
        }
        .sheet(isPresented: $showFilter) {
            SearchFilterSheet(query: $model.query, filters: filters.filters, soldMode: resultTab == .sold) {
                Task { await model.load() }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showSubscribe) {
            SaveSearchSheet(query: model.query) {
                Task { await meta.refreshSavedCount() }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Chrome

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.vText)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.vTextTertiary)
                TextField("搜索品牌、车型、比例", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { submit() }
                    .onChange(of: text) { _, v in if v.isEmpty { submitted = false } }
                if !text.isEmpty {
                    Button {
                        text = ""
                        submitted = false
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.vTextTertiary)
                    }
                }
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.vSurface, in: Capsule())
            Button("搜索") { submit() }.font(.vBodyMedium).foregroundStyle(Color.vPrimary)
        }
        .padding(.horizontal, VSpace.l).padding(.vertical, VSpace.s)
    }

    private var resultChrome: some View {
        VStack(spacing: VSpace.s) {
            HStack(spacing: 0) {
                ForEach([ResultTab.onsale, .sold], id: \.self) { tab in
                    Button {
                        switchResultTab(tab)
                    } label: {
                        Text(tab.title)
                            .font(resultTab == tab ? .vBodyMedium : .vBody)
                            .foregroundStyle(resultTab == tab ? Color.vPrimary : Color.vTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(resultTab == tab ? Color.vPrimary : .clear)
                                    .frame(height: 2)
                            }
                    }
                }
            }

            if resultTab == .onsale {
                endingSoonChips
            }

            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ListingSearchSort.allCases, id: \.self) { s in
                            let on = sort == s
                            Button {
                                sort = s
                                model.query.sort = s
                                model.onFilterChanged()
                                Task { await model.load() }
                            } label: {
                                Text(s.title)
                                    .font(on ? .vCaptionMedium : .vCaption)
                                    .foregroundStyle(on ? Color.vPrimary : Color.vTextSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? Color.vPrimarySoft : Color.vSurface, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, VSpace.l)
                }
                Button { showFilter = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease.circle" + (model.query.hasActiveFilters ? ".fill" : ""))
                        Text("筛选")
                    }
                    .font(.vCaptionMedium)
                    .foregroundStyle(model.query.hasActiveFilters ? Color.vPrimary : Color.vTextSecondary)
                    .padding(.trailing, VSpace.l)
                }
            }

            if resultTab == .onsale {
                HStack {
                    Button {
                        guard session.isLoggedIn else { router.showLogin = true; return }
                        showSubscribe = true
                    } label: {
                        Label("订阅此搜索", systemImage: "bell.badge")
                            .font(.vCaptionMedium)
                            .foregroundStyle(Color.vPrimary)
                    }
                    Spacer()
                    if model.query.hasActiveFilters || model.query.endingWithin != nil {
                        Button("清除筛选") {
                            clearFiltersKeepingKeyword()
                        }
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                    }
                }
                .padding(.horizontal, VSpace.l)
            }
        }
        .padding(.bottom, VSpace.s)
    }

    private var endingSoonChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EndingWithin.allCases, id: \.self) { w in
                    let on = model.query.endingWithin == w
                    Button {
                        toggleEnding(w)
                    } label: {
                        Text(w == .tonight ? SearchBusinessTimezone.tonightCaption() : w.title)
                            .font(on ? .vCaptionMedium : .vCaption)
                            .foregroundStyle(on ? Color.vPrimary : Color.vText)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(on ? Color.vPrimarySoft : Color.vSurface, in: Capsule())
                            .overlay(
                                Capsule().stroke(on ? Color.vPrimary : .clear, lineWidth: 1)
                            )
                    }
                }
                leakChip(title: "无人出价", bid: 0)
                leakChip(title: "≤1次出价", bid: 1)
                let noReserveOn = model.query.noReserve == true
                Button {
                    model.query.noReserve = noReserveOn ? nil : true
                    Task { await model.load() }
                } label: {
                    Text("无保留价")
                        .font(noReserveOn ? .vCaptionMedium : .vCaption)
                        .foregroundStyle(noReserveOn ? Color.vPrimary : Color.vText)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(noReserveOn ? Color.vPrimarySoft : Color.vSurface, in: Capsule())
                }
            }
            .padding(.horizontal, VSpace.l)
        }
    }

    private func leakChip(title: String, bid: Int) -> some View {
        let on = model.query.maxBidCount == bid
        return Button {
            model.query.maxBidCount = on ? nil : bid
            Task { await model.load() }
        } label: {
            Text(title)
                .font(on ? .vCaptionMedium : .vCaption)
                .foregroundStyle(on ? Color.vPrimary : Color.vText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Color.vPrimarySoft : Color.vSurface, in: Capsule())
        }
    }

    // MARK: - Results

    private var results: some View {
        ScrollView {
            switch model.state {
            case .idle, .loading: VLoadingView()
            case .failed(let m): VErrorView(message: m) { Task { await model.load() } }
            case .loaded:
                if model.items.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: VSpace.m) {
                        Text("共 \(model.total) 件")
                            .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        WaterfallGrid(
                            items: model.items,
                            height: { SearchListingCardView.estimatedHeight(for: $0, imageHeight: SearchListingCardView.imageHeight(for: $0)) }
                        ) { card in
                            NavigationLink(value: card) {
                                SearchListingCardView(card: card, imageHeight: SearchListingCardView.imageHeight(for: card))
                            }
                            .buttonStyle(.plain)
                            .reportLotCardVisibility(
                                lotId: card.tradeType == "auction" ? card.lotId : nil,
                                onRatio: { id, ratio in model.realtime.updateVisibility(lotId: id, ratio: ratio) },
                                onDisappear: { id in model.realtime.cardDidDisappear(lotId: id) }
                            )
                            .onAppear {
                                if model.shouldLoadMore(card) { Task { await model.loadMore() } }
                            }
                        }
                        if model.loadingMore { ProgressView().padding() }
                    }
                    .padding(.horizontal, VSpace.m)
                    .padding(.bottom, VSpace.xl)
                }
            }
        }
        .refreshable {
            model.realtime.acknowledgeBannerAndRefresh()
            await model.load()
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { model.realtime.updateViewportHeight(geo.size.height) }
                    .onChange(of: geo.size.height) { _, h in model.realtime.updateViewportHeight(h) }
            }
        )
        .navigationDestination(for: SearchListingCard.self) { card in
            ListingDetailView(listingId: card.listingId, lotId: card.lotId, preloadTradeType: card.tradeType)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if resultTab == .sold {
            VEmptyState(icon: "checkmark.seal", title: "近 30 天暂无成交", message: "换个关键词，或看看在售商品")
        } else if model.query.endingWithin != nil {
            VEmptyState(icon: "timer", title: "接下来没有结拍", message: "去热门看看，或放宽时间与捡漏条件")
        } else {
            VEmptyState(icon: "magnifyingglass", title: "没有找到相关商品", message: "试试去掉捡漏条件，或点热搜换个词")
        }
    }

    // MARK: - Suggestions

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VSpace.xl) {
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: VSpace.m) {
                        HStack {
                            Text("搜索历史").font(.vHeadline)
                            Spacer()
                            Button { historyRaw = "" } label: {
                                Image(systemName: "trash").foregroundStyle(Color.vTextTertiary)
                            }
                            .accessibilityLabel("清空搜索历史")
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(history, id: \.self) { h in
                                Button { text = h; submit() } label: {
                                    chip(h)
                                }
                            }
                        }
                    }
                }

                if session.isLoggedIn, !meta.shortcuts.sorted.isEmpty {
                    VStack(alignment: .leading, spacing: VSpace.m) {
                        HStack {
                            Text("我的快捷词").font(.vHeadline)
                            Spacer()
                            Text("\(meta.shortcuts.words.count)/\(SearchLimits.maxShortcuts)")
                                .font(.vCaption).foregroundStyle(Color.vTextTertiary)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(meta.shortcuts.sorted) { s in
                                Button { text = s.word; submit() } label: {
                                    chip(s.word, tinted: true)
                                }
                                .contextMenu {
                                    Button("删除", role: .destructive) {
                                        Task { await removeShortcut(s.word) }
                                    }
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
                        ForEach(Array(meta.hotWords.enumerated()), id: \.element.id) { i, k in
                            Button { text = k.word; submit() } label: {
                                HStack(spacing: 5) {
                                    Text("\(i + 1)").font(.vMono(11)).foregroundStyle(i < 3 ? Color.vPrimary : Color.vTextTertiary)
                                    Text(k.word).font(.vCaption).foregroundStyle(Color.vText)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.vSurface, in: Capsule())
                            }
                            .contextMenu {
                                Button("添加到快捷词") { Task { await addShortcut(k.word) } }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text("按品牌").font(.vHeadline)
                    FlowLayout(spacing: 8) {
                        ForEach(filters.filters.brands, id: \.self) { b in
                            Button {
                                model.query.brand = b
                                text = b
                                submit(keyword: false)
                            } label: { chip(b) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: VSpace.m) {
                    Text("按比例").font(.vHeadline)
                    FlowLayout(spacing: 8) {
                        ForEach(filters.filters.effectiveScales, id: \.self) { s in
                            Button {
                                model.query.scale = s
                                text = s
                                submit(keyword: false)
                            } label: {
                                Text(s).font(.vMono(12)).foregroundStyle(Color.vText)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.vSurface, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(VSpace.l)
        }
        .onTapGesture { focused = false }
    }

    private func chip(_ title: String, tinted: Bool = false) -> some View {
        Text(title)
            .font(.vCaption)
            .foregroundStyle(tinted ? Color.vPrimary : Color.vText)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(tinted ? Color.vPrimarySoft : Color.vSurface, in: Capsule())
    }

    // MARK: - Actions

    private func submit(keyword: Bool = true) {
        focused = false
        let q = text.trimmingCharacters(in: .whitespaces)
        if keyword {
            model.query.q = q.isEmpty ? nil : q
            if !q.isEmpty { SearchHistoryStore.push(q, into: &historyRaw) }
        }
        model.query.sort = sort
        model.query.applySoldTab(resultTab == .sold)
        submitted = true
        Task { await model.load() }
    }

    private func switchResultTab(_ tab: ResultTab) {
        guard resultTab != tab else { return }
        resultTab = tab
        // Keep keyword; clear time shortcuts when entering sold (DES §9).
        model.query.applySoldTab(tab == .sold)
        if tab == .sold {
            model.query.maxBidCount = nil
            model.query.noReserve = nil
        }
        model.onFilterChanged()
        Task { await model.load() }
    }

    private func toggleEnding(_ w: EndingWithin) {
        if model.query.endingWithin == w {
            model.query.endingWithin = nil
        } else {
            model.query.endingWithin = w
            model.query.sold = nil
            if resultTab == .sold { resultTab = .onsale }
        }
        model.onFilterChanged()
        Task { await model.load() }
    }

    private func clearFiltersKeepingKeyword() {
        let q = model.query.q
        let sold = resultTab == .sold
        model.query = ListingSearchQuery(q: q, sold: sold ? true : nil, sort: sort)
        model.onFilterChanged()
        Task { await model.load() }
    }

    private func addShortcut(_ word: String) async {
        guard session.isLoggedIn else { router.showLogin = true; return }
        if let err = meta.shortcuts.upsert(word) {
            ToastCenter.shared.show(err.fallbackMessage, .info)
            return
        }
        if let err = await meta.saveShortcuts() {
            ToastCenter.shared.show(err.fallbackMessage, .error)
            await meta.loadShortcuts()
        } else {
            ToastCenter.shared.show("已加入快捷词", .success)
        }
    }

    private func removeShortcut(_ word: String) async {
        meta.shortcuts.remove(word)
        _ = await meta.saveShortcuts()
    }
}

// MARK: - Filter sheet

struct SearchFilterSheet: View {
    @Binding var query: ListingSearchQuery
    let filters: Filters
    var soldMode: Bool = false
    let apply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ListingSearchQuery()
    @State private var minText = ""
    @State private var maxText = ""
    @State private var priceError: String?

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
                        if let priceError {
                            Text(priceError).font(.vCaption).foregroundStyle(Color.vPrimary)
                        }
                    }
                    optionGroup("品牌", filters.brands, $draft.brand)
                    optionGroup("比例", filters.effectiveScales, $draft.scale)
                    optionGroup("系列", filters.series, $draft.series)
                    optionGroup("成色", filters.conditions, $draft.condition)
                    group("交易方式") {
                        tradeTypePills
                    }
                    if !soldMode {
                        group("包邮") {
                            Toggle("仅看包邮", isOn: Binding(
                                get: { draft.freeShipping == true },
                                set: { draft.freeShipping = $0 ? true : nil }
                            ))
                            .tint(Color.vPrimary)
                        }
                        group("即将结束") {
                            endingPills
                        }
                        group("捡漏条件") {
                            leakOptions
                        }
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
                        let q = query.q
                        draft = ListingSearchQuery(q: q, sold: soldMode ? true : nil)
                        minText = ""; maxText = ""; priceError = nil
                    }
                    VPrimaryButton(title: "确定") {
                        commit()
                    }
                }
                .padding(VSpace.l).background(Color.vSurface)
            }
        }
        .onAppear {
            draft = query
            minText = query.priceMin.map { String(Int($0 / 100)) } ?? ""
            maxText = query.priceMax.map { String(Int($0 / 100)) } ?? ""
        }
        .onChange(of: minText) { _, _ in validatePriceDraft() }
        .onChange(of: maxText) { _, _ in validatePriceDraft() }
    }

    private var tradeTypePills: some View {
        let items: [(String?, String)] = [(nil, "全部"), ("auction", "拍卖"), ("fixed", "直购"), ("release", "发售")]
        return FlowLayout(spacing: 8) {
            ForEach(items, id: \.1) { value, title in
                let on = draft.tradeType == value
                Button { draft.tradeType = on && value != nil ? nil : value } label: {
                    pill(title, on: on || (value == nil && draft.tradeType == nil))
                }
            }
        }
    }

    private var endingPills: some View {
        FlowLayout(spacing: 8) {
            ForEach(EndingWithin.allCases, id: \.self) { w in
                let on = draft.endingWithin == w
                Button { draft.endingWithin = on ? nil : w } label: {
                    pill(w.title, on: on)
                }
            }
        }
    }

    private var leakOptions: some View {
        FlowLayout(spacing: 8) {
            leakToggle("无人出价", bid: 0)
            leakToggle("≤1次出价", bid: 1)
            let on = draft.noReserve == true
            Button { draft.noReserve = on ? nil : true } label: { pill("无保留价", on: on) }
        }
    }

    private func leakToggle(_ title: String, bid: Int) -> some View {
        let on = draft.maxBidCount == bid
        return Button { draft.maxBidCount = on ? nil : bid } label: { pill(title, on: on) }
    }

    private func pill(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(on ? .vCaptionMedium : .vCaption)
            .foregroundStyle(on ? Color.vPrimary : Color.vText)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? Color.vPrimarySoft : Color.vSurface, in: RoundedRectangle(cornerRadius: VRadius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VRadius.m, style: .continuous)
                    .stroke(on ? Color.vPrimary : .clear, lineWidth: 1)
            )
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: VSpace.m) { Text(title).font(.vHeadline); c() }
    }

    private func optionGroup(_ title: String, _ options: [String], _ sel: Binding<String?>) -> some View {
        group(title) {
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    let on = sel.wrappedValue == o
                    Button { sel.wrappedValue = on ? nil : o } label: { pill(o, on: on) }
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

    private func validatePriceDraft() {
        let minV = Double(minText)
        let maxV = Double(maxText)
        if let minV, let maxV, minV > maxV {
            priceError = SearchErrorCode.invalidPriceRange.fallbackMessage
        } else if (!minText.isEmpty && Double(minText) == nil) || (!maxText.isEmpty && Double(maxText) == nil) {
            priceError = "请输入有效金额"
        } else {
            priceError = nil
        }
    }

    private func commit() {
        validatePriceDraft()
        guard priceError == nil else { return }
        draft.priceMin = Double(minText).map { Money($0 * 100) }
        draft.priceMax = Double(maxText).map { Money($0 * 100) }
        draft.page = 1
        if soldMode {
            draft.sold = true
            draft.endingWithin = nil
        }
        if let err = draft.validating() {
            priceError = err.fallbackMessage
            return
        }
        query = draft
        apply()
        dismiss()
    }
}

// MARK: - Save / subscribe sheet

struct SaveSearchSheet: View {
    let query: ListingSearchQuery
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var router: AppRouter
    @State private var notify: Set<SavedSearchNotifyType> = [.newList, .endingSoon]
    @State private var saving = false
    @State private var pendingRetry = false
    @StateObject private var meta = SearchMetaStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(summary)
                        .font(.vBody)
                        .foregroundStyle(Color.vText)
                    Text("命中后只提醒一次，同一商品不会因多条订阅重复推送")
                        .font(.vCaption)
                        .foregroundStyle(Color.vTextTertiary)
                }
                Section("提醒类型") {
                    ForEach(SavedSearchNotifyType.allCases, id: \.self) { t in
                        Toggle(t.title, isOn: Binding(
                            get: { notify.contains(t) },
                            set: { on in
                                if on { notify.insert(t) } else { notify.remove(t) }
                            }
                        ))
                    }
                }
                if meta.savedCount >= SearchLimits.savedSearchSoftWarnAt {
                    Section {
                        Text("已有 \(meta.savedCount) 条订阅，最多 \(SearchLimits.maxSavedSearches) 条")
                            .font(.vCaption)
                            .foregroundStyle(Color.vPrimary)
                    }
                }
            }
            .navigationTitle("订阅搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(pendingRetry ? "重试" : "保存") { Task { await save() } }
                        .disabled(saving || notify.isEmpty)
                }
            }
            .task { await meta.refreshSavedCount() }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let q = query.q, !q.isEmpty { parts.append("「\(q)」") }
        if let e = query.endingWithin { parts.append(e.title) }
        if let bid = query.maxBidCount { parts.append(bid == 0 ? "无人出价" : "≤1次出价") }
        if query.noReserve == true { parts.append("无保留价") }
        if let b = query.brand { parts.append(b) }
        if parts.isEmpty { return "当前筛选条件" }
        return parts.joined(separator: " · ")
    }

    private func save() async {
        guard session.isLoggedIn else { router.showLogin = true; return }
        saving = true
        defer { saving = false }
        do {
            _ = try await API.createSavedSearch(
                query: query.q,
                filters: query.filtersSnapshot,
                notifyTypes: Array(notify)
            )
            pendingRetry = false
            ToastCenter.shared.show("订阅成功，命中后只提醒一次", .success)
            onSaved()
            dismiss()
        } catch let e as APIError {
            pendingRetry = true
            if let code = SearchErrorCode(rawValue: e.code) {
                ToastCenter.shared.show(code.fallbackMessage, .error)
            } else {
                ToastCenter.shared.show("保存失败，可点重试", .error)
            }
        } catch {
            pendingRetry = true
            ToastCenter.shared.show("保存失败，可点重试", .error)
        }
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
