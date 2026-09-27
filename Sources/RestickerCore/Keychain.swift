import Foundation
import Security

/// The repository password lives in a generic password item created by `make set-password`.
public enum Keychain {
    public static let service = "resticker"
    public static let account = "repository-password"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Checks that the item exists without reading its data. An attribute only query
    /// does not trigger the keychain access dialog, so the menu can call this freely.
    public static func hasPassword() -> Bool {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    public static func readPassword() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            LogFile.shared.write("keychain read failed with status \(status)")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
