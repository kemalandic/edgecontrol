import AppKit
import SwiftUI

public final class CICDRunsWidget: DashboardWidget {
    public let widgetId = "cicd-runs"
    public let displayName = "CI/CD"
    public let description = "GitHub Actions workflow runs with status indicators"
    public let iconName = "arrow.triangle.branch"
    public let category: WidgetCategory = .devtools
    public let requiredServices: Set<ServiceKey> = [.github]
    public let supportedSizes = WidgetSizeRange(min: .size(4, 2), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(6, 4)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .green)

    private let service: GitHubService

    public init(service: GitHubService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CICDRunsWidgetView(service: service, maxRuns: size.height <= 2 ? 2 : size.height <= 3 ? 3 : 6)
    }
}

private struct CICDRunsWidgetView: View {
    @ObservedObject var service: GitHubService
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    let maxRuns: Int

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18 * ts.fontScale))
                    .foregroundStyle(Theme.widgetPrimary("cicd-runs", ts: ts, default: .green))
                Text("CI/CD")
                    .font(Theme.title(ts))
                    .foregroundStyle(Theme.text2(ts))
                Spacer()
                Text("\(service.runs.count)")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
            }

            if service.runs.isEmpty {
                Spacer()
                Text("NO RUNS")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(Array(service.runs.prefix(maxRuns))) { run in
                            runRow(run)
                        }
                    }
                }
            }
        }
        .padding(Theme.sectionSpacing)
        .widgetCard()
    }

    private func runRow(_ run: WorkflowRun) -> some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor(run)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.repoName)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text3(ts))
                Text(run.displayTitle)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
            }
            Spacer()
            Text(statusLabel(run))
                .font(Theme.label(ts))
                .foregroundStyle(statusColor(run))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(run).opacity(0.15), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .touchTappable(id: "cicd-\(run.id)", registry: touchRegistry) {
            if let url = URL(string: run.url) {
                Task { @MainActor in NSWorkspace.shared.open(url) }
            }
        }
    }

    private func statusColor(_ run: WorkflowRun) -> Color {
        if run.status == "in_progress" { return Theme.accentYellow }
        switch run.conclusion {
        case "success": return Theme.accentGreen
        case "failure": return Theme.accentRed
        case "cancelled": return Theme.text3(ts)
        default: return Theme.widgetPrimary("cicd-runs", ts: ts, default: .green)
        }
    }

    private func statusLabel(_ run: WorkflowRun) -> String {
        if run.status == "in_progress" { return "RUNNING" }
        if run.status == "queued" { return "QUEUED" }
        switch run.conclusion {
        case "success": return "PASS"
        case "failure": return "FAIL"
        case "cancelled": return "CANCEL"
        default: return run.status.uppercased()
        }
    }
}
