import Foundation
import Combine

/// Direct zone config + cursor list (DES-v1.3-04-01).
@MainActor
final class DirectZoneModel: ObservableObject {
    @Published var config = DirectZoneConfig()
    @Published var items: [DirectZoneListingCard] = []
    @Published var state: LoadState = .idle
    @Published var hasMore = true
    @Published var total: Int?
    @Published private(set) var loadingMore = false
    @Published var section: DirectZoneSectionKey = .new
    @Published var sort: DirectZoneSort = .newest
    @Published var searchText = ""
    @Published var freeShipping = false
    @Published var negotiable = false
    @Published var brandNew = false
    @Published var brandOfficial = false
    @Published var zoneDisabled = false

    private var nextCursor: String?
    private var configLoaded = false

    private enum Prefs {
        static let section = "direct_zone.last_section"
        static let freeShipping = "direct_zone.filter.free_shipping"
        static let negotiable = "direct_zone.filter.negotiable"
        static let brandNew = "direct_zone.filter.brand_new"
        static let brandOfficial = "direct_zone.filter.brand_official"
    }

    init() {
        restorePrefs()
    }

    var enabledSections: [DirectZoneSection] { config.enabledSections }
    var enabledQuickFilters: [DirectZoneFilterOption] {
        config.enabledFilters.filter {
            switch $0.key {
            case .freeShipping, .negotiable, .brandNew: return true
            case .brandOfficial, .priceRange, .brandSeries: return false
            }
        }
    }

