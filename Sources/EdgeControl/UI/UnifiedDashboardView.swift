import SwiftUI

/// iCUE-style unified dashboard for the XENEON EDGE 2560×720 display.
public struct UnifiedDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var history = MetricsHistory()

    public init() {}

    private var metrics: SystemMetrics? {
        model.systemMetrics
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.03, blue: 0.05),
                        Color(red: 0.05, green: 0.05, blue: 0.08),
                        Color(red: 0.03, green: 0.04, blue: 0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if let m = metrics {
                    HStack(spacing: 0) {
                        // LEFT: 4 gauges vertically stacked in 2 columns
                        gaugesPanel(m, height: geo.size.height)
                            .frame(width: geo.size.width * 0.28)

                        dividerLine()

                        // CENTER: Dual graphs stacked + info strip
                        centerPanel(m, height: geo.size.height)
                            .frame(width: geo.size.width * 0.44)

                        dividerLine()

                        // RIGHT: Clock + system specs
                        rightPanel(m, height: geo.size.height)
                            .frame(width: geo.size.width * 0.28)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Theme.accentCyan)
                            .scaleEffect(1.5)
                        Text("COLLECTING SYSTEM DATA")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .onChange(of: model.systemMetrics) { _, newMetrics in
            if let m = newMetrics {
                history.record(cpu: m.cpuLoadPercent, memory: m.memoryUsedPercent)
            }
        }
        .background(WindowAccessor { window in
            WindowPlacement.configure(
                window,
                display: model.selectedDisplay,
                kioskMode: model.settings.kioskMode,
                isDevKit: model.isDevKitMode
            )
        })
        .onAppear {
            model.startIfNeeded()
        }
    }

    private func dividerLine() -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 20)
    }

    // MARK: - LEFT: Gauge Panel (2×2 grid, fits in height)

    private func gaugesPanel(_ m: SystemMetrics, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Circle().fill(Theme.accentCyan).frame(width: 10, height: 10)
                Text("MONITOR")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                thermalBadge(m.thermalState)
            }
            .padding(.horizontal, 16)

            // 2×2 gauge grid — constrained to available height
            let gaugeSize = min((height - 80) / 2 - 12, 280)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                RadialGaugeView(
                    value: m.cpuLoadPercent, maxValue: 100,
                    label: "CPU",
                    displayValue: String(format: "%.0f%%", m.cpuLoadPercent),
                    unit: abbreviate(m.cpuBrand),
                    accentColor: Theme.accentCyan
                )
                .frame(height: gaugeSize)

                RadialGaugeView(
                    value: m.memoryUsedPercent, maxValue: 100,
                    label: "MEMORY",
                    displayValue: String(format: "%.1f", m.memoryUsedGB),
                    unit: String(format: "/ %.0f GB", m.memoryTotalGB),
                    accentColor: Theme.accentPurple
                )
                .frame(height: gaugeSize)

                RadialGaugeView(
                    value: m.storageUsedPercent, maxValue: 100,
                    label: "STORAGE",
                    displayValue: String(format: "%.0f%%", m.storageUsedPercent),
                    unit: String(format: "%.0f/%.0f GB", m.storageUsedGB, m.storageTotalGB),
                    accentColor: Theme.accentBlue
                )
                .frame(height: gaugeSize)

                RadialGaugeView(
                    value: m.memoryPressurePercent, maxValue: 100,
                    label: "PRESSURE",
                    displayValue: String(format: "%.0f%%", m.memoryPressurePercent),
                    unit: String(format: "Swap %.0fMB", m.swapUsedMB),
                    accentColor: Theme.accentOrange
                )
                .frame(height: gaugeSize)
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }

    // MARK: - CENTER: Graphs + System Info

    private func centerPanel(_ m: SystemMetrics, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            // CPU graph — takes equal share of available space
            graphCard(
                title: "CPU USAGE",
                currentValue: String(format: "%.1f%%", m.cpuLoadPercent),
                history: history.cpuHistory,
                color: Theme.accentCyan
            )
            .frame(maxHeight: .infinity)

            // Memory graph — takes equal share of available space
            graphCard(
                title: "MEMORY",
                currentValue: String(format: "%.1f / %.0f GB", m.memoryUsedGB, m.memoryTotalGB),
                history: history.memoryHistory,
                color: Theme.accentPurple
            )
            .frame(maxHeight: .infinity)

            // System info strip — fixed height at bottom
            HStack(spacing: 8) {
                infoChip(icon: "cpu", label: "CPU", value: abbreviate(m.cpuBrand))
                infoChip(icon: "gpu", label: "GPU", value: abbreviate(m.gpuName))
                infoChip(icon: "point.3.filled.connected.trianglepath.dotted", label: "CORES", value: "\(m.performanceCoreCount)P + \(m.efficiencyCoreCount)E")
                infoChip(icon: "clock.arrow.circlepath", label: "UPTIME", value: formatUptime(m.uptimeSeconds))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    // MARK: - RIGHT: Clock + Details

    private func rightPanel(_ m: SystemMetrics, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            // Clock — compact
            ClockWidgetView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                )
                .fixedSize(horizontal: false, vertical: true)

            // System specs list — scrollable if needed
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    specRow(icon: "cpu", label: "Processor", value: m.cpuBrand, color: Theme.accentCyan, isFirst: true)
                    specRow(icon: "gpu", label: "Graphics", value: m.gpuName, color: Theme.accentGreen)
                    specRow(icon: "memorychip", label: "Memory", value: String(format: "%.1f / %.0f GB (%.0f%%)", m.memoryUsedGB, m.memoryTotalGB, m.memoryUsedPercent), color: Theme.accentPurple)
                    specRow(icon: "internaldrive", label: "Storage", value: String(format: "%.0f / %.0f GB (%.0f%%)", m.storageUsedGB, m.storageTotalGB, m.storageUsedPercent), color: Theme.accentBlue)
                    specRow(icon: "arrow.triangle.swap", label: "Swap", value: String(format: "%.0f MB used", m.swapUsedMB), color: Theme.accentOrange)
                    specRow(icon: "thermometer.medium", label: "Thermal", value: m.thermalState, color: thermalColor(m.thermalState), isLast: true)
                }
            }
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )
            .frame(maxHeight: .infinity)

            // Core breakdown — fixed at bottom
            HStack(spacing: 8) {
                coreChip(label: "P-CORES", value: "\(m.performanceCoreCount)", color: Theme.accentCyan)
                coreChip(label: "E-CORES", value: "\(m.efficiencyCoreCount)", color: Theme.accentGreen)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    // MARK: - Component Helpers

    private func thermalBadge(_ state: String) -> some View {
        Text(state.uppercased())
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(thermalColor(state))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(thermalColor(state).opacity(0.12), in: Capsule())
    }

    private func graphCard(title: String, currentValue: String, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(currentValue)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .fixedSize(horizontal: false, vertical: true)

            HistoryGraphView(history: history, color: color)
                .frame(maxHeight: .infinity)
        }
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func infoChip(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accentCyan.opacity(0.7))
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func specRow(icon: String, label: String, value: String, color: Color, isFirst: Bool = false, isLast: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)
                    .padding(.leading, 50)
            }
        }
    }

    private func coreChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }

    private func thermalColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "nominal": return Theme.accentGreen
        case "fair": return Theme.accentYellow
        case "serious": return Theme.accentOrange
        case "critical": return Theme.accentRed
        default: return Theme.textSecondary
        }
    }

    private func abbreviate(_ name: String) -> String {
        if name.contains("Apple M") {
            return name.replacingOccurrences(of: "Apple ", with: "")
        }
        if name.count > 20 {
            return String(name.prefix(18)) + "…"
        }
        return name
    }

    private func formatUptime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 24 {
            return "\(hours / 24)d \(hours % 24)h"
        }
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Metrics History (shared state for graphs)

