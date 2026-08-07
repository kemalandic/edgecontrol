import SwiftUI

/// Offered once, on first launch after the update, when no accounts exist.
///
/// Copying a credential out of another tool's keyring is not something to do
/// silently, which is why this is a prompt rather than an automatic migration.
struct CICDImportPrompt: View {
    let candidates: [DiscoveredCredential]
    let onAdd: ([DiscoveredCredential]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CI/CD accounts found").font(.headline)
            Text("EdgeControl can import these from your existing CLI tools. Tokens are stored in your macOS Keychain.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(candidates, id: \.host) { candidate in
                Toggle(isOn: binding(for: candidate)) {
                    HStack {
                        Text(candidate.host)
                        Spacer()
                        Text("via \(candidate.source)").foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Button("Not now") { dismiss() }
                Spacer()
                Button("Add selected") {
                    onAdd(candidates.filter { selected.contains($0.host) })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { selected = Set(candidates.map(\.host)) }
    }

    private func binding(for candidate: DiscoveredCredential) -> Binding<Bool> {
        Binding(
            get: { selected.contains(candidate.host) },
            set: { isOn in
                if isOn { selected.insert(candidate.host) } else { selected.remove(candidate.host) }
            }
        )
    }
}
