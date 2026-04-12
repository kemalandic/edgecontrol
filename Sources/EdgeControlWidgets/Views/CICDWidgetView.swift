import SwiftUI
import WidgetKit

struct CICDWidget: Widget {
    let kind = "CICD"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CICDProvider()) { entry in
            CICDWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("CI/CD")
        .description("GitHub Actions workflow runs")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CICDWidgetView: View {
    let entry: CICDEntry

    @Environment(\.widgetFamily) var family

    private var maxRuns: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 3
        case .systemLarge: return 6
        default: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14))
                    .foregroundStyle(WidgetColors.green)
                Text("CI/CD")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
                Spacer()
                if !entry.runs.isEmpty {
                    Text("\(entry.runs.count)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(WidgetColors.textTertiary)
                }
            }

            if entry.runs.isEmpty {
                Spacer()
                Text("No runs")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(entry.runs.prefix(maxRuns))) { run in
                    runRow(run)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .staleOverlay(isStale: entry.isStale, minutesAgo: entry.minutesAgo)
    }

    private func runRow(_ run: WidgetCICDRun) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(run))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(run.repoName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)

                if family != .systemSmall {
                    Text(run.title)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(WidgetColors.textPrimary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(statusLabel(run))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor(run))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor(run).opacity(0.15), in: Capsule())
        }
    }

    private func statusColor(_ run: WidgetCICDRun) -> Color {
        if run.status == "in_progress" { return WidgetColors.yellow }
        switch run.conclusion {
        case "success": return WidgetColors.green
        case "failure": return WidgetColors.red
        case "cancelled": return WidgetColors.textTertiary
        default: return WidgetColors.cyan
        }
    }

    private func statusLabel(_ run: WidgetCICDRun) -> String {
        if run.status == "in_progress" { return "RUN" }
        if run.status == "queued" { return "QUEUE" }
        switch run.conclusion {
        case "success": return "PASS"
        case "failure": return "FAIL"
        case "cancelled": return "SKIP"
        default: return String(run.status.prefix(4)).uppercased()
        }
    }
}