    var availableSorts: [DirectZoneSort] { DirectZoneLogic.sorts(for: section) }
    var showsSortPicker: Bool { availableSorts.count > 1 }
    var hasActiveFilters: Bool {
        freeShipping || negotiable || brandNew || brandOfficial || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var featuredSlots: [DirectZoneSlotPublic] {
        guard section == .featured else { return [] }
        return Array(config.featuredSlots.sorted { $0.position < $1.position }.prefix(DirectZoneConfigDefaults.featuredSlotMax))
    }

    func bootstrapFlagEnabled(session: SessionStore) -> Bool {
        if let flags = session.bootstrap?.flags {
            if let v = flags[DirectZoneConfigDefaults.bootstrapFlagKey] { return v }
            if let v = flags["direct_zone"] { return v }
        }
        return true
    }

    func loadConfig(force: Bool = false) async {
        if configLoaded && !force { return }
        do {
            let cfg = try await API.directZone()
            config = cfg
            zoneDisabled = !cfg.enabled
            configLoaded = true
            reconcileSectionAgainstConfig()
        } catch {
            // Fall back to local defaults so the zone still opens offline.
            config = DirectZoneConfig()
            configLoaded = true
            #if DEBUG
            print("[direct-zone] config failed: \(error)")
            #endif
        }
    }

    func load(reset: Bool = true) async {
        if zoneDisabled {
            items = []
            state = .loaded
            hasMore = false
            return
        }
        var q = makeQuery(cursor: reset ? nil : nextCursor)
        if let err = DirectZoneLogic.validateListingsQuery(q) {
            state = .failed(err == "invalid_section" ? DirectZoneErrorCode.invalidSection.fallbackMessage : "筛选条件无效")
            return
        }
        if reset {
            state = items.isEmpty ? .loading : state
            nextCursor = nil
            q.cursor = nil
        }
        do {
            let page = try await API.directZoneListings(q)
            if reset {
                items = page.items
            } else {
                let known = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            }
            nextCursor = page.nextCursor
            hasMore = page.hasMore
            total = page.total
            if let v = page.configVersion, v != config.configVersion {
                await loadConfig(force: true)
            }
            state = .loaded
        } catch let e as APIError {
            if let code = DirectZoneErrorCode(rawValue: e.code) {
                state = .failed(e.message.isEmpty ? code.fallbackMessage : e.message)
            } else if items.isEmpty {
                state = .failed(e.message.isEmpty ? "加载失败" : e.message)
            } else {
                ToastCenter.shared.error(e)
            }
        } catch {
            if items.isEmpty { state = .failed("加载失败") }
            else { ToastCenter.shared.error(error) }
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore, state == .loaded, let cursor = nextCursor, !cursor.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }
        await load(reset: false)
    }

    func shouldLoadMore(_ card: DirectZoneListingCard) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == card.id }) else { return false }
        return idx >= items.count - 4
    }

    func selectSection(_ key: DirectZoneSectionKey) {
        guard section != key else { return }
        section = key
        sort = DirectZoneLogic.defaultSort(for: key)
        UserDefaults.standard.set(key.rawValue, forKey: Prefs.section)
        Task { await load(reset: true) }
    }

    func selectSort(_ value: DirectZoneSort) {
        guard availableSorts.contains(value), sort != value else { return }
        sort = value
        Task { await load(reset: true) }
    }

    func toggleFilter(_ key: DirectZoneFilterKey) {
        switch key {
        case .freeShipping:
            freeShipping.toggle()
            UserDefaults.standard.set(freeShipping, forKey: Prefs.freeShipping)
        case .negotiable:
            negotiable.toggle()
            UserDefaults.standard.set(negotiable, forKey: Prefs.negotiable)
        case .brandNew:
            brandNew.toggle()
            UserDefaults.standard.set(brandNew, forKey: Prefs.brandNew)
        case .brandOfficial:
            brandOfficial.toggle()
            UserDefaults.standard.set(brandOfficial, forKey: Prefs.brandOfficial)
        case .priceRange, .brandSeries:
            break
        }
        Task { await load(reset: true) }
    }

    func isFilterOn(_ key: DirectZoneFilterKey) -> Bool {
        switch key {
        case .freeShipping: return freeShipping
        case .negotiable: return negotiable
        case .brandNew: return brandNew
        case .brandOfficial: return brandOfficial
        case .priceRange, .brandSeries: return false
        }
    }

    func clearFilters() {
        freeShipping = false
        negotiable = false
        brandNew = false
        brandOfficial = false
        searchText = ""
        UserDefaults.standard.set(false, forKey: Prefs.freeShipping)
        UserDefaults.standard.set(false, forKey: Prefs.negotiable)
        UserDefaults.standard.set(false, forKey: Prefs.brandNew)
        UserDefaults.standard.set(false, forKey: Prefs.brandOfficial)
        Task { await load(reset: true) }
    }

    func submitSearch() {
        Task { await load(reset: true) }
    }

    func applyStockEvent(_ ev: ListingStockEvent) {
        guard let idx = items.firstIndex(where: { $0.listingId == ev.listingId }) else { return }
        let old = items[idx]
        items[idx] = DirectZoneListingCard(
            listingId: old.listingId,
            title: old.title,
            cover: old.cover,
            condition: old.condition,
            price: ev.price,
            originalPrice: old.originalPrice,
            freeShipping: old.freeShipping,
            negotiable: old.negotiable,
            sellerType: old.sellerType,
            availableQty: ev.availableQty,
            priceDropped: old.priceDropped,
            status: ev.status,
            slotLabel: old.slotLabel
        )
        if section != .sold && (ev.status == "sold" || ev.availableQty <= 0) {
            items.removeAll { $0.listingId == ev.listingId }
        }
    }

    private func makeQuery(cursor: String?) -> DirectZoneListingsQuery {
        DirectZoneListingsQuery(
            section: section,
            sort: sort,
            cursor: cursor,
            pageSize: DirectZoneConfigDefaults.listingsPageSize,
            q: searchText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            freeShipping: freeShipping ? true : nil,
            negotiable: negotiable ? true : nil,
            brandNew: brandNew ? true : nil,
            brandOfficial: brandOfficial ? true : nil
        )
    }

    private func restorePrefs() {
        if let raw = UserDefaults.standard.string(forKey: Prefs.section),
           let key = DirectZoneSectionKey(rawValue: raw) {
            section = key
            sort = DirectZoneLogic.defaultSort(for: key)
        }
        freeShipping = UserDefaults.standard.bool(forKey: Prefs.freeShipping)
        negotiable = UserDefaults.standard.bool(forKey: Prefs.negotiable)
        brandNew = UserDefaults.standard.bool(forKey: Prefs.brandNew)
        brandOfficial = UserDefaults.standard.bool(forKey: Prefs.brandOfficial)
    }

    private func reconcileSectionAgainstConfig() {
        let keys = Set(enabledSections.map(\.key))
        if !keys.contains(section) {
            section = enabledSections.first?.key ?? .new
            sort = DirectZoneLogic.defaultSort(for: section)
        }
        if !availableSorts.contains(sort) {
            sort = DirectZoneLogic.defaultSort(for: section)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
