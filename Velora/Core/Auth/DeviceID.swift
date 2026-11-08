import Foundation

/// Stable install-scoped device id stored in Keychain (DES-v1.3-01 SMS / login / rate buckets).
enum DeviceID {
    private static let key = "device_id"

    static var current: String {
        if let existing = KeychainStore.get(key), !existing.isEmpty { return existing }
        let id = UUID().uuidString.lowercased()
        KeychainStore.set(id, for: key)
        return id
    }
}
