import AppKit
import SwiftUI

/// Shows `CICDImportPrompt` once, in its own window.
///
/// The app builds windows with AppKit rather than a SwiftUI `Scene`, so there
/// is no view to attach a `.sheet` to at launch.
@MainActor
final class CICDImportPromptController {
    private static let shownKey = "cicd.importPromptShown"

    /// True when the process was launched by XCTest rather than by the user.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private var window: NSWindow?

    /// Offers CLI-discovered accounts once, and only when none are configured.
    ///
    /// The flag is set when the prompt is *shown*, not when accounts are added,
    /// so declining "Not now" does not re-prompt on every launch.
    func offerIfNeeded(model: AppModel) {
        // The test suite launches this app as its host, which would fire the
        // one-time prompt and burn it before the user ever sees it.
        guard !Self.isRunningTests else { return }
        guard !UserDefaults.standard.bool(forKey: Self.shownKey) else { return }
        guard model.accountStore.accounts.isEmpty else { return }

        // Spawning `gh`/`tea` is cheap but not free; keep it off the first frame.
        Task.detached(priority: .utility) {
            let found = CredentialImporter().discover()
            guard !found.isEmpty else { return }
            await MainActor.run { self.present(found, model: model) }
        }
    }

    private func present(_ candidates: [DiscoveredCredential], model: AppModel) {
        UserDefaults.standard.set(true, forKey: Self.shownKey)

        let view = CICDImportPrompt(candidates: candidates) { chosen in
            for candidate in chosen {
                let account = CIAccount(
                    id: UUID(),
                    kind: candidate.kind,
                    host: candidate.host,
                    apiBaseURL: CIAccount.apiBaseURL(
                        forKind: candidate.kind, webURL: candidate.webURL
                    ),
                    username: candidate.username
                )
                Task { @MainActor in
                    // Resolve the identity before storing, exactly as the
                    // Settings import does. `gh auth token` gives no username,
                    // and an unvalidated token would be stored even if dead.
                    var resolved = account
                    do {
                        let identity = try await CICDSettingsView
                            .makeProvider(account, token: candidate.token)
                            .validate()
                        resolved.username = identity.login
                    } catch {
                        AppLog.cicd.error(
                            "importing \(candidate.host, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                        )
                        return
                    }
                    try? model.accountStore.add(resolved, token: candidate.token)
                    model.cicdService.start()
                }
            }
        }

        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "CI/CD accounts found"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        win.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
        win.makeKeyAndOrderFront(nil)
        window = win
    }
}
