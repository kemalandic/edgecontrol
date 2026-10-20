import AppKit
import SwiftUI

/// Apps and keys to tap: a copy of the Dock with running apps, the apps
/// used most or most recently, or a deck of keys set up like a Stream Deck,
/// which open apps, run Shortcuts, open links and files, copy or type text,
/// press hotkeys and media keys, do several of those in a row, or open
/// folders of more keys.
public final class AppDrawerWidget: DashboardWidget {
    public let widgetId = "app-drawer"
    public let displayName = "App Drawer"
    public let description = "Your Dock, your most or recently used apps, or a deck of keys like a Stream Deck"
    public let iconName = "square.grid.3x3.fill"
    public let category: WidgetCategory = .system
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(20, 6))
    public let defaultSize = WidgetSize.size(8, 2)
    public var requiredServices: Set<ServiceKey> { [.appDrawer] }

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(
            key: "mode", label: "Show", type: .picker, defaultValue: .string(DrawerSettings.Mode.dock.rawValue),
            options: DrawerSettings.Mode.allCases.map(\.rawValue),
            help:
                "Dock: your Dock's apps, then running apps that aren't in it. Deck: keys you set up with the pencil or in the deck editor."
        ),
        ConfigSchemaEntry(
            key: "deck", label: "Deck Name", type: .text, defaultValue: .string("Main"),
            help: "For Deck mode. Tiles with the same deck name share their keys."),
        ConfigSchemaEntry(
            key: "decks", label: "Decks", type: .appDrawerDecks, defaultValue: .string(""),
            help: "The deck editor, on this Mac, for what a touch keyboard is no good at."),
        ConfigSchemaEntry(key: "title", label: "Title", type: .text, defaultValue: .string("")),
        ConfigSchemaEntry(
            key: "style", label: "Style", type: .picker, defaultValue: .string(DrawerSettings.Style.plain.rawValue),
            options: DrawerSettings.Style.allCases.map(\.rawValue),
            help: "Keys: square keys with their labels inside, like a Stream Deck."),
        ConfigSchemaEntry(
            key: "keyColor", label: "Key Color", type: .picker, defaultValue: .string("Dimmed accent"),
            options: ["Dimmed accent", "Accent"], help: "For deck keys without a color of their own."),
        ConfigSchemaEntry(
            key: "iconColor", label: "Icon Color", type: .picker, defaultValue: .string("Theme color"),
            options: ["Theme color", "White"],
            help: "The symbol on those keys. On the full accent, Theme color is whichever of near-black or white reads."
        ),
        ConfigSchemaEntry(
            key: "iconSize", label: "Icon Size", type: .picker,
            defaultValue: .string(DrawerSettings.IconSize.auto.rawValue),
            options: DrawerSettings.IconSize.allCases.map(\.rawValue)),
        ConfigSchemaEntry(key: "showNames", label: "Show Names", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(
            key: "showRunning", label: "Show Running Indicators", type: .toggle, defaultValue: .bool(true)),
    ]

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        AppDrawerWidgetView(config: config)
    }
}

private struct AppDrawerWidgetView: View {
    let config: WidgetConfig
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DrawerContent(service: model.appDrawerService, decks: model.appDrawerService.decks, config: config)
    }
}

/// The tile: its grid of apps or keys, or the picker that edits the deck.
struct DrawerContent: View {
    @ObservedObject var service: AppDrawerService
    @ObservedObject var decks: DeckStore
    let config: WidgetConfig

    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    /// Keeps touch zone ids apart when the widget is placed twice.
    @State private var instance = String(UUID().uuidString.prefix(8))
    @State private var page = 0
    /// The folders opened, from the top of the deck.
    @State private var path: [String] = []
    @State private var editing = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private var settings: DrawerSettings { DrawerSettings(config) }
    private var registry: TouchZoneRegistry { model.touchService.zoneRegistry }
    /// The color picked for App Drawer on the Theme page, or the accent.
    private var accent: Color { ts.widgetColorOverrides["app-drawer"]?.primary.color ?? Theme.accent(ts) }
    private var palette: KeyPalette {
        KeyPalette(accent: accent, fullAccent: settings.fullAccent, whiteIcons: settings.whiteIcons)
    }
    private var gap: CGFloat { settings.style == .dividers ? 0 : max(4, CGFloat(ts.widgetGap) * 0.6) }

