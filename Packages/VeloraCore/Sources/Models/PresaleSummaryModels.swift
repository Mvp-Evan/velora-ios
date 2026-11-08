import Foundation

// MARK: - Presale summary / reconcile / list-compare (DES-v1.3-06-04 REL-09/16/17 / D26)
//
// App scope (design 端 / §1): **does not** ship export, batch reconcile, or list-compare UI.
// Brand sellers are pointed to merchant Web「发售与预定单管理」. Full models + APIs live on
// server / merchant Web; this file keeps shared copy, Me-entry keys, and deep-link helpers.

/// Product defaults mirrored for App deep-link / Me entry (design §3 / §5 / §13 / 商家后台Web §5.4).
public enum PresaleSummaryConfigDefaults {
    public static let meEntryKey = "presale_orders"
    public static let meEntryTitle = "预定单"
    public static let meEntryIcon = "list.clipboard"
    /// Merchant SPA path (velora-web `MERCHANT_NAV` /releases/presale).
    public static let merchantPresalePath = "/releases/presale"
    /// Local merchant Vite default (apps/merchant port 5173).
    public static let defaultMerchantWebBaseURL = "http://localhost:5173"
    public static let formulaVersion = "recv_minus_refund_v1"
    public static let exportTTLHours = 24
    public static let exportRowLimit = 100_000
    public static let listCompareMaxRows = 20_000
    public static let listCompareMaxBytes = 10 * 1024 * 1024
    public static let launchGateKey = "launch_gate.presale"
}

// MARK: - Copy (App → merchant Web)

public enum PresaleSummaryCopy {
    /// Primary App redirect message (design: App 不提供导出).
    public static let useMerchantWeb = "预定单管理请在商家后台"
    public static let openMerchantWeb = "打开商家后台"
    public static let pageTitle = "预定单管理"
    public static let hint = "汇总、导出、对账与名单比对仅在商家后台提供"
    public static let unpaidBalanceExpected = "待补款导致的差额为预期差异"
    public static let summaryRefreshing = "汇总刷新中"
}

// MARK: - Empty / stub types (App does not decode merchant APIs)

/// Placeholder so App/VeloraCore share the D26 module name without shipping export payloads.
public struct PresaleSummaryAppStub: Equatable, Sendable {
    public init() {}
}

// MARK: - Deep link

public enum PresaleSummaryLogic {
    /// Build merchant Web URL for「发售与预定单管理」.
    public static func merchantPresaleURL(
        baseURLString: String = PresaleSummaryConfigDefaults.defaultMerchantWebBaseURL,
        path: String = PresaleSummaryConfigDefaults.merchantPresalePath
    ) -> URL? {
        let trimmedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty, var base = URL(string: trimmedBase) else { return nil }
        if base.path.isEmpty || base.path == "/" {
            // OK
        }
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        if trimmedPath == "/" { return base }
        // Preserve base path if any; append merchant path components.
        for comp in trimmedPath.split(separator: "/").map(String.init) where !comp.isEmpty {
            base.appendPathComponent(comp)
        }
        return base
    }

    /// Brand seller Me entry visibility (商家后台Web §5.4): `seller_type=brand` ∧ `can_presale`.
    public static func showsMeEntry(sellerType: String?, canPresale: Bool) -> Bool {
        sellerType == "brand" && canPresale
    }
}
