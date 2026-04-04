import SwiftUI

/// Page 3: Full-screen temperature monitoring with history graphs and per-core breakdown
struct TemperaturePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: CPU + GPU gauges with history
            VStack(spacing: 10) {
                // CPU Temperature
                tempCard(
                    title: "CPU",
                    icon: "cpu",
                    temp: model.smcService.cpuTemperature,
                    history: model.smcService.cpuTempHistory,
                    color: Theme.accentCyan,
                    maxTemp: 110
                )
                .frame(maxHeight: .infinity)

                // GPU Temperature
                tempCard(
                    title: "GPU",
                    icon: "gpu",
                    temp: model.smcService.gpuTemperature,
                    history: model.smcService.gpuTempHistory,
                    color: Theme.accentGreen,
                    maxTemp: 110
                )
                .frame(maxHeight: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity)

            divider()

            // CENTER: Per-core CPU visualization
            perCorePanel()
                .frame(maxWidth: .infinity)

            divider()

            // RIGHT: SSD + Memory + Fans + Thermal
            VStack(spacing: 10) {
                // SSD
                tempCard(
                    title: "SSD",
                    icon: "internaldrive",
                    temp: model.smcService.ssdTemperature,
                    history: model.smcService.ssdTempHistory,
                    color: Theme.accentBlue,
                    maxTemp: 80
                )
                .frame(maxHeight: .infinity)

                // Memory
                tempCard(
                    title: "MEMORY",
                    icon: "memorychip",
                    temp: model.smcService.memoryTemperature,
                    history: model.smcService.memTempHistory,
                    color: Theme.accentPurple,
                    maxTemp: 90
                )
                .frame(maxHeight: .infinity)

                // Fan speeds + Thermal
                HStack(spacing: 8) {
                    // Fans
                    if model.smcService.fanCount > 0 {
                        ForEach(0..<model.smcService.fanCount, id: \.self) { i in
                            let rpm = i < model.smcService.fanSpeeds.count ? model.smcService.fanSpeeds[i] : 0
                            fanChip(index: i, rpm: rpm)
                        }
                    }

                    // Thermal state
                    if let m = model.systemMetrics {
                        thermalChip(state: m.thermalState)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Temperature Card (gauge + mini graph)

    private func tempCard(title: String, icon: String, temp: Double?, history: [Double], color: Color, maxTemp: Double) -> some View {
        HStack(spacing: 14) {
            // Gauge
            if let temp {
                RadialGaugeView(
                    value: temp,
                    maxValue: maxTemp,
                    label: title,
                    displayValue: String(format: "%.0f°", temp),
                    unit: tempStatus(temp),
                    accentColor: color
                )
                .frame(width: 150)
            } else {
                VStack {
                    Image(systemName: "thermometer.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text("N/A")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(width: 150)
            }

            // History graph
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let temp {
                        Text(String(format: "%.1f°C", temp))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                            .monospacedDigit()
                    }
                }

                if !history.isEmpty {
                    TempGraphView(history: history, color: color, maxTemp: maxTemp)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Per-Core Panel

    private func perCorePanel() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentCyan).frame(width: 10, height: 10)
                Text("PER-CORE")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(model.smcService.cpuCoreTemps.count) CORES")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)

            if !model.smcService.cpuCoreTemps.isEmpty {
                // Temperature bar grid
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(model.smcService.cpuCoreTemps) { core in
                            coreBar(core)
                        }
                    }
                }
                .padding(.horizontal, 12)

                // Per-core CPU usage bars (if available)
                if !model.metricsPerCore.isEmpty {
                    Divider().background(Theme.borderSubtle).padding(.horizontal, 12)

                    HStack(spacing: 8) {
                        Circle().fill(Theme.accentPurple).frame(width: 10, height: 10)
                        Text("CPU USAGE")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(model.metricsPerCore) { core in
                                usageBar(core)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
            } else {
                VStack(spacing: 8) {
                    Text("LOADING CORE DATA")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    ProgressView().tint(Theme.accentCyan)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }

    // MARK: - Core Temperature Bar

    private func coreBar(_ core: CoreTemp) -> some View {
        HStack(spacing: 8) {
            Text(core.label)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(core.isPerformance ? Theme.accentCyan : Theme.accentGreen)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(tempBarColor(core.temperature))
                        .frame(width: geo.size.width * min(core.temperature / 110, 1))
                }
            }
            .frame(height: 14)

            Text(String(format: "%.0f°", core.temperature))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(tempBarColor(core.temperature))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - CPU Usage Bar

    private func usageBar(_ core: CoreUsage) -> some View {
        HStack(spacing: 8) {
            Text("C\(core.id)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.accentPurple)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(usageBarColor(core.usage))
                        .frame(width: geo.size.width * min(core.usage / 100, 1))
                }
            }
            .frame(height: 14)

            Text(String(format: "%.0f%%", core.usage))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(usageBarColor(core.usage))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    // MARK: - Fan & Thermal Chips

    private func fanChip(index: Int, rpm: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "fan.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accentCyan)
                .rotationEffect(.degrees(rpm > 0 ? 360 : 0))
                .animation(rpm > 0 ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: rpm > 0)
            VStack(alignment: .leading, spacing: 1) {
                Text("FAN \(index + 1)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(String(format: "%.0f RPM", rpm))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func thermalChip(state: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: thermalIcon(state))
                .font(.system(size: 16))
                .foregroundStyle(thermalColor(state))
            Text(state.uppercased())
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(thermalColor(state))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(thermalColor(state).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(thermalColor(state).opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func divider() -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            .frame(width: 1).padding(.vertical, 20)
    }

    private func tempStatus(_ temp: Double) -> String {
        if temp < 40 { return "Idle" }
        if temp < 60 { return "Normal" }
        if temp < 80 { return "Warm" }
        if temp < 95 { return "Hot" }
        return "Critical"
    }

    private func tempBarColor(_ temp: Double) -> Color {
        if temp < 50 { return Theme.accentCyan }
        if temp < 65 { return Theme.accentGreen }
        if temp < 80 { return Theme.accentYellow }
        if temp < 95 { return Theme.accentOrange }
        return Theme.accentRed
    }

    private func usageBarColor(_ usage: Double) -> Color {
        if usage < 30 { return Theme.accentCyan }
        if usage < 60 { return Theme.accentGreen }
        if usage < 85 { return Theme.accentYellow }
        return Theme.accentOrange
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

    private func thermalIcon(_ state: String) -> String {
        switch state.lowercased() {
        case "nominal": return "checkmark.shield.fill"
        case "fair": return "exclamationmark.triangle"
        case "serious": return "flame"
        case "critical": return "flame.fill"
        default: return "thermometer.medium"
        }
    }
}

// MARK: - Temperature History Graph (absolute scale, not normalized)

struct TempGraphView: View {
    let history: [Double]
    let color: Color
    let maxTemp: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .bottomLeading) {
                // Grid lines at 25°C intervals
                ForEach([25.0, 50.0, 75.0, 100.0], id: \.self) { level in
                    if level < maxTemp {
                        Path { p in
                            let y = h * (1 - level / maxTemp)
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }

                if history.count > 1 {
                    // Area
                    Path { path in
                        let step = w / CGFloat(max(history.count - 1, 1))
                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, val) in history.enumerated() {
                            let x = CGFloat(i) * step
                            let y = h * (1 - min(val / maxTemp, 1))
                            if i == 0 { path.addLine(to: CGPoint(x: x, y: y)) }
                            else {
                                let px = CGFloat(i-1) * step
                                let py = h * (1 - min(history[i-1] / maxTemp, 1))
                                let mx = (px + x) / 2
                                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: mx, y: py), control2: CGPoint(x: mx, y: y))
                            }
                        }
                        path.addLine(to: CGPoint(x: CGFloat(history.count-1) * step, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                    // Line
                    Path { path in
                        let step = w / CGFloat(max(history.count - 1, 1))
                        for (i, val) in history.enumerated() {
                            let x = CGFloat(i) * step
                            let y = h * (1 - min(val / maxTemp, 1))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else {
                                let px = CGFloat(i-1) * step
                                let py = h * (1 - min(history[i-1] / maxTemp, 1))
                                let mx = (px + x) / 2
                                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: mx, y: py), control2: CGPoint(x: mx, y: y))
                            }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
    }
}
