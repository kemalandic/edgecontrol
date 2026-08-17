import AppKit
import SwiftUI

/// What the CI/CD widget should render.
///
/// The previous implementation printed "NO RUNS" whether the account was
/// misconfigured, the token was dead, the host was unreachable, or there
/// genuinely were no runs. Each case is distinct here, and each one the user
/// can act on says so.
public enum CICDWidgetState: Equatable {
    /// Nothing configured yet — the only state that asks the user to act.
    case noAccounts
    /// Every account is failing and there is nothing to show.
    case accountError(String, CIError)
    /// Accounts are healthy, there simply are no recent runs.
    case empty
    /// Runs to display, plus how many accounts are currently failing.
    case runs([CIRun], failingAccounts: Int)

    /// Runs win over errors: a partial outage must not blank the dashboard.
    public static func resolve(
        runs: [CIRun],
        accounts: [CIAccount],
        states: [UUID: CIAccountState]
    ) -> CICDWidgetState {
        if accounts.isEmpty { return .noAccounts }

        let failing = accounts.filter { states[$0.id]?.isFailure == true }
        if !runs.isEmpty {
            return .runs(runs, failingAccounts: failing.count)
        }
        if let first = failing.first, case .failed(let error, _) = states[first.id] {
            return .accountError(first.host, error)
        }
        return .empty
    }
}

extension CIError {
    /// Short, non-technical text for the widget.
    var widgetMessage: String {
        switch self {
        case .unauthorized:         return "authentication failed"
        case .rateLimited:          return "rate limited"
        case .unreachable:          return "unreachable"
        case .httpStatus(let code): return "server error \(code)"
        case .decoding:             return "unexpected response"
        }
    }
}

public final class CICDRunsWidget: DashboardWidget {
    public let widgetId = "cicd-runs"
    public let displayName = "CI/CD"
    public let description = "Workflow runs from GitHub and Forgejo/Gitea"
    public let iconName = "arrow.triangle.branch"
    public let category: WidgetCategory = .devtools
    public let requiredServices: Set<ServiceKey> = [.cicd]
    public let supportedSizes = WidgetSizeRange(min: .size(4, 2), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(6, 4)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .green)

    private let service: CICDService

    public init(service: CICDService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CICDRunsWidgetView(service: service)
    }
}

private struct CICDRunsWidgetView: View {
    @ObservedObject var service: CICDService
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }

    /// Resolved once so the header badge and the body cannot disagree.
    private var state: CICDWidgetState {
        CICDWidgetState.resolve(
            runs: service.runs,
            accounts: model.accountStore.accounts,
            states: service.accountStates
        )
    }

    /// Latest run per (account, repository, workflow). The widget is a status
    /// board, not an activity log: re-runs and repeat deployments (Pages runs
    /// all share one title) collapse to the workflow's current state.
    private func latestPerWorkflow(_ runs: [CIRun]) -> [CIRun] {
        var latest: [String: CIRun] = [:]
        for run in runs {
            // run.id is "<accountID>/<repo full name>/<run number>"; dropping
            // the run number yields a key that survives same-named repos in
            // different orgs, which repositoryName (the short name) would not.
            let repoKey = run.id[..<(run.id.lastIndex(of: "/") ?? run.id.endIndex)]
            let key = "\(repoKey)|\(run.workflowName)"
            if let existing = latest[key], existing.startedAt >= run.startedAt { continue }
            latest[key] = run
        }
        return latest.values.sorted { $0.startedAt > $1.startedAt }
    }

    /// The header badge counts what the list shows: distinct workflows, not
    /// raw runs, once collapsing is in effect.
    private var headerCount: Int {
        if case .runs(let runs, _) = state { return latestPerWorkflow(runs).count }
        return service.runs.count
    }

    /// Compact age label ("2h"). Empty for runs whose start time is unknown
    /// (the provider falls back to .distantPast).
    private func relativeAge(_ date: Date) -> String {
        guard date != .distantPast else { return "" }
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            content
        }
        .padding(Theme.sectionSpacing)
        .widgetCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 18 * ts.fontScale))
                .foregroundStyle(Theme.widgetPrimary("cicd-runs", ts: ts, default: .green))
            Text("CI/CD")
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))
            Spacer()
            if case .runs(_, let failing) = state, failing > 0 {
                // One host is down while another works — show the runs we have
                // and flag the rest rather than blanking the widget. Tapping
                // goes where the user can actually see and fix it; a warning
                // with no way to act on it is just noise.
                Text("⚠ \(failing)")
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.accentYellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accentYellow.opacity(0.15), in: Capsule())
                    .touchTappable(id: "cicd-failing-accounts", registry: touchRegistry) {
                        Task { @MainActor in SettingsWindowController.shared.show() }
                    }
            }
            Text("\(headerCount)")
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .noAccounts:
            emptyMessage("NO ACCOUNTS", detail: "Open Settings → CI/CD")
                .touchTappable(id: "cicd-no-accounts", registry: touchRegistry) {
                    Task { @MainActor in SettingsWindowController.shared.show() }
                }

        case .accountError(let host, let error):
            emptyMessage(host.uppercased(), detail: error.widgetMessage)

        case .empty:
            emptyMessage("NO RECENT RUNS", detail: nil)

        case .runs(let runs, _):
            // Every run goes in, however short the widget: the scroll view is
            // what handles overflow now. Capping the rows to whatever fits
            // leaves nothing to scroll to, and the count in the header ends up
            // describing runs the user cannot reach. The service already holds
            // the list to 50.
            TouchScrollView {
                VStack(spacing: 4) {
                    ForEach(latestPerWorkflow(runs)) { run in
                        runRow(run)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func emptyMessage(_ title: String, detail: String?) -> some View {
        Spacer()
        VStack(spacing: 4) {
            Text(title)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            if let detail {
                Text(detail)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
        }
        Spacer()
    }

    private func runRow(_ run: CIRun) -> some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor(run)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(run.repositoryName)
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text3(ts))
                    // Only worth the space once the user has more than one host.
                    if model.accountStore.accounts.count > 1 {
                        Text(run.hostLabel)
                            .font(Theme.label(ts))
                            .foregroundStyle(Theme.text3(ts).opacity(0.6))
                    }
                    // One commit can fan out to several workflows, and some runs
                    // share a constant title ("pages build and deployment"), so
                    // without the workflow name such rows are indistinguishable.
                    Text("· \(run.workflowName)")
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text3(ts).opacity(0.6))
                        .lineLimit(1)
                }
                Text(run.title)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
            }
            Spacer()
            Text(relativeAge(run.startedAt))
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts).opacity(0.7))
            Text(statusLabel(run))
                .font(Theme.label(ts))
                .foregroundStyle(statusColor(run))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(run).opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color.white.opacity(0.02),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .touchTappable(id: "cicd-\(run.id)", registry: touchRegistry) {
            let url = run.url
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
    }

    private func statusColor(_ run: CIRun) -> Color {
        switch run.state {
        case .running, .queued:              return Theme.accentYellow
        case .success:                       return Theme.accentGreen
        case .failure:                       return Theme.accentRed
        case .cancelled, .skipped, .unknown: return Theme.text3(ts)
        }
    }

    private func statusLabel(_ run: CIRun) -> String {
        switch run.state {
        case .running:   return "RUNNING"
        case .queued:    return "QUEUED"
        case .success:   return "PASS"
        case .failure:   return "FAIL"
        case .cancelled: return "CANCEL"
        case .skipped:   return "SKIP"
        case .unknown:   return "—"
        }
    }
}
