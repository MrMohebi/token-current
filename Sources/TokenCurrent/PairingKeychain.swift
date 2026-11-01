#if os(macOS)
import Foundation
import Security

enum PairingKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.mrmohebi.TokenCurrent.mesh", kSecAttrAccount as String: account]
    }
    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ value: String, account: String) throws {
        let q = query(account)
        let data = Data(value.utf8)
        let result = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw KeyError.save }
        } else if result != errSecSuccess { throw KeyError.save }
    }
    static func remove(_ account: String) { SecItemDelete(query(account) as CFDictionary) }
    enum KeyError: Error, LocalizedError {
        case save
        var errorDescription: String? { "Could not save the pairing token in Keychain." }
    }
}
#endif
