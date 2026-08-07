import XCTest
@testable import EdgeControl

/// Stands in for the real CLIs. Keyed by "executable arg1 arg2".
private struct FakeRunner: CommandRunner {
    let outputs: [String: String]
    let available: Set<String>

    func run(_ executable: String, _ arguments: [String], stdin: String?) throws -> String {
        guard available.contains(executable) else {
            throw CIError.decoding("not found: \(executable)")
        }
        let key = ([executable] + arguments).joined(separator: " ")
        guard let output = outputs[key] else {
            throw CIError.decoding("no stub for: \(key)")
        }
        return output
    }
}

final class CredentialImporterTests: XCTestCase {
    func testImportsGitHubTokenFromGh() {
        let runner = FakeRunner(
            outputs: ["gh auth token": "gho_exampletoken"],
            available: ["gh"]
        )
        let found = CredentialImporter(runner: runner).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].kind, .github)
        XCTAssertEqual(found[0].host, "github.com")
        XCTAssertEqual(found[0].token, "gho_exampletoken")
        XCTAssertEqual(found[0].source, "gh")
    }

    func testImportsForgejoLoginsFromTea() {
        let list = """
        [
          {"name":"work","url":"https://git.example.dev","ssh_host":"git.example.dev","user":"someone","default":"true"}
        ]
        """
        let helper = """
        protocol=https
        host=git.example.dev
        username=someone
        password=tea_token_value
        """
        let runner = FakeRunner(
            outputs: [
                "tea login list --output json": list,
                "tea login helper get": helper,
            ],
            available: ["tea"]
        )
        let found = CredentialImporter(runner: runner).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].kind, .forgejo)
        XCTAssertEqual(found[0].host, "git.example.dev")
        XCTAssertEqual(found[0].username, "someone")
        XCTAssertEqual(found[0].token, "tea_token_value")
        XCTAssertEqual(found[0].source, "tea")
    }

    /// A missing CLI is an ordinary outcome, not an error. The importer must
    /// return an empty list so the UI can hide the button.
    func testMissingCLIsYieldNothing() {
        let runner = FakeRunner(outputs: [:], available: [])
        XCTAssertTrue(CredentialImporter(runner: runner).discover().isEmpty)
    }

    /// gh prints nothing when logged out; an empty token must not become an
    /// account that then fails every request with 401.
    func testEmptyGhTokenIsIgnored() {
        let runner = FakeRunner(outputs: ["gh auth token": ""], available: ["gh"])
        XCTAssertTrue(CredentialImporter(runner: runner).discover().isEmpty)
    }

    func testCredentialFieldParsing() {
        let output = "protocol=https\nhost=h\nusername=u\npassword=p=q"
        XCTAssertEqual(CredentialImporter.credentialField("username", in: output), "u")
        // Values may contain '=' — only the first one separates key from value.
        XCTAssertEqual(CredentialImporter.credentialField("password", in: output), "p=q")
        XCTAssertNil(CredentialImporter.credentialField("missing", in: output))
    }
}