    var body: some View {
        let settings = settings
        VStack(alignment: .leading, spacing: 6) {
            if !settings.title.isEmpty {
                Text(settings.title.uppercased())
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .lineLimit(1)
                    .padding(.horizontal, settings.style == .dividers ? Theme.widgetPadding : 2)
                    .padding(.top, settings.style == .dividers ? 10 : 0)
            }
            if editing {
                DrawerPicker(
                    service: service, decks: decks, deckId: settings.deckId, deckName: settings.deckName,
                    path: $path, accent: accent, palette: palette, registry: registry, instance: instance
                ) {
                    editing = false
                }
            } else {
                grid(settings)
            }
        }
        .padding(settings.style == .dividers ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetCard()
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous))
        .overlay(alignment: .topTrailing) {
            if settings.mode == .deck && !editing { editButton }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(Theme.caption(ts))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.accentRed.opacity(0.9), in: Capsule())
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .onChange(of: service.lastFailure?.at) { _, _ in
            guard let failure = service.lastFailure, visibleIds.contains(failure.key) else { return }
            show(failure.message)
        }
        .onChange(of: settings.deckId) { _, _ in
            path = []
            page = 0
        }
        .onChange(of: settings.mode) { _, _ in page = 0 }
        .onAppear { decks.loadIfNeeded() }
    }

    // MARK: - Tiles

    private var visibleIds: Set<String> { Set(tiles(settings).map(\.id)) }

    private func tiles(_ settings: DrawerSettings) -> [DrawerTile] {
        switch settings.mode {
        case .recent: return service.recentlyUsed.filter { service.apps[$0] != nil }.map { appTile($0) }
        case .most: return service.mostUsed.filter { service.apps[$0] != nil }.map { appTile($0) }
        case .dock:
            let dock = service.dockLayout
            return dock.kept.map { appTile($0) } + dock.others.enumerated().map { appTile($1, divider: $0 == 0) }
        case .deck:
            let deck = decks.deck(settings.deckId)
            let level = deck.keys.level(path)
            let arranged = deck.order.arrange(
                level, title: { $0.title(appName: service.appName) },
                appRank: { service.rank(of: $0, recent: deck.order == .recent) })
            var tiles = arranged.map(keyTile)
            if !path.isEmpty {
                tiles.insert(
                    DrawerTile(id: "back", label: "Back", look: .symbol("chevron.left"), neutral: true, action: .back),
                    at: 0)
            }
            return tiles
        }
    }

    private func appTile(_ bundleId: String, divider: Bool = false) -> DrawerTile {
        DrawerTile(
            id: "app:" + bundleId, label: service.appName(bundleId) ?? bundleId, look: .app(bundleId),
            running: service.running.contains(bundleId), front: service.frontmost == bundleId,
            launching: service.launching.contains(bundleId), missing: service.apps[bundleId] == nil,
            failed: service.failures["app:" + bundleId] != nil, divider: divider, action: .openApp(bundleId))
    }

    private func keyTile(_ key: DeckKey) -> DrawerTile {
        DrawerTile.key(key, service: service, decks: decks)
    }

    private func perform(_ action: TileAction) {
        switch action {
        case .openApp(let bundleId): service.open(bundleId)
        case .runKey(let key): service.run(key)
        case .openFolder(let id):
            path.append(id)
            page = 0
        case .back:
            path.removeLast()
            page = 0
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private func grid(_ settings: DrawerSettings) -> some View {
        let tiles = tiles(settings)
        if let message = emptyMessage(settings, empty: tiles.isEmpty) {
            message
        } else {
            GeometryReader { geo in
                let keys = settings.style == .keys
                let fit = { (height: CGFloat) in
                    DrawerLayout.fit(
                        count: tiles.count, width: geo.size.width, height: height, gap: gap, keys: keys,
                        showNames: settings.showNames, showRunning: settings.showRunning,
                        fixedIcon: settings.iconSize.points)
                }
                // Recently used and Most used show the top apps that fit; the
                // Dock and decks page.
                let paged = settings.mode == .dock || settings.mode == .deck
                let whole = fit(geo.size.height)
                let needsPages = paged && tiles.count > whole.perPage
                let layout = needsPages ? fit(geo.size.height - 16) : whole
                let pages = needsPages ? Int((Double(tiles.count) / Double(layout.perPage)).rounded(.up)) : 1
                let current = min(page, pages - 1)
                let visible = Array(tiles.dropFirst(current * layout.perPage).prefix(layout.perPage))
                let cellWidth = (geo.size.width - gap * CGFloat(layout.columns - 1)) / CGFloat(layout.columns)
                let height = needsPages ? geo.size.height - 16 : geo.size.height
                let cellHeight = (height - gap * CGFloat(layout.rows - 1)) / CGFloat(layout.rows)
                VStack(spacing: 0) {
                    VStack(spacing: gap) {
                        ForEach(0..<layout.rows, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(0..<layout.columns, id: \.self) { column in
                                    let index = row * layout.columns + column
                                    if index < visible.count {
                                        cell(
                                            visible[index], layout: layout, settings: settings,
                                            row: row, column: column, lastRow: layout.rows - 1,
                                            lastColumn: layout.columns - 1
                                        )
                                        .frame(width: cellWidth, height: cellHeight)
                                    } else {
                                        Color.clear.frame(width: cellWidth, height: cellHeight)
                                    }
                                }
                            }
                        }
                    }
                    if needsPages { pager(pages: pages, current: current) }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(
        _ tile: DrawerTile, layout: DrawerLayout, settings: DrawerSettings, row: Int, column: Int, lastRow: Int,
        lastColumn: Int
    ) -> some View {
        let content = Group {
            if settings.style == .keys {
                DrawerKey(
                    tile: tile, side: layout.key, palette: palette,
                    labelFont: .system(
                        size: min(max(9, layout.key * 0.12), ts.fontSizeLabel * ts.fontScale), weight: .heavy,
                        design: ts.fontFamily.design),
                    images: service.images
                )
                .overlay {
                    if tile.front && settings.showRunning {
                        RoundedRectangle(cornerRadius: layout.key * 0.18, style: .continuous).strokeBorder(
                            accent, lineWidth: 2)
                    }
                }
                .bouncing(tile.launching, height: layout.key * 0.06)
            } else {
                VStack(spacing: 3) {
                    DrawerIcon(tile: tile, side: layout.icon, palette: palette, images: service.images)
                        .bouncing(tile.launching, height: layout.icon * 0.12)
                    if settings.showNames {
                        Text(tile.label)
                            .font(Theme.caption(ts))
                            .foregroundStyle(Theme.text2(ts))
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                    }
                    if settings.showRunning {
                        Circle()
                            .fill(tile.front ? accent : Theme.text3(ts))
                            .frame(width: 4, height: 4)
                            .opacity(tile.running ? 1 : 0)
                    }
                }
            }
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                switch settings.style {
                case .cards:
                    RoundedRectangle(cornerRadius: max(0, Theme.radius(ts) - 4), style: .continuous)
                        .fill(tile.front && settings.showRunning ? accent.opacity(0.16) : Theme.cardBg(ts))
                        .overlay(
                            RoundedRectangle(cornerRadius: max(0, Theme.radius(ts) - 4), style: .continuous)
                                .strokeBorder(Theme.border(ts), lineWidth: 1))
                case .dividers:
                    Rectangle().fill(Color.clear)
                        .overlay(alignment: .trailing) {
                            if column < lastColumn { Rectangle().fill(Theme.border(ts)).frame(width: 1) }
                        }
                        .overlay(alignment: .bottom) {
                            if row < lastRow { Rectangle().fill(Theme.border(ts)).frame(height: 1) }
                        }
                default:
                    Color.clear
                }
            }
            .overlay(alignment: .leading) {
                // The Dock's divider, between kept apps and the rest.
                if tile.divider && settings.style != .dividers && column > 0 {
                    Rectangle().fill(Theme.border(ts)).frame(width: 1).padding(.vertical, 10).offset(x: -gap / 2 - 0.5)
                }
            }
            .overlay {
                if tile.failed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accentRed, lineWidth: 2)
                }
            }
            .opacity(tile.missing ? 0.35 : 1)
            .scaleEffect(tile.fired ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: tile.fired)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5) {
                if let key = tile.holdKey { service.run(key, held: true) }
            }
            .touchTappable(id: "app-drawer-\(instance)-\(tile.id)", registry: registry) { [action = tile.action] in
                Task { @MainActor in perform(action) }
            }
    }

    private func pager(pages: Int, current: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<pages, id: \.self) { index in
                Circle()
                    .fill(index == current ? accent : Theme.text3(ts))
                    .frame(width: 6, height: 6)
                    .frame(width: 22, height: 16)
                    .contentShape(Rectangle())
                    .touchTappable(id: "app-drawer-\(instance)-page-\(index)", registry: registry) {
                        Task { @MainActor in page = index }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Messages and controls

    private func emptyMessage(_ settings: DrawerSettings, empty: Bool) -> AnyView? {
        guard empty else { return nil }
        let title: String
        var detail: String?
        var action: (label: String, id: String)?
        if service.apps.isEmpty {
            title = "Loading apps…"
        } else {
            switch settings.mode {
            case .recent, .most:
                title = settings.mode == .recent ? "No recent apps yet" : "No usage yet"
                detail = "Apps show up here as you use them."
            case .dock:
                title = "The Dock is empty"
            case .deck:
                title = path.isEmpty ? "No keys yet" : "This folder is empty"
                detail = "Add apps, Shortcuts, links, hotkeys and more."
                action = ("Add Keys", "add")
            }
        }
        return AnyView(
            VStack(spacing: 6) {
                Text(title).font(Theme.label(ts)).foregroundStyle(Theme.text1(ts))
                if let detail {
                    Text(detail).font(Theme.caption(ts)).foregroundStyle(Theme.text3(ts)).multilineTextAlignment(
                        .center)
                }
                if let action {
                    Text(action.label)
                        .font(Theme.caption(ts))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(accent.opacity(0.16), in: Capsule())
                        .touchTappable(id: "app-drawer-\(instance)-\(action.id)", registry: registry) {
                            Task { @MainActor in editing = true }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity))
    }

    private var editButton: some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.text2(ts))
            .frame(width: 26, height: 26)
            .background(Color.black.opacity(0.35), in: Circle())
            .padding(6)
            .touchTappable(id: "app-drawer-\(instance)-edit", registry: registry) {
                Task { @MainActor in editing = true }
            }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

// MARK: - Bounce

extension View {
    /// Bounces while an app is opening, as the Dock does.
    func bouncing(_ active: Bool, height: CGFloat) -> some View {
        modifier(Bounce(active: active, height: height))
    }
}

/// Worked out from the clock, not a repeating animation: SwiftUI adds a new
/// animation to one that repeats forever rather than replacing it, so that
/// kind never stops.
private struct Bounce: ViewModifier {
    let active: Bool
    let height: CGFloat
    @State private var since: Date?

    /// Up and down again, slowing at the top as a ball does.
    static let period: TimeInterval = 0.76

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: since == nil)) { context in
            let elapsed = since.map { context.date.timeIntervalSince($0) } ?? 0
            content.offset(y: -height * abs(sin(elapsed / Self.period * .pi)))
        }
        .animation(.easeOut(duration: 0.2), value: since == nil)
        .onChange(of: active, initial: true) { _, isActive in since = isActive ? .now : nil }
    }
}
