import AppKit
import SwiftUI

public final class PrintersWidget: DashboardWidget {
    public let widgetId = "printers"
    public let displayName = "Printers"
    public let description = "Status and ink levels of the printers on your network"
    public let iconName = "printer"
    public let category: WidgetCategory = .network
    public let requiredServices: Set<ServiceKey> = [.printers]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(12, 6))
    public let defaultSize = WidgetSize.size(4, 2)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(
            key: "printer", label: "Printer", type: .printerPicker, defaultValue: .string(""),
            help: "All Printers lists every printer on the network. Pick one to give it the whole widget.")
    ]
    /// Marks a printer at work; ink keeps the printer's own colors.
    public let defaultColors = WidgetColors(primary: .cyan)

    private let service: PrinterService

    public init(service: PrinterService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        PrintersWidgetView(service: service, selectedId: config.string("printer"))
    }
}

private struct PrintersWidgetView: View {
    @ObservedObject var service: PrinterService
    let selectedId: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    /// Keeps touch zone ids apart when the widget is placed twice.
    @State private var instance = String(UUID().uuidString.prefix(8))

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }
    private var accent: Color { Theme.widgetPrimary("printers", ts: ts, default: .cyan) }
    private var gap: CGFloat { max(4, CGFloat(ts.widgetGap)) }

    private var shown: [PrinterService.Printer] {
        selectedId.isEmpty ? service.printers : service.printers.filter { $0.id == selectedId }
    }

    var body: some View {
        Group {
            let printers = shown
            if printers.isEmpty {
                emptyState
            } else if printers.count == 1 {
                detail(printers[0])
            } else {
                TouchScrollView {
                    VStack(spacing: gap) {
                        ForEach(printers) { row($0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.widgetPadding)
        .widgetCard()
    }

    // MARK: - One printer

    private func detail(_ printer: PrinterService.Printer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusDot(printer)
                VStack(alignment: .leading, spacing: 2) {
                    Text(printer.name)
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .lineLimit(1)
                    statusText(printer)
                        .font(Theme.label(ts))
                }
                Spacer(minLength: 0)
            }
            if let supplies = printer.status?.supplies, !supplies.isEmpty {
                HStack(alignment: .bottom, spacing: gap) {
                    ForEach(supplies) { InkTank(supply: $0, compact: false) }
                }
                .frame(maxHeight: .infinity)
            } else {
                Text(printer.status == nil ? "Asking the printer…" : "This printer doesn't report ink levels.")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .touchTappable(id: "printers-\(instance)-\(printer.id)", registry: touchRegistry) {
            Task { @MainActor in openWebPage(printer) }
        }
    }

    // MARK: - Several printers

    private func row(_ printer: PrinterService.Printer) -> some View {
        HStack(spacing: 10) {
            statusDot(printer)
            VStack(alignment: .leading, spacing: 2) {
                Text(printer.name)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
                statusText(printer)
                    .font(Theme.caption(ts))
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(printer.status?.supplies ?? []) { InkTank(supply: $0, compact: true) }
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous))
        .touchTappable(id: "printers-\(instance)-\(printer.id)", registry: touchRegistry) {
            Task { @MainActor in openWebPage(printer) }
        }
    }

    // MARK: - Status

    /// What the printer is doing, or its most pressing problem.
    private func status(_ printer: PrinterService.Printer) -> (text: String, color: Color) {
        if let problem = printer.problem { return (problem, Theme.text3(ts)) }
        guard let status = printer.status else { return ("Connecting…", Theme.text3(ts)) }
        if let top = status.topProblem {
            switch top.severity {
            case .error: return (top.text, Theme.accentRed)
            case .warning: return (top.text, Theme.accentYellow)
            case .report: break
            }
        }
        switch status.state {
        case .printing:
            let waiting = status.queuedJobs > 1 ? " · \(status.queuedJobs - 1) waiting" : ""
            return ("Printing" + waiting, accent)
        case .idle: return ("Ready", Theme.accentGreen)
        case .stopped: return (status.message ?? "Stopped", Theme.accentRed)
        case .unknown: return ("Unknown", Theme.text3(ts))
        }
    }

    private func statusText(_ printer: PrinterService.Printer) -> some View {
        let (text, color) = status(printer)
        return Text(text).foregroundStyle(color).lineLimit(1)
    }

    @ViewBuilder
    private func statusDot(_ printer: PrinterService.Printer) -> some View {
        let color = status(printer).color
        if printer.problem == nil, printer.status?.state == .printing {
            PulsingDot(color: color, size: 8)
        } else {
            Circle().fill(color).frame(width: 8, height: 8).frame(width: 16, height: 16)
        }
    }

    private func openWebPage(_ printer: PrinterService.Printer) {
        guard let page = printer.status?.webPage ?? printer.endpoint.flatMap({ URL(string: "http://\($0.host)/") })
        else { return }
        NSWorkspace.shared.open(page)
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "printer")
                .font(.system(size: 30 * ts.fontScale))
                .foregroundStyle(Theme.text3(ts))
            if !selectedId.isEmpty {
                Text("PRINTER NOT FOUND")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                Text(PrinterStatus.displayName(selectedId) + " hasn't answered on the network")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(2)
            } else {
                Text(service.searching ? "LOOKING FOR PRINTERS" : "NO PRINTERS FOUND")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                Text("Printers on your network appear here")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One ink tank or toner cartridge, filled to its level in its own color.
private struct InkTank: View {
    let supply: PrinterStatus.Supply
    let compact: Bool

    @Environment(\.themeSettings) private var ts

    private var fraction: CGFloat {
        switch supply.level {
        case .percent(let percent): return CGFloat(percent) / 100
        case .someRemaining: return 0.5
        case .unknown: return 0
        }
    }

    private var label: String {
        switch supply.level {
        case .percent(let percent): return "\(percent)%"
        case .someRemaining: return "OK"
        case .unknown: return "?"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let shape = RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous)
                ZStack(alignment: .bottom) {
                    shape.fill(Color.white.opacity(0.08))
                    shape.fill(fill)
                        .frame(height: geo.size.height * fraction)
                        .opacity(supply.level == .someRemaining ? 0.5 : 1)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(supply.isLow ? Theme.accentRed : Theme.border(ts), lineWidth: 1))
            }
            .frame(maxWidth: compact ? 10 : 44)
            if !compact {
                Text(label)
                    .font(Theme.caption(ts))
                    .foregroundStyle(supply.isLow ? Theme.accentRed : Theme.text2(ts))
                    .monospacedDigit()
                Text(supply.name)
                    .font(Theme.micro(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .help("\(supply.name): \(label)")
    }

    /// The printer's ink color. Black ink on a black dashboard would vanish,
    /// so the darkest colors are lifted to charcoal.
    private var fill: AnyShapeStyle {
        let colors = supply.colors.map { rgb -> Color in
            let luminance = 0.2126 * rgb.red + 0.7152 * rgb.green + 0.0722 * rgb.blue
            return luminance < 0.12 ? Color(white: 0.32) : Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        switch colors.count {
        case 0: return AnyShapeStyle(Theme.text3(ts))
        case 1: return AnyShapeStyle(colors[0])
        default: return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        }
    }
}
