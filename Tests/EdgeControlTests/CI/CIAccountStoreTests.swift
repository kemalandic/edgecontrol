import XCTest
@testable import EdgeControl

@MainActor
final class CIAccountStoreTests: XCTestCase {
    private func makeAccount(
        kind: CIProviderKind = .github,
        host: String = "github.com",
        username: String = "octo"
    ) -> CIAccount {
        CIAccount(
            id: UUID(),
            kind: kind,
            host: host,
            apiBaseURL: URL(string: "https://api.github.com")!,
            username: username
        )
    }

    func testAddPersistsAccountWithoutToken() throws {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        let store = CIAccountStore(defaults: suite, secrets: secrets)

        let account = makeAccount(kind: .forgejo, host: "git.example.dev", username: "someone")
        try store.add(account, token: "secret-token")

        XCTAssertEqual(store.accounts.map(\.host), ["git.example.dev"])
        XCTAssertEqual(secrets.read(account.id.uuidString), "secret-token")

        // The token must not appear anywhere in the persisted account list.
        let raw = suite.data(forKey: "cicd.accounts") ?? Data()
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("secret-token"))
    }

    func testAccountsSurviveReload() throws {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        let account = makeAccount()
        try CIAccountStore(defaults: suite, secrets: secrets).add(account, token: "t")

        let reloaded = CIAccountStore(defaults: suite, secrets: secrets)
        XCTAssertEqual(reloaded.accounts, [account])
        XCTAssertEqual(reloaded.token(for: account), "t")
    }

    func testRemoveDeletesTokenToo() throws {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let secrets = InMemorySecretStore()
        let store = CIAccountStore(defaults: suite, secrets: secrets)

        let account = makeAccount()
        try store.add(account, token: "t")
        store.remove(account)

        XCTAssertTrue(store.accounts.isEmpty)
        XCTAssertNil(secrets.read(account.id.uuidString))
    }

    func testAPIBaseURLDerivation() {
        XCTAssertEqual(
            CIAccount.apiBaseURL(forKind: .github, webURL: URL(string: "https://github.com")!),
            URL(string: "https://api.github.com")
        )
        XCTAssertEqual(
            CIAccount.apiBaseURL(forKind: .forgejo, webURL: URL(string: "https://git.example.dev")!),
            URL(string: "https://git.example.dev/api/v1")
        )
        // GitHub Enterprise uses a path-based API root, not api.<host>.
        XCTAssertEqual(
            CIAccount.apiBaseURL(forKind: .github, webURL: URL(string: "https://ghe.corp.test")!),
            URL(string: "https://ghe.corp.test/api/v3")
        )
    }
}
