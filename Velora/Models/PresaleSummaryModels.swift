import Foundation

// MARK: - Presale summary / reconcile / list-compare (DES-v1.3-06-04 REL-09/16/17 / D26 — app mirror of VeloraCore)
//
// App scope (design 端 / §1): **does not** ship export, batch reconcile, or list-compare UI.
// Brand sellers are pointed to merchant Web「发售与预定单管理」.

/// Product defaults mirrored for App deep-link / Me entry (design §3 / §5 / §13 / 商家后台Web §5.4).
enum PresaleSummaryConfigDefaults {
    static let meEntryKey = "presale_orders"
    static let meEntryTitle = "预定单"
    static let meEntryIcon = "list.clipboard"
    /// Merchant SPA path (velora-web `MERCHANT_NAV` /releases/presale).
    static let merchantPresalePath = "/releases/presale"
    /// Local merchant Vite default (apps/merchant port 5173).
    static let defaultMerchantWebBaseURL = "http://localhost:5173"
    static let formulaVersion = "recv_minus_refund_v1"
    static let exportTTLHours = 24
    static let exportRowLimit = 100_000
    static let listCompareMaxRows = 20_000
    static let listCompareMaxBytes = 10 * 1024 * 1024
    static let launchGateKey = "launch_gate.presale"
}

// MARK: - Copy (App → merchant Web)

enum PresaleSummaryCopy {
    /// Primary App redirect message (design: App 不提供导出).
    static let useMerchantWeb = "预定单管理请在商家后台"
    static let openMerchantWeb = "打开商家后台"
    static let pageTitle = "预定单管理"
    static let hint = "汇总、导出、对账与名单比对仅在商家后台提供"
    static let unpaidBalanceExpected = "待补款导致的差额为预期差异"
    static let summaryRefreshing = "汇总刷新中"
}

// MARK: - Empty / stub types (App does not decode merchant APIs)

struct PresaleSummaryAppStub: Equatable, Sendable {
    init() {}
}

// MARK: - Deep link

enum PresaleSummaryLogic {
    /// Build merchant Web URL for「发售与预定单管理」.
    static func merchantPresaleURL(
        baseURLString: String = PresaleSummaryConfigDefaults.defaultMerchantWebBaseURL,
        path: String = PresaleSummaryConfigDefaults.merchantPresalePath
    ) -> URL? {
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, var base = URL(string: trimmedBase) else { return nil }
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        if trimmedPath == "/" { return base }
        for comp in trimmedPath.split(separator: "/").map(String.init) where !comp.isEmpty {
            base.appendPathComponent(comp)
        }
        return base
    }

    /// Brand seller Me entry visibility (商家后台Web §5.4): `seller_type=brand` ∧ `can_presale`.
    static func showsMeEntry(sellerType: String?, canPresale: Bool) -> Bool {
        sellerType == "brand" && canPresale
    }
}
