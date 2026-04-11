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
        ConfigSchemaEntry(key: "sortBy", label: "Sort By", type: .picker, defaultValue: .string("cpu")),
    ]
    public let defaultColors = WidgetColors(primary: .purple, secondary: .cyan)

    private let service: ProcessMonitorService

    public init(service: ProcessMonitorService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        ProcessListWidgetView(service: service, isCompact: size.height <= 3)
    }
}

private struct ProcessListWidgetView: View {
    @ObservedObject var service: ProcessMonitorService
    @Environment(\.themeSettings) private var ts
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            WidgetHeader(title: "TOP PROCESSES", color: Theme.widgetPrimary("process-list", ts: ts, default: .purple))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            HStack {
                Text("APP")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU")
                    .frame(width: 70, alignment: .trailing)
                if !isCompact {
                    Text("MEM")
                        .frame(width: 70, alignment: .trailing)
                }
            }
            .font(Theme.label(ts))
            .foregroundStyle(Theme.text3(ts))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider().background(Theme.border(ts))

            if service.topProcesses.isEmpty {
                Text("Loading...")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxCount = isCompact ? 4 : 8
                ForEach(Array(service.topProcesses.prefix(maxCount))) { proc in
                    processRow(proc)
                    if proc.id != service.topProcesses.prefix(maxCount).last?.id {
                        Divider().background(Theme.border(ts)).padding(.leading, 50)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .widgetCard()
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

            if !isCompact {
                Text(String(format: "%.0f MB", proc.memoryMB))
                    .font(Theme.body(ts))
                    .foregroundStyle(proc.memoryMB > 1024 ? Theme.accentOrange : Theme.text2(ts))
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
