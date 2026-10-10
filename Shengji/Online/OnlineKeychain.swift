import Foundation
import Security

/// Where the session token lives between launches.
protocol OnlineTokenStore: Sendable {
    func load() -> String?
    @discardableResult func save(_ token: String) -> Bool
    func delete()
}

/// The session token in the Keychain: a generic password readable after the first unlock (so a
/// notification that arrives while the phone is locked can still refresh).
struct KeychainTokenStore: OnlineTokenStore {
    static let standard = KeychainTokenStore(service: "com.mrellcrane.shengji.online", account: "session")

    let service: String
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let token = String(decoding: data, as: UTF8.self)
        return token.isEmpty ? nil : token
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In memory only (demo scenes, previews and checks): never touches the Keychain.
final class MemoryTokenStore: OnlineTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func load() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    @discardableResult
    func save(_ token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
        return true
    }

    func delete() {
        lock.lock()
        defer { lock.unlock() }
        token = nil
    }
}
