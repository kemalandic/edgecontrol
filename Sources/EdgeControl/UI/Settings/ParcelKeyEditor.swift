import AppKit
import SwiftUI

/// The Parcel API key, kept in the Keychain rather than the layout, and
/// shared by every Parcel widget since it belongs to the account. Saving
/// asks Parcel straight away, so the line underneath says whether the key
/// works.
struct ParcelKeyEditor: View {
    let entry: ConfigSchemaEntry
    @ObservedObject var service: ParcelService
    let accent: Color

    @State private var key = ""
    @State private var keychainError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                SecureField(service.hasKey ? "Saved" : "Paste your key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit(save)
            }
            HStack(spacing: 8) {
                statusLine
                Spacer()
                Button("Get a Key") {
                    if let url = URL(string: "https://web.parcelapp.net") { NSWorkspace.shared.open(url) }
                }
                if service.hasKey {
                    Button("Remove") { service.removeKey() }
                }
                Button("Save", action: save)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .tint(accent)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    private func save() {
        keychainError = false
        do {
            try service.setKey(key)
            key = ""
        } catch {
            keychainError = true
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let (text, color): (String, Color) = {
            if keychainError { return ("Couldn't save the key to the Keychain", Theme.accentRed) }
            switch service.problem {
            case .needsKey: return ("Needs Parcel Premium", Theme.textTertiary)
            case .keyRefused(let reason): return (reason ?? "Parcel refused the key", Theme.accentRed)
            case .rateLimited: return ("Parcel asked for a pause", Theme.accentYellow)
            case .unreachable: return ("Can't reach Parcel", Theme.accentYellow)
            case .failed(let reason): return (reason, Theme.accentRed)
            case nil:
                let count = service.lists.values.map(\.deliveries.count).max()
                guard let count else { return ("Checking…", Theme.textTertiary) }
                return ("Connected · \(count) \(count == 1 ? "delivery" : "deliveries")", Theme.accentGreen)
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
