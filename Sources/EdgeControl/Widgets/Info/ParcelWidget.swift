import AppKit
import SwiftUI

public final class ParcelWidget: DashboardWidget {
    public let widgetId = "parcel"
    public let displayName = "Parcel"
    public let description = "Deliveries on their way, from the Parcel app (needs Parcel Premium)"
    public let iconName = "shippingbox"
    public let category: WidgetCategory = .info
    public let requiredServices: Set<ServiceKey> = [.parcel]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(12, 6))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(
            key: "apiKey", label: "API Key", type: .parcelKey, defaultValue: .string(""),
            help:
                "From web.parcelapp.net, with Parcel Premium. It's kept in the Keychain and shared by every Parcel widget."
        ),
        ConfigSchemaEntry(
            key: "show", label: "Show", type: .picker, defaultValue: .string("active"),
            options: ParcelService.Filter.allCases.map(\.rawValue),
            help:
                "Active is everything on its way. Recent is Parcel's recent list, which also has deliveries that have just arrived."
        ),
        ConfigSchemaEntry(
            key: "showUpdates", label: "Latest Update", type: .toggle, defaultValue: .bool(true),
            help: "The carrier's most recent scan under each delivery."),
    ]
    public let defaultColors = WidgetColors(primary: .blue)
    /// Marks deliveries in transit in the theme's accent, like the rest of
    /// the dashboard's highlights; the other states keep their own colors.
    public let defaultsToAccentColor = true

    private let service: ParcelService

    public init(service: ParcelService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        ParcelWidgetView(
            service: service,
            filter: ParcelService.Filter(rawValue: config.string("show", default: "active")) ?? .active,
            showUpdates: config.bool("showUpdates", default: true))
    }
}