@MainActor
final class MetricsHistory: ObservableObject {
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    private let maxPoints = 120

    func record(cpu: Double, memory: Double) {
        cpuHistory.append(cpu / 100)
        memoryHistory.append(memory / 100)
        if cpuHistory.count > maxPoints { cpuHistory.removeFirst() }
        if memoryHistory.count > maxPoints { memoryHistory.removeFirst() }
    }
}

// MARK: - History Graph (proper time-series with 120-point buffer)

struct HistoryGraphView: View {
    let history: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottomLeading) {
                // Grid lines + labels
                ForEach([0.25, 0.50, 0.75], id: \.self) { level in
                    Path { p in
                        let y = h * (1 - level)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                if history.count > 1 {
                    // Area fill
                    areaPath(in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.30), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Line
                    linePath(in: geo.size)
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                    // Current value dot
                    if let last = history.last {
                        let x = w
                        let y = h * (1 - last)
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .shadow(color: color.opacity(0.6), radius: 4)
                            .position(x: x, y: y)
                    }
                }

                // Bottom baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            guard history.count > 1 else { return }
            let stepX = size.width / CGFloat(max(history.count - 1, 1))

            for (i, val) in history.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - val)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    let px = CGFloat(i - 1) * stepX
                    let py = size.height * (1 - history[i - 1])
                    let mx = (px + x) / 2
                    path.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: mx, y: py),
                                  control2: CGPoint(x: mx, y: y))
                }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        Path { path in
            guard history.count > 1 else { return }
            let stepX = size.width / CGFloat(max(history.count - 1, 1))

            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, val) in history.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - val)
                if i == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let px = CGFloat(i - 1) * stepX
                    let py = size.height * (1 - history[i - 1])
                    let mx = (px + x) / 2
                    path.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: mx, y: py),
                                  control2: CGPoint(x: mx, y: y))
                }
            }
            path.addLine(to: CGPoint(x: CGFloat(history.count - 1) * stepX, y: size.height))
            path.closeSubpath()
        }
    }
}
