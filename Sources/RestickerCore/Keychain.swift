import Foundation
import Security

/// What every restic run needs from the keychain, read together right before the run.
public struct RepositorySecrets: Equatable {
    public var password: String
    public var environment: [String: String]

    public init(password: String, environment: [String: String]) {
        self.password = password
        self.environment = environment
    }
}

/// Two generic password items under the same service: the repository password, set from
/// the Settings window's Repository page, and a JSON blob of extra environment variables
/// restic needs for some backends (cloud credentials and the like). Both stay out of
/// `Config`/`UserDefaults` because they are secrets.
public enum Keychain {
    public static let service = "resticker"
    public static let passwordAccount = "repository-password"
    public static let environmentAccount = "environment-variables"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Checks that the item exists without reading its data. An attribute only query
    /// does not trigger the keychain access dialog, so the menu can call this freely.
    public static func hasPassword() -> Bool {
        var query = baseQuery(account: passwordAccount)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// Nil when no password is stored or it cannot be read; the environment is empty when
    /// none is stored.
    public static func readSecrets() -> RepositorySecrets? {
        try? readSecretsResult().get()
    }

    /// Like `readSecrets()`, but tells a denied keychain dialog apart from other failures.
    public static func readSecretsResult() -> Result<RepositorySecrets, KeychainReadError> {
        readData(account: passwordAccount).flatMap { data in
            guard let password = String(data: data, encoding: .utf8) else { return .failure(.failed(errSecDecode)) }
            return .success(RepositorySecrets(password: password, environment: readEnvironment()))
        }
    }

    /// Creates or updates the generic password item. Because the app itself performs this
    /// write, macOS grants it implicit read access to what it just wrote, with no
    /// separate access-control step needed.
    @discardableResult
    public static func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        return save(data, account: passwordAccount)
    }

    /// A missing item is the common case (nothing configured yet), not an error, so it
    /// returns an empty dictionary instead of logging.
    public static func readEnvironment() -> [String: String] {
        guard case .success(let data) = readData(account: environmentAccount) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    @discardableResult
    public static func saveEnvironment(_ variables: [String: String]) -> Bool {
        guard let data = try? JSONEncoder().encode(variables) else { return false }
        return save(data, account: environmentAccount)
    }

    private static func readData(account: String) -> Result<Data, KeychainReadError> {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                LogFile.shared.write("keychain read failed for \(account) with status \(status)")
            }
            return .failure(KeychainReadError(status: status))
        }
        return .success(data)
    }

    @discardableResult
    private static func save(_ data: Data, account: String) -> Bool {
        var status = SecItemUpdate(baseQuery(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = baseQuery(account: account)
            newItem[kSecValueData as String] = data
            status = SecItemAdd(newItem as CFDictionary, nil)
        }
        if status != errSecSuccess {
            LogFile.shared.write("keychain save failed for \(account) with status \(status)")
        }
        return status == errSecSuccess
    }
}

public enum KeychainReadError: Error, Equatable {
    case notFound
    /// The user clicked Deny (or cancelled) in the macOS keychain access dialog. Ad-hoc
    /// signed builds see that dialog again after each update.
    case denied
    case failed(OSStatus)

    init(status: OSStatus) {
        switch status {
        case errSecItemNotFound: self = .notFound
        // Deny in the access dialog gives errSecAuthFailed; closing the password
        // dialog gives errSecUserCanceled.
        case errSecAuthFailed, errSecUserCanceled: self = .denied
        default: self = .failed(status)
        }
    }
}
