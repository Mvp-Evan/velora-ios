import Foundation

// MARK: - Future reserve: live / inspect / warehouse (DES-v1.3-14-05 FUT-01～03 / D50)

/// Phase 3: all `fut.*` flags default **off** — no App surfaces for live/inspect/warehouse.
public enum FutureConfigDefaults {
    public static let liveFlagKey = "fut.live"
    public static let inspectFlagKey = "fut.inspect"
    public static let warehouseFlagKey = "fut.warehouse"
    public static let enabledDefault = false

    public static let fulfillmentNormal = "normal"
    public static let fulfillmentInspectThenShip = "inspect_then_ship"
    public static let fulfillmentWarehouse = "warehouse"

    public static let errorFutNotEnabled = "fut_not_enabled"
    public static let errorB18Unmet = "b18_unmet"
}

public enum FutureCopy {
    /// V1.3 must not tease live/inspect/warehouse (design §9).
    public static let hiddenCapabilityHint = "能力未开放"
}
