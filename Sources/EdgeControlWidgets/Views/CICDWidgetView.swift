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
        .description("Workflow runs from GitHub and Forgejo/Gitea")
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
                // The note explains *why* there is nothing — no accounts, a dead
                // token, an unreachable host, or genuinely no runs. Falling back
                // to "No runs" only when the app has not told us.
                Text(entry.statusNote ?? "No runs")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                    .multilineTextAlignment(.center)
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

    /// True when the snapshot carries runs from more than one host.
    private var multipleHosts: Bool {
        Set(entry.runs.map(\.hostLabel)).count > 1
    }

    private func runRow(_ run: WidgetCICDRun) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor(run))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(run.repoName)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetColors.textTertiary)
                    // Without this, runs from three hosts sit in one list with
                    // no way to tell them apart. Skipped on the small family,
                    // where there is no room, and when a single host is in play.
                    if family != .systemSmall, multipleHosts {
                        Text(run.hostLabel)
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(WidgetColors.textTertiary.opacity(0.65))
                            .lineLimit(1)
                    }
                }

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
        switch run.state {
        case .running, .queued:              return WidgetColors.yellow
        case .success:                       return WidgetColors.green
        case .failure:                       return WidgetColors.red
        case .cancelled, .skipped, .unknown: return WidgetColors.textTertiary
        }
    }

    private func statusLabel(_ run: WidgetCICDRun) -> String {
        switch run.state {
        case .running:   return "RUN"
        case .queued:    return "QUEUE"
        case .success:   return "PASS"
        case .failure:   return "FAIL"
        case .cancelled: return "CANCEL"
        case .skipped:   return "SKIP"
        case .unknown:   return "—"
        }
    }
}
