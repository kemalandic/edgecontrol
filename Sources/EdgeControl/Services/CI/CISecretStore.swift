import Foundation
import Security

public protocol CISecretStore: Sendable {
    func read(_ key: String) -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String)
}

/// Stores tokens in the macOS Keychain.
///
/// The main app is not sandboxed, so this needs no special entitlement.
/// Contributors building with their own Apple Developer Team ID will see the
/// Keychain access prompt on first run after re-signing — expected behaviour.
public struct KeychainSecretStore: CISecretStore {
    private let service: String

    public init(service: String = "ai.pakslab.edgecontrol.cicd") {
        self.service = service
    }

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: String) throws {
        // Delete first: SecItemUpdate cannot create, and SecItemAdd fails on
        // duplicates.
        SecItemDelete(query(key) as CFDictionary)
        var attributes = query(key)
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CIError.decoding("Keychain write failed (OSStatus \(status))")
        }
    }

    public func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}

/// Test double.
///
/// Lives in Sources so the test target can use it without touching the real
/// Keychain, which would prompt for access and behave differently on machines
/// signed with a different team.
public final class InMemorySecretStore: CISecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func read(_ key: String) -> String? {
        lock.withLock { storage[key] }
    }

    public func write(_ value: String, for key: String) throws {
        lock.withLock { storage[key] = value }
    }

    public func delete(_ key: String) {
        lock.withLock { storage[key] = nil }
    }
}
