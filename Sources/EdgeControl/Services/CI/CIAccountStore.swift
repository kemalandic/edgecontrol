import Combine
import Foundation

/// Owns the configured accounts: the list in UserDefaults, the tokens in the
/// Keychain.
@MainActor
public final class CIAccountStore: ObservableObject {
    private static let defaultsKey = "cicd.accounts"

    @Published public private(set) var accounts: [CIAccount] = []

    private let defaults: UserDefaults
    private let secrets: CISecretStore

    public init(
        defaults: UserDefaults = .standard,
        secrets: CISecretStore = KeychainSecretStore()
    ) {
        self.defaults = defaults
        self.secrets = secrets
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([CIAccount].self, from: data) {
            accounts = decoded
        }
    }

    public func add(_ account: CIAccount, token: String) throws {
        try secrets.write(token, for: account.id.uuidString)
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        persist()
    }

    public func remove(_ account: CIAccount) {
        secrets.delete(account.id.uuidString)
        accounts.removeAll { $0.id == account.id }
        persist()
    }

    public func token(for account: CIAccount) -> String? {
        secrets.read(account.id.uuidString)
    }

    /// Replaces a token in place — used when a rotated CLI token is re-imported.
    public func updateToken(_ token: String, for account: CIAccount) throws {
        try secrets.write(token, for: account.id.uuidString)
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(accounts), forKey: Self.defaultsKey)
        } catch {
            // The token is already in the Keychain at this point; losing the
            // account list would orphan it.
            AppLog.cicd.error(
                "encoding CI accounts failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
