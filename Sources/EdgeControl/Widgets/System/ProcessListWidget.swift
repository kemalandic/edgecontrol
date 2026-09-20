import AppKit
import SwiftUI

public final class ProcessListWidget: DashboardWidget {
    public let widgetId = "process-list"
    public let displayName = "Process List"
    public let description = "Top processes sorted by CPU or memory usage"
    public let iconName = "list.bullet.rectangle"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.process]
    public let supportedSizes = WidgetSizeRange(min: .size(4, 3), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(6, 4)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "sortBy", label: "Sort By", type: .picker, defaultValue: .string("cpu"), options: ["cpu", "memory"]),
        // "auto" fills whatever height the widget has; a number pins the row
        // count and scrolls past it.
        ConfigSchemaEntry(key: "rows", label: "Rows", type: .picker, defaultValue: .string("auto"), options: ["auto", "4", "6", "8", "10", "12", "16"]),
    ]
    public let defaultColors = WidgetColors(primary: .purple, secondary: .cyan)

    private let service: ProcessMonitorService

    public init(service: ProcessMonitorService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        ProcessListWidgetView(
            service: service,
            sortByMemory: config.string("sortBy", default: "cpu") == "memory",
            fixedRows: Int(config.string("rows", default: "auto"))
        )
    }
}

private struct ProcessListWidgetView: View {
    @ObservedObject var service: ProcessMonitorService
    @Environment(\.themeSettings) private var ts
    @EnvironmentObject private var model: AppModel
    // Tapping a column header re-sorts live, overriding the configured
    // default for this on-screen session; tap again to flip direction.
    @State private var tappedSort: (memory: Bool, ascending: Bool)?
    let sortByMemory: Bool
    /// nil = fit rows to the widget height; a number pins the count.
    let fixedRows: Int?

    // Row = 26pt icon + 2x8pt vertical padding + 1pt divider.
    private let rowHeight: CGFloat = 43

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(title: "TOP PROCESSES", color: Theme.widgetPrimary("process-list", ts: ts, default: .purple))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack {
                Text("APP")
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortHeader("CPU", memory: false)
                sortHeader("MEM", memory: true)
            }
            .font(Theme.label(ts))
            .foregroundStyle(Theme.text3(ts))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().background(Theme.border(ts))

            GeometryReader { geo in
                if service.topProcesses.isEmpty {
                    Text("Loading...")
                        .font(Theme.body(ts))
                        .foregroundStyle(Theme.text3(ts))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let fitCount = min(max(Int(geo.size.height / rowHeight), 3), 16)
                    let maxCount = fixedRows ?? fitCount
                    let memSort = tappedSort?.memory ?? sortByMemory
                    let ascending = tappedSort?.ascending ?? false
                    let ranked = service.topProcesses.sorted {
                        let (a, b) = memSort ? ($0.memoryMB, $1.memoryMB) : ($0.cpuPercent, $1.cpuPercent)
                        return ascending ? a < b : a > b
                    }
                    let visible = Array(ranked.prefix(maxCount))
                    // Scrolls only when a pinned row count exceeds the height.
                    TouchScrollView {
                        VStack(spacing: 0) {
                            ForEach(visible) { proc in
                                processRow(proc)
                                if proc.id != visible.last?.id {
                                    Divider().background(Theme.border(ts)).padding(.leading, 50)
                                }
                            }
                        }
                    }
                }
            }
        }
        .widgetCard()
    }

    private func sortHeader(_ label: String, memory: Bool) -> some View {
        let memSort = tappedSort?.memory ?? sortByMemory
        let ascending = tappedSort?.ascending ?? false
        let active = memSort == memory
        return Text(active ? label + (ascending ? " ▲" : " ▼") : label)
            .foregroundStyle(active ? Theme.text1(ts) : Theme.text3(ts))
            .frame(width: 70, alignment: .trailing)
            .touchTappable(id: "proc-sort-\(label)", registry: model.touchService.zoneRegistry) {
                Task { @MainActor in
                    if active {
                        tappedSort = (memory, !ascending)
                    } else {
                        tappedSort = (memory, false)
                    }
                }
            }
    }

    private func processRow(_ proc: ProcessInfo_EC) -> some View {
        HStack(spacing: 10) {
            if let icon = proc.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 18 * ts.fontScale))
                    .foregroundStyle(Theme.text3(ts))
                    .frame(width: 26, height: 26)
            }

            Text(proc.name)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text1(ts))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", proc.cpuPercent))
                .font(Theme.body(ts))
                .foregroundStyle(proc.cpuPercent > 50 ? Theme.accentOrange : Theme.widgetSecondary("process-list", ts: ts, default: .cyan) ?? Theme.accentCyan)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(String(format: "%.0f MB", proc.memoryMB))
                .font(Theme.body(ts))
                .foregroundStyle(proc.memoryMB > 1024 ? Theme.accentOrange : Theme.text2(ts))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
