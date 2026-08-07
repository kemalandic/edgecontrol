import SwiftUI

/// Add-account flow: kind → host → token → Validate → Save.
///
/// Validation runs against the host before anything is persisted, so a dead
/// token never reaches the Keychain.
struct CICDAccountSheet: View {
    let prefill: DiscoveredCredential?
    let onSave: (CIAccount, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: CIProviderKind = .github
    @State private var urlText = "https://github.com"
    @State private var token = ""
    @State private var validating = false
    @State private var validated: CIIdentity?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add CI/CD account").font(.headline)

            Picker("Host type", selection: $kind) {
                ForEach(CIProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .onChange(of: kind) { _, newKind in
                // Reset the identity: a token validated against one host says
                // nothing about another.
                validated = nil
                errorText = nil
                if newKind == .github, urlText.isEmpty || urlText == "https://" {
                    urlText = "https://github.com"
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Server URL", text: $urlText)
                Text(kind == .github
                     ? "github.com, or your GitHub Enterprise address."
                     : "The address you use in the browser, e.g. https://git.example.dev")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SecureField("Access token", text: $token)
                .onChange(of: token) { _, _ in validated = nil }

            if let validated {
                Label("Signed in as \(validated.login)", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(validated == nil ? "Validate" : "Save") {
                    if validated == nil { validate() } else { save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validating || token.isEmpty || urlText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear(perform: applyPrefill)
    }

    private func applyPrefill() {
        guard let prefill else { return }
        kind = prefill.kind
        urlText = prefill.webURL.absoluteString
        token = prefill.token
    }

    private func validate() {
        guard let webURL = URL(string: urlText), webURL.host != nil else {
            errorText = "That is not a valid URL."
            return
        }
        validating = true
        errorText = nil

        let account = CIAccount(
            id: UUID(),
            kind: kind,
            host: webURL.host ?? urlText,
            apiBaseURL: CIAccount.apiBaseURL(forKind: kind, webURL: webURL),
            username: ""
        )

        Task { @MainActor in
            defer { validating = false }
            do {
                validated = try await CICDSettingsView.makeProvider(account, token: token).validate()
            } catch let error as CIError {
                errorText = error.widgetMessage
            } catch {
                errorText = "Could not reach the server."
            }
        }
    }

    private func save() {
        guard let webURL = URL(string: urlText), let identity = validated else { return }
        let account = CIAccount(
            id: UUID(),
            kind: kind,
            host: webURL.host ?? urlText,
            apiBaseURL: CIAccount.apiBaseURL(forKind: kind, webURL: webURL),
            username: identity.login
        )
        onSave(account, token)
        dismiss()
    }
}
