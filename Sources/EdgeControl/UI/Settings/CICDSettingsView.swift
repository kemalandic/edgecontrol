import SwiftUI

/// Accounts, discovery and refresh settings for the CI/CD widget.
///
/// Accounts are app-level rather than widget-level configuration because both
/// the in-app widget and the sandboxed desktop widget depend on them.
struct CICDSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts

    @State private var showingAddSheet = false
    @State private var pinnedDraft = ""
    @State private var hiddenDraft = ""
    @State private var pinnedHost = ""
    @State private var hiddenHost = ""
    @State private var importError: String?

    private var service: CICDService { model.cicdService }

    /// Repositories currently contributing runs to the widget, ready to hide.
    /// run.id is "<accountID>/<owner>/<name>/<run number>".
    private var shownRepositories: [CIRepositoryRef] {
        let hidden = service.settings.hiddenRepositories
        var seen = Set<CIRepositoryRef>()
        var result: [CIRepositoryRef] = []
        for run in service.runs {
            let parts = run.id.split(separator: "/")
            guard parts.count >= 4,
                  let accountID = UUID(uuidString: String(parts[0])),
                  let host = store.accounts.first(where: { $0.id == accountID })?.host else { continue }
            let ref = CIRepositoryRef(host: host, fullName: parts.dropFirst().dropLast().joined(separator: "/"))
            if !hidden.contains(ref), seen.insert(ref).inserted { result.append(ref) }
        }
        return result.sorted()
    }
    private var store: CIAccountStore { model.accountStore }

    private var cliAvailable: Bool {
        ProcessCommandRunner.locate("gh") != nil || ProcessCommandRunner.locate("tea") != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountsSection
                discoverySection
                refreshSection
            }
            .padding(Theme.sectionSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showingAddSheet) {
            CICDAccountSheet(prefill: nil) { account, token in
                try? store.add(account, token: token)
                service.start()
            }
        }
    }

    // MARK: - Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))

            if store.accounts.isEmpty {
                Text("No accounts yet. Add one to see workflow runs.")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
            }

            ForEach(store.accounts) { account in
                accountRow(account)
            }

            if let importError {
                Text(importError)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.accentRed)
            }

            HStack(spacing: 8) {
                Button("Add account…") { showingAddSheet = true }
                // Hidden rather than disabled: a button that can never work is
                // worse than no button.
                if cliAvailable {
                    Button("Import from CLI") { importFromCLI() }
                }
            }
        }
    }

    private func accountRow(_ account: CIAccount) -> some View {
        HStack(spacing: 10) {
            // Pulsing while a sync is in flight; a static dot otherwise, so the
            // motion means something rather than decorating every row.
            if case .syncing = service.accountStates[account.id] {
                PulsingDot(color: Theme.accentYellow, size: 8)
            } else {
                Circle()
                    .fill(healthColor(for: account))
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(account.host)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                healthDetail(for: account)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            Spacer()
            // Only hosts that publish a quota get a figure; Forgejo does not,
            // and an absent quota must not read as an exhausted one.
            if let limit = service.rateLimits[account.id] {
                Text(Self.quotaText(limit))
                    .font(Theme.label(ts))
                    .foregroundStyle(limit.isLow ? Theme.accentYellow : Theme.text3(ts))
            }
            Text(account.username)
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts))
            Button("Remove") {
                store.remove(account)
                service.start()
            }
        }
        .padding(.vertical, 4)
    }

    /// `now` is a parameter so the result does not depend on how long the
    /// caller took to get here — truncating a live interval turned an exact
    /// 42 minutes into "41m", and 59 seconds into "0m".
    static func quotaText(_ limit: CIRateLimit, now: Date = Date()) -> String {
        var text = "\(limit.remaining)/\(limit.limit)"
        if let reset = limit.resetsAt {
            let minutes = Int((reset.timeIntervalSince(now) / 60).rounded())
            text += minutes > 0 ? " · resets in \(minutes)m" : " · resetting"
        }
        return text
    }

    /// Imports every discovered credential that is not already configured,
    /// resolving each identity before storing so a dead token never persists.
    private func importFromCLI() {
        importError = nil
        let candidates = CredentialImporter().discover()
            .filter { candidate in !store.accounts.contains { $0.host == candidate.host } }

        guard !candidates.isEmpty else {
            importError = "Nothing new to import."
            return
        }

        for candidate in candidates {
            let account = CIAccount(
                id: UUID(),
                kind: candidate.kind,
                host: candidate.host,
                apiBaseURL: CIAccount.apiBaseURL(forKind: candidate.kind, webURL: candidate.webURL),
                username: candidate.username
            )
            Task { @MainActor in
                let provider = Self.makeProvider(account, token: candidate.token)
                guard let identity = try? await provider.validate() else {
                    importError = "\(candidate.host): token was rejected."
                    return
                }
                var resolved = account
                resolved.username = identity.login
                try? store.add(resolved, token: candidate.token)
                service.start()
            }
        }
    }

    static func makeProvider(_ account: CIAccount, token: String) -> CIProvider {
        switch account.kind {
        case .github:
            return GitHubProvider(
                accountID: account.id, hostLabel: account.host,
                apiBaseURL: account.apiBaseURL, token: token,
                transport: URLSessionTransport()
            )
        case .forgejo:
            return ForgejoProvider(
                accountID: account.id, hostLabel: account.host,
                apiBaseURL: account.apiBaseURL, token: token,
                transport: URLSessionTransport()
            )
        }
    }

    private func healthColor(for account: CIAccount) -> Color {
        switch service.accountStates[account.id] {
        case .ok:      return Theme.accentGreen
        case .failed:  return Theme.accentRed
        case .syncing: return Theme.accentYellow
        default:       return Theme.text3(ts)
        }
    }

    /// `.ok` renders through `TimeAgoText` because the age has to keep
    /// counting: a plain formatted string is computed once and then sits there
    /// claiming "2m ago" long after it stopped being true.
    @ViewBuilder
    private func healthDetail(for account: CIAccount) -> some View {
        switch service.accountStates[account.id] {
        case .ok(let date):
            HStack(spacing: 3) {
                Text("Synced")
                TimeAgoText(date)
            }
        case .failed(let error, _):
            Text(error.widgetMessage)
        case .syncing:
            Text("Syncing…")
        default:
            Text("Not started")
        }
    }

    // MARK: - Discovery

    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discovery")
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))
            Picker("Activity window", selection: Binding(
                get: { service.settings.activityWindowDays },
                set: { service.settings.activityWindowDays = $0 }
            )) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            .frame(maxWidth: 260)
            Text("Repositories with a workflow run and activity inside this window are shown automatically.")
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts))

            repositoryList(
                title: "Pinned",
                hint: "Always shown, whatever the activity window says.",
                symbol: "pin.fill",
                entries: service.settings.pinnedRepositories,
                add: { service.settings.pinnedRepositories.insert($0) },
                remove: { service.settings.pinnedRepositories.remove($0) },
                host: $pinnedHost,
                text: $pinnedDraft
            )

            repositoryList(
                title: "Hidden",
                hint: "Never shown, and never polled.",
                symbol: "eye.slash",
                entries: service.settings.hiddenRepositories,
                add: { service.settings.hiddenRepositories.insert($0) },
                remove: { service.settings.hiddenRepositories.remove($0) },
                host: $hiddenHost,
                text: $hiddenDraft
            )

            // The typed entry above requires knowing the exact owner/name;
            // this menu offers exactly what the widget is showing right now.
            if !shownRepositories.isEmpty {
                Menu {
                    ForEach(shownRepositories, id: \.self) { ref in
                        Button(ref.displayName) {
                            service.settings.hiddenRepositories.insert(ref)
                        }
                    }
                } label: {
                    Label("Hide a repository currently shown…", systemImage: "eye.slash")
                        .font(Theme.label(ts))
                }
                .frame(maxWidth: 320)
            }
        }
    }

    /// Shared editor for the pinned and hidden lists.
    ///
    /// The host comes from a picker rather than free text: an entry that names
    /// no host was previously applied to every account, so a Forgejo repository
    /// was polled against github.com as well.
    @ViewBuilder
    private func repositoryList(
        title: String,
        hint: String,
        symbol: String,
        entries: Set<CIRepositoryRef>,
        add: @escaping (CIRepositoryRef) -> Void,
        remove: @escaping (CIRepositoryRef) -> Void,
        host: Binding<String>,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text2(ts))
            Text(hint)
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts))

            ForEach(entries.sorted(), id: \.self) { entry in
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.text3(ts))
                    Text(entry.displayName)
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text1(ts))
                    Spacer()
                    Button("Remove") { remove(entry) }
                }
            }

            if store.accounts.isEmpty {
                Text("Add an account first.")
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text3(ts))
            } else {
                HStack(spacing: 6) {
                    Picker("", selection: host) {
                        ForEach(store.accounts) { account in
                            Text(account.host).tag(account.host)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170)

                    TextField("owner/name", text: text)
                        .frame(maxWidth: 190)

                    Button("Add") {
                        let value = text.wrappedValue.trimmingCharacters(in: .whitespaces)
                        // "owner/name" is what the API and the widget both key
                        // on; anything else would silently never match.
                        guard value.split(separator: "/").count == 2 else { return }
                        let chosen = host.wrappedValue.isEmpty
                            ? (store.accounts.first?.host ?? "")
                            : host.wrappedValue
                        guard !chosen.isEmpty else { return }
                        add(CIRepositoryRef(host: chosen, fullName: value))
                        text.wrappedValue = ""
                    }
                    .disabled(text.wrappedValue.split(separator: "/").count != 2)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Refresh

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Refresh")
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))
            Picker("Interval", selection: Binding(
                get: { Int(service.settings.pollInterval) },
                set: { service.settings.pollInterval = TimeInterval($0) }
            )) {
                Text("15s").tag(15)
                Text("30s").tag(30)
                Text("60s").tag(60)
                Text("120s").tag(120)
            }
            .frame(maxWidth: 260)
            Text("An account that starts failing backs off on its own and returns to this interval once it recovers.")
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts))
        }
    }
}
