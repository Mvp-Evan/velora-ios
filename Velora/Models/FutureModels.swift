import Foundation

// MARK: - Future reserve (DES-v1.3-14-05 FUT-01～03 / D50 — app mirror of VeloraCore)

enum FutureConfigDefaults {
    static let liveFlagKey = "fut.live"
    static let inspectFlagKey = "fut.inspect"
    static let warehouseFlagKey = "fut.warehouse"
    static let enabledDefault = false

    static let fulfillmentNormal = "normal"
    static let fulfillmentInspectThenShip = "inspect_then_ship"
    static let fulfillmentWarehouse = "warehouse"

    static let errorFutNotEnabled = "fut_not_enabled"
    static let errorB18Unmet = "b18_unmet"
}

enum FutureCopy {
    static let hiddenCapabilityHint = "能力未开放"
}