private struct ParcelWidgetView: View {
    @ObservedObject var service: ParcelService
    let filter: ParcelService.Filter
    let showUpdates: Bool

    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    /// Keeps touch zone ids apart when the widget is placed twice.
    @State private var instance = String(UUID().uuidString.prefix(8))
    @State private var watching: ParcelService.Filter?

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }
    private var accent: Color { Theme.widgetPrimaryOrAccent("parcel", ts: ts) }
    private var gap: CGFloat { CGFloat(ts.widgetGap) }
    private var scale: CGFloat { CGFloat(ts.fontScale) }

    var body: some View {
        let now = Date()
        Group {
            if let deliveries = service.deliveries(filter), deliveries.count > 1 {
                list(deliveries, now: now)
            } else {
                VStack(spacing: max(6, gap)) {
                    if let deliveries = service.deliveries(filter) {
                        if let only = deliveries.first {
                            detail(only, now: now)
                        } else {
                            emptyState
                        }
                        if let note = staleNote { noteText(note) }
                    } else {
                        problemState
                    }
                }
                .padding(Theme.widgetPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetCard()
        .onAppear(perform: syncWatching)
        .onChange(of: filter) { syncWatching() }
        .onDisappear {
            if let watching { service.unwatch(watching) }
            watching = nil
        }
    }

    private func syncWatching() {
        guard watching != filter else { return }
        if let watching { service.unwatch(watching) }
        service.watch(filter)
        watching = filter
    }

    // MARK: - Several deliveries

    /// The rows are cards of their own, so they sit inside the widget the
    /// way widgets sit on the page: inset by the theme's gap, and edge to
    /// edge when the gap is nothing.
    private func list(_ deliveries: [ParcelDelivery], now: Date) -> some View {
        VStack(spacing: 0) {
            TouchScrollView {
                VStack(spacing: gap) {
                    ForEach(deliveries) { row($0, now: now) }
                }
            }
            if let note = staleNote {
                noteText(note)
                    .padding(.horizontal, Theme.widgetPadding)
                    .padding(.vertical, 8)
            }
        }
        .padding(gap)
    }

    private func row(_ delivery: ParcelDelivery, now: Date) -> some View {
        HStack(spacing: 12) {
            badge(delivery.status, size: 30 * scale)
            VStack(alignment: .leading, spacing: 3) {
                Text(delivery.title)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
                Text(statusLine(delivery))
                    .font(Theme.caption(ts))
                    .foregroundStyle(look(delivery.status).color)
                    .lineLimit(1)
                if showUpdates, let update = updateLine(delivery.latestEvent, now: now) {
                    Text(update)
                        .font(Theme.micro(ts))
                        .foregroundStyle(Theme.text3(ts))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            arrival(delivery, now: now, large: false)
        }
        // Each row is drawn like a widget card, with a card's padding, so
        // rows sit the way the theme's widgets do: apart by its gap, or
        // edge to edge.
        .padding(.horizontal, Theme.widgetPadding)
        .padding(.vertical, 12)
        .background(Theme.cardBg(ts), in: RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous)
                .strokeBorder(Theme.border(ts), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .touchTappable(id: "parcel-\(instance)-\(delivery.id)", registry: touchRegistry) {
            Task { @MainActor in openParcel() }
        }
    }

    // MARK: - One delivery

    private func detail(_ delivery: ParcelDelivery, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                badge(delivery.status, size: 40 * scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(delivery.title)
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .lineLimit(1)
                    Text(statusLine(delivery))
                        .font(Theme.label(ts))
                        .foregroundStyle(look(delivery.status).color)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                arrival(delivery, now: now, large: true)
            }
            if showUpdates, !delivery.events.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(delivery.events.prefix(4).enumerated()), id: \.offset) { index, event in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(index == 0 ? look(delivery.status).color : Theme.text3(ts))
                                .frame(width: 7 * scale, height: 7 * scale)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.text.isEmpty ? "Update" : event.text)
                                    .font(Theme.caption(ts))
                                    .foregroundStyle(index == 0 ? Theme.text1(ts) : Theme.text2(ts))
                                    .lineLimit(1)
                                if let place = placeAndTime(event, now: now) {
                                    Text(place)
                                        .font(Theme.micro(ts))
                                        .foregroundStyle(Theme.text3(ts))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .touchTappable(id: "parcel-\(instance)-\(delivery.id)", registry: touchRegistry) {
            Task { @MainActor in openParcel() }
        }
    }

    // MARK: - Pieces

    private struct Look {
        let symbol: String
        let text: String
        let color: Color
    }

    private func look(_ status: ParcelDelivery.Status) -> Look {
        switch status {
        case .outForDelivery: Look(symbol: "box.truck.fill", text: "Out for delivery", color: Theme.accentGreen)
        case .awaitingPickup: Look(symbol: "building.2.fill", text: "Ready for pickup", color: Theme.accentYellow)
        case .failedAttempt:
            Look(symbol: "exclamationmark", text: "Delivery attempted", color: Theme.accentOrange)
        case .exception:
            Look(symbol: "exclamationmark.triangle.fill", text: "Needs attention", color: Theme.accentRed)
        case .inTransit: Look(symbol: "shippingbox.fill", text: "In transit", color: accent)
        case .infoReceived: Look(symbol: "tag.fill", text: "Label created", color: Theme.text2(ts))
        case .notFound: Look(symbol: "questionmark", text: "Not found yet", color: Theme.text3(ts))
        case .frozen: Look(symbol: "pause.fill", text: "No recent updates", color: Theme.text3(ts))
        case .delivered: Look(symbol: "checkmark", text: "Delivered", color: Theme.text2(ts))
        case .unknown: Look(symbol: "shippingbox", text: "Unknown status", color: Theme.text3(ts))
        }
    }

    private func badge(_ status: ParcelDelivery.Status, size: CGFloat) -> some View {
        let look = look(status)
        return ZStack {
            Circle().fill(look.color.opacity(0.16))
            Image(systemName: look.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(look.color)
        }
        .frame(width: size, height: size)
    }

    private func statusLine(_ delivery: ParcelDelivery) -> String {
        let carrier = delivery.carrier.isEmpty ? nil : service.carrierName(delivery.carrier)
        return [look(delivery.status).text, carrier].compactMap { $0 }.joined(separator: " · ")
    }

    /// "2:14 PM · Arrived at facility · Memphis, TN". The time leads because
    /// carriers' place names are long and the end of the line gets cut.
    private func updateLine(_ event: ParcelDelivery.Event?, now: Date) -> String? {
        guard let event else { return nil }
        let parts = [ParcelSchedule.when(event.date, now: now), event.text, event.location]
        let line = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    private func placeAndTime(_ event: ParcelDelivery.Event, now: Date) -> String? {
        let line = [event.location, ParcelSchedule.when(event.date, now: now)].compactMap { $0 }.joined(
            separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// When it's coming, or when it came: the day, then the time or window.
    @ViewBuilder
    private func arrival(_ delivery: ParcelDelivery, now: Date, large: Bool) -> some View {
        let (day, time, late) = arrivalText(delivery, now: now)
        if let day {
            VStack(alignment: .trailing, spacing: 1) {
                Text(day)
                    .font(large ? Theme.title(ts) : Theme.label(ts))
                    .foregroundStyle(late ? Theme.accentYellow : Theme.text1(ts))
                    .lineLimit(1)
                if let time {
                    Text(time)
                        .font(large ? Theme.label(ts) : Theme.caption(ts))
                        .foregroundStyle(Theme.text2(ts))
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
    }

    private func arrivalText(_ delivery: ParcelDelivery, now: Date) -> (String?, String?, Bool) {
        if delivery.status == .delivered {
            return (delivery.latestEvent.flatMap { ParcelSchedule.when($0.date, now: now) }, nil, false)
        }
        if let expected = delivery.expected {
            let phrase = ParcelSchedule.phrase(for: expected, now: now)
            // The van has it: a day that's gone by only means the carrier
            // didn't update the estimate.
            if delivery.status == .outForDelivery, phrase.isLate { return ("Today", nil, false) }
            return (phrase.day, phrase.time, phrase.isLate)
        }
        return (delivery.status == .outForDelivery ? "Today" : nil, nil, false)
    }

    // MARK: - Without deliveries

    private var emptyState: some View {
        message(
            symbol: "shippingbox",
            title: filter == .active ? "NOTHING ON THE WAY" : "NO RECENT DELIVERIES",
            detail: filter == .active ? "Deliveries you add in Parcel appear here" : nil)
    }

    @ViewBuilder
    private var problemState: some View {
        switch service.problem {
        case .needsKey:
            message(
                symbol: "shippingbox", title: "ADD YOUR PARCEL API KEY",
                detail: "Edit this widget and paste the key from web.parcelapp.net")
        case .keyRefused(let reason):
            message(symbol: "key", title: "PARCEL REFUSED THE KEY", detail: reason ?? "Check it at web.parcelapp.net")
        case .rateLimited(let until):
            message(
                symbol: "hourglass", title: "PARCEL ASKED FOR A PAUSE",
                detail: "Trying again at " + until.formatted(date: .omitted, time: .shortened))
        case .unreachable:
            message(symbol: "wifi.slash", title: "CAN'T REACH PARCEL", detail: "Trying again shortly")
        case .failed(let reason):
            message(symbol: "exclamationmark.triangle", title: "PARCEL DIDN'T ANSWER", detail: reason)
        case nil:
            message(symbol: "shippingbox", title: "CHECKING PARCEL", detail: nil)
        }
    }

    private func noteText(_ note: String) -> some View {
        Text(note)
            .font(Theme.micro(ts))
            .foregroundStyle(Theme.text3(ts))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Under a list that couldn't be refreshed: why, and how old it is.
    private var staleNote: String? {
        guard let problem = service.problem, let updated = service.lists[filter]?.updated else { return nil }
        let reason: String
        switch problem {
        case .needsKey: return nil
        case .keyRefused: reason = "Parcel refused the key"
        case .rateLimited: reason = "Parcel asked for a pause"
        case .unreachable: reason = "Can't reach Parcel"
        case .failed: reason = "Couldn't update"
        }
        return reason + " · as of " + updated.formatted(date: .omitted, time: .shortened)
    }

    private func message(symbol: String, title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 30 * ts.fontScale))
                .foregroundStyle(Theme.text3(ts))
            Text(title)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            if let detail {
                Text(detail)
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openParcel() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mr-brightside.myParcel") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let web = URL(string: "https://web.parcelapp.net") {
            NSWorkspace.shared.open(web)
        }
    }
}
