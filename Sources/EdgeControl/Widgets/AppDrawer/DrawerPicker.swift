import AppKit
import SwiftUI

/// Editing a deck on the tile: the keys at the level the tile is showing,
/// and apps, running apps, Shortcuts and more to add, with search and the
/// tile's own keyboard.
struct DrawerPicker: View {
    @ObservedObject var service: AppDrawerService
    @ObservedObject var decks: DeckStore
    let deckId: String
    let deckName: String
    @Binding var path: [String]
    let accent: Color
    let palette: KeyPalette
    let registry: TouchZoneRegistry
    let instance: String
    let done: @MainActor () -> Void

    @Environment(\.themeSettings) private var ts
    @State private var tab: Tab?
    @State private var searching = false
    @State private var query = ""
    @State private var keysShown = true
    @State private var more: More?
    @State private var prompt: Prompt?
    @State private var viewport: CGRect?

    enum Tab: String, CaseIterable {
        case keys = "Keys"
        case apps = "Apps"
        case running = "Running"
        case shortcuts = "Shortcuts"
        case more = "More"
    }

    enum More {
        case hotkeys, media
    }

    struct Prompt {
        var title: String
        var text: String
        var symbols: Bool
        var save: @MainActor (String) -> Void
    }

    /// Something that can be on this level of the deck or not: tapping it
    /// adds a key for it, or takes that key off.
    struct Choice: Identifiable, Sendable {
        let id: String
        let label: String
        let sub: String
        let look: DrawerTile.Look
        let matches: @Sendable (DeckKey) -> Bool
        let make: @Sendable () -> DeckKey
    }

    private var deck: Deck { decks.deck(deckId) }
    private var level: [DeckKey] { deck.keys.level(path) }
    private var currentTab: Tab { tab ?? (level.isEmpty ? .apps : .keys) }
    private func zone(_ name: String) -> String { "app-drawer-\(instance)-picker-\(name)" }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 330
            VStack(spacing: 6) {
                if let prompt {
                    promptView(prompt, compact: compact)
                } else {
                    header
                    if searching && keysShown && compact {
                        chipStrip
                    } else {
                        list
                    }
                    if searching && keysShown {
                        DrawerKeyboard(
                            compact: compact, symbols: false, registry: registry, idPrefix: zone("search")
                        ) { pressSearch($0) }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            circleButton(searching ? "xmark" : "magnifyingglass", id: "search", active: searching) {
                searching.toggle()
                query = ""
                keysShown = true
            }
            if searching {
                field(query, placeholder: "Search apps and Shortcuts")
                    .touchTappable(id: zone("field"), registry: registry) {
                        Task { @MainActor in keysShown = true }
                    }
            } else {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases, id: \.self) { tabButton($0) }
                }
                Spacer(minLength: 0)
            }
            Text("Done")
                .font(Theme.caption(ts))
                .foregroundStyle(KeyPalette.ink(on: accent))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accent, in: Capsule())
                .touchTappable(id: zone("done"), registry: registry) {
                    Task { @MainActor in done() }
                }
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let active = currentTab == tab
        return HStack(spacing: 4) {
            Text(tab.rawValue)
            if tab == .keys { Text("\(level.count)").foregroundStyle(Theme.text3(ts)) }
        }
        .font(Theme.caption(ts))
        .foregroundStyle(active ? Theme.text1(ts) : Theme.text2(ts))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(active ? accent.opacity(0.24) : Color.white.opacity(0.06), in: Capsule())
        .touchTappable(id: zone("tab-\(tab.rawValue)"), registry: registry) {
            Task { @MainActor in
                self.tab = tab
                more = nil
            }
        }
    }

    private func circleButton(
        _ symbol: String, id: String, active: Bool = false, _ action: @escaping @MainActor () -> Void
    )
        -> some View
    {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(active ? KeyPalette.ink(on: accent) : Theme.text2(ts))
            .frame(width: 30, height: 30)
            .background(active ? accent : Color.white.opacity(0.08), in: Circle())
            .touchTappable(id: zone(id), registry: registry) {
                Task { @MainActor in action() }
            }
    }

    private func field(_ text: String, placeholder: String) -> some View {
        HStack(spacing: 1) {
            Text(text.isEmpty ? placeholder : text)
                .foregroundStyle(text.isEmpty ? Theme.text3(ts) : Theme.text1(ts))
                .lineLimit(1)
                .truncationMode(.head)
            Rectangle().fill(accent).frame(width: 2, height: 16)
            Spacer(minLength: 0)
        }
        .font(Theme.body(ts))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    // MARK: - List

    private var list: some View {
        TouchScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 6)], alignment: .leading, spacing: 6) {
                rows
            }
            .environment(\.touchViewport, viewport)
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { viewport = geo.frame(in: .named(TouchCoordinate.name)) }
                    .onChange(of: geo.frame(in: .named(TouchCoordinate.name))) { _, frame in viewport = frame }
            }
        )
    }

    @ViewBuilder
    private var rows: some View {
        if service.apps.isEmpty {
            emptyRow("Loading apps…")
        } else if searching {
            searchRows
        } else {
            switch currentTab {
            case .keys: keyRows
            case .apps: appRows(service.installed, grouped: true)
            case .running: appRows(service.running.filter { service.apps[$0] != nil }, grouped: false)
            case .shortcuts: shortcutRows
            case .more: moreRows
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Section {
            EmptyView()
        } header: {
            Text(text)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.caption(ts))
            .foregroundStyle(Theme.text3(ts))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: Keys

    @ViewBuilder
    private var keyRows: some View {
        Section {
            if level.isEmpty {
                Text(path.isEmpty ? "No keys yet. Add some from the other tabs." : "This folder is empty.")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            ForEach(deck.order.arrange(level, title: title, appRank: rank), id: \.id) { keyRow($0) }
        } header: {
            VStack(alignment: .leading, spacing: 6) {
                if !path.isEmpty { crumb }
                orderRow
            }
        }
    }

    private var crumb: some View {
        let names =
            [deck.name ?? deckName]
            + path.indices.map { index in
                deck.keys.level(Array(path.prefix(index))).first { $0.id == path[index] }.map(title) ?? "Folder"
            }
        return HStack(spacing: 6) {
            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
            Text(names.joined(separator: " › ")).lineLimit(1)
        }
        .font(Theme.caption(ts))
        .foregroundStyle(Theme.text2(ts))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
        .listTouchTappable(id: zone("crumb"), registry: registry) {
            Task { @MainActor in _ = path.popLast() }
        }
    }

    private var orderRow: some View {
        HStack(spacing: 4) {
            Text("Order").font(Theme.caption(ts)).foregroundStyle(Theme.text3(ts))
            ForEach(DeckOrder.allCases, id: \.self) { order in
                Text(order.title)
                    .font(Theme.caption(ts))
                    .foregroundStyle(deck.order == order ? Theme.text1(ts) : Theme.text2(ts))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(deck.order == order ? accent.opacity(0.24) : Color.white.opacity(0.06), in: Capsule())
                    .listTouchTappable(id: zone("order-\(order.rawValue)"), registry: registry) {
                        Task { @MainActor in decks.edit(deckId) { $0.order = order } }
                    }
            }
        }
    }

    private func keyRow(_ key: DeckKey) -> some View {
        let manual = deck.order == .manual
        let index = level.firstIndex { $0.id == key.id } ?? 0
        return HStack(spacing: 10) {
            rowIcon(look(key), color: key.color.flatMap(Color.init(deckHex:)))
            label(title(key), sub: subtitle(key))
            Spacer(minLength: 4)
            if manual {
                smallButton("chevron.left", id: "earlier-\(key.id)", disabled: index == 0) { move(key.id, by: -1) }
                smallButton("chevron.right", id: "later-\(key.id)", disabled: index == level.count - 1) {
                    move(key.id, by: 1)
                }
            }
            smallButton("pencil", id: "rename-\(key.id)") {
                prompt = Prompt(title: "Name", text: key.title ?? "", symbols: true) { text in
                    editLevel { keys in
                        if let at = keys.firstIndex(where: { $0.id == key.id }) {
                            let name = text.trimmingCharacters(in: .whitespaces)
                            keys[at].title = name.isEmpty ? nil : name
                        }
                    }
                }
            }
            smallButton("xmark", id: "remove-\(key.id)") {
                editLevel { $0.removeAll { $0.id == key.id } }
            }
        }
        .padding(8)
        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .listTouchTappable(id: zone("key-\(key.id)"), registry: registry) {
            Task { @MainActor in
                if key.action.kind == .folder { path.append(key.id) }
            }
        }
    }

    private func smallButton(
        _ symbol: String, id: String, disabled: Bool = false, _ action: @escaping @MainActor () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.text2(ts))
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(0.08), in: Circle())
            .opacity(disabled ? 0.3 : 1)
            .listTouchTappable(id: zone(id), registry: registry) {
                Task { @MainActor in if !disabled { action() } }
            }
    }

    private func move(_ id: String, by offset: Int) {
        editLevel { keys in
            guard let at = keys.firstIndex(where: { $0.id == id }), keys.indices.contains(at + offset) else { return }
            keys.swapAt(at, at + offset)
        }
    }

    private func editLevel(_ change: @escaping (inout [DeckKey]) -> Void) {
        let path = path
        let name = deckName
        decks.edit(deckId) { deck in
            if deck.name == nil { deck.name = name }
            deck.keys.editLevel(path, change)
        }
    }

    // MARK: Apps and Shortcuts

    @ViewBuilder
    private func appRows(_ ids: [String], grouped: Bool) -> some View {
        if ids.isEmpty {
            emptyRow("No apps found.")
        } else if grouped {
            ForEach(letterGroups(ids), id: \.letter) { group in
                Section {
                    ForEach(group.ids, id: \.self) { choiceRow(appChoice($0)) }
                } header: {
                    groupHeader(group.letter)
                }
            }
        } else {
            ForEach(ids, id: \.self) { choiceRow(appChoice($0)) }
        }
    }

    private func letterGroups(_ ids: [String]) -> [(letter: String, ids: [String])] {
        var groups: [(letter: String, ids: [String])] = []
        for id in ids {
            let first = (service.appName(id) ?? id).prefix(1).uppercased()
            let letter = first.range(of: "^[A-Z]$", options: .regularExpression) != nil ? first : "#"
            if groups.last?.letter == letter {
                groups[groups.count - 1].ids.append(id)
            } else {
                groups.append((letter, [id]))
            }
        }
        return groups
    }

    @ViewBuilder
    private var shortcutRows: some View {
        if service.shortcuts.isEmpty {
            emptyRow("No Shortcuts on this Mac yet. Make some in the Shortcuts app.")
        } else {
            ForEach(service.shortcuts) { choiceRow(shortcutChoice($0)) }
        }
    }

    private func appChoice(_ id: String) -> Choice {
        Choice(
            id: "app-" + id, label: service.appName(id) ?? id, sub: id, look: .app(id),
            matches: { $0.action.kind == .app && $0.action.bundleId == id },
            make: { DeckKey(action: .app(id)) })
    }

    private func shortcutChoice(_ shortcut: DrawerShortcut) -> Choice {
        Choice(
            id: "shortcut-" + shortcut.id, label: shortcut.name, sub: "Shortcut", look: .symbol("square.2.layers.3d"),
            matches: { $0.action.kind == .shortcut && $0.action.shortcutId == shortcut.id },
            make: { DeckKey(action: .shortcut(id: shortcut.id, name: shortcut.name)) })
    }

    private func choiceRow(_ choice: Choice) -> some View {
        let chosen = level.contains(where: choice.matches)
        return HStack(spacing: 10) {
            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(chosen ? accent : Theme.text3(ts))
            rowIcon(choice.look, color: nil)
            label(choice.label, sub: choice.sub)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            chosen ? accent.opacity(0.14) : Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .listTouchTappable(id: zone("choice-\(choice.id)"), registry: registry) {
            Task { @MainActor in toggle(choice) }
        }
    }

    private func toggle(_ choice: Choice) {
        editLevel { keys in
            if let at = keys.firstIndex(where: choice.matches) {
                keys.remove(at: at)
            } else {
                keys.append(choice.make())
            }
        }
    }

    // MARK: Search

    /// Every typed word appears in the name, or the query does with its
    /// spaces taken out, since the compact keyboard has no space bar.
    nonisolated static func matches(_ text: String, query: String) -> Bool {
        let typed = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return true }
        let haystack = text.lowercased()
        return typed.split(separator: " ").allSatisfy { haystack.contains($0) }
            || haystack.replacingOccurrences(of: " ", with: "").contains(typed.replacingOccurrences(of: " ", with: ""))
    }

    private var searchResults: (shortcuts: [Choice], apps: [Choice]) {
        let typed = query.trimmingCharacters(in: .whitespaces).lowercased()
        let apps = service.installed
            .filter { Self.matches((service.appName($0) ?? "") + " " + $0, query: query) }
            .sorted { a, b in
                let aStarts = (service.appName(a) ?? "").lowercased().hasPrefix(typed)
                let bStarts = (service.appName(b) ?? "").lowercased().hasPrefix(typed)
                return aStarts && !bStarts
            }
            .prefix(150)
            .map(appChoice)
        let shortcuts = service.shortcuts.filter { Self.matches($0.name, query: query) }.map(shortcutChoice)
        return (shortcuts, apps)
    }

    @ViewBuilder
    private var searchRows: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyRow("Type part of an app’s or a Shortcut’s name.")
        } else {
            let results = searchResults
            if results.apps.isEmpty && results.shortcuts.isEmpty {
                emptyRow("Nothing matches “\(query)”.")
            }
            if !results.shortcuts.isEmpty {
                Section {
                    ForEach(results.shortcuts) { choiceRow($0) }
                } header: {
                    groupHeader("Shortcuts")
                }
            }
            if !results.apps.isEmpty {
                Section {
                    ForEach(results.apps) { choiceRow($0) }
                } header: {
                    groupHeader("Apps")
                }
            }
        }
    }

    /// On a short tile, matches go in one row above the keyboard.
    private var chipStrip: some View {
        let results = searchResults
        let choices = Array((results.shortcuts + results.apps).prefix(8))
        return HStack(spacing: 6) {
            if query.isEmpty {
                Text("Type part of a name").font(Theme.caption(ts)).foregroundStyle(Theme.text3(ts))
            }
            ForEach(choices) { choice in
                let chosen = level.contains(where: choice.matches)
                HStack(spacing: 6) {
                    rowIcon(choice.look, color: nil, side: 22)
                    Text(choice.label).lineLimit(1)
                    if chosen { Image(systemName: "checkmark").foregroundStyle(accent) }
                }
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text1(ts))
                .padding(.leading, 5)
                .padding(.trailing, 11)
                .frame(height: 32)
                .background(chosen ? accent.opacity(0.24) : Color.white.opacity(0.08), in: Capsule())
                .touchTappable(id: zone("chip-\(choice.id)"), registry: registry) {
                    Task { @MainActor in toggle(choice) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .clipped()
    }

    private func pressSearch(_ press: DrawerKeyboard.Press) {
        switch press {
        case .backspace: query = String(query.dropLast())
        case .clear: query = ""
        case .hide: keysShown = false
        case .character(" "):
            if !query.isEmpty && !query.hasSuffix(" ") { query += " " }
        case .character(let text): query += text
        }
    }

    // MARK: More

    @ViewBuilder
    private var moreRows: some View {
        switch more {
        case .hotkeys:
            actionRow("chevron.left", "Hotkeys", "Back to More", neutral: true) { more = nil }
            ForEach(HotkeyPreset.groups, id: \.name) { group in
                Section {
                    ForEach(group.presets, id: \.self) { choiceRow(hotkeyChoice($0)) }
                } header: {
                    groupHeader(group.name)
                }
            }
        case .media:
            actionRow("chevron.left", "Media keys", "Back to More", neutral: true) { more = nil }
            ForEach(MediaKey.allCases, id: \.self) { key in
                choiceRow(
                    Choice(
                        id: "media-" + key.rawValue, label: key.title, sub: "Media key", look: .symbol(key.symbol),
                        matches: { $0.action.kind == .media && $0.action.key == key.rawValue },
                        make: { DeckKey(action: .media(key)) }))
            }
        case nil:
            actionRow("folder.fill", "New folder", "A key that opens a page of more keys") {
                prompt = Prompt(title: "Folder name", text: "", symbols: false) { text in
                    let name = text.trimmingCharacters(in: .whitespaces)
                    let title = name.isEmpty ? "Folder" : name.prefix(1).uppercased() + name.dropFirst()
                    editLevel { $0.append(DeckKey(title: title, action: .folder())) }
                    tab = .keys
                }
            }
            actionRow("globe", "Link", "A website, or an app link like obsidian://") {
                prompt = Prompt(title: "Link", text: "https://", symbols: true) { text in
                    var link = text.trimmingCharacters(in: .whitespaces)
                    guard !link.isEmpty, link != "https://" else { return }
                    if link.range(of: "^[a-z][a-z0-9+.-]*:", options: [.regularExpression, .caseInsensitive]) == nil {
                        link = "https://" + link
                    }
                    editLevel { $0.append(DeckKey(action: .link(link))) }
                    tab = .keys
                }
            }
            Section {
                actionRow("command", "Hotkey", "Copy, paste, screenshots, Mission Control…") { more = .hotkeys }
                actionRow("playpause.fill", "Media key", "Play/pause, next track, volume") { more = .media }
                actionRow("keyboard", "Type text", "Types it into the app you’re using") {
                    prompt = Prompt(title: "Text to type", text: "", symbols: true) { text in
                        guard !text.isEmpty else { return }
                        editLevel { $0.append(DeckKey(action: .text(text, typed: true))) }
                        tab = .keys
                    }
                }
                if !service.canPostEvents {
                    actionRow(
                        "lock.open", "Allow in Accessibility…", "Hotkeys, media keys and typing need it", neutral: true
                    ) {
                        service.openAccessibilitySettings()
                    }
                }
            } header: {
                if !service.canPostEvents {
                    groupHeader("These need EdgeControl allowed in Accessibility on your Mac")
                }
            }
            actionRow(
                "desktopcomputer", "Edit on your Mac",
                "Record any hotkey, build multi-actions, set what holding a key does, and more", neutral: true
            ) {
                DeckEditorWindowController.shared.show(service: service, deckId: deckId)
            }
        }
    }

    private func hotkeyChoice(_ preset: HotkeyPreset) -> Choice {
        Choice(
            id: "hotkey-\(preset.keyCode)-\(preset.modifiers.joined(separator: "-"))", label: preset.name,
            sub: preset.display, look: .symbol("command"),
            matches: {
                $0.action.kind == .hotkey && $0.action.keyCode == preset.keyCode
                    && $0.action.modifiers == preset.modifiers
            },
            make: { DeckKey(action: .hotkey(preset)) })
    }

    private func actionRow(
        _ symbol: String, _ title: String, _ sub: String, neutral: Bool = false,
        _ action: @escaping @MainActor () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            rowIcon(.symbol(symbol), color: neutral ? KeyPalette.neutral : nil)
            label(title, sub: sub)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .listTouchTappable(id: zone("action-\(title)"), registry: registry) {
            Task { @MainActor in
                action()
            }
        }
    }

    // MARK: - Prompt

    private func promptView(_ prompt: Prompt, compact: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(prompt.title).font(Theme.label(ts)).foregroundStyle(Theme.text1(ts))
                Spacer()
                Text("Cancel")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .touchTappable(id: zone("prompt-cancel"), registry: registry) {
                        Task { @MainActor in self.prompt = nil }
                    }
                Text("Save")
                    .font(Theme.caption(ts))
                    .foregroundStyle(KeyPalette.ink(on: accent))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(accent, in: Capsule())
                    .touchTappable(id: zone("prompt-save"), registry: registry) {
                        Task { @MainActor in
                            guard let current = self.prompt else { return }
                            self.prompt = nil
                            current.save(current.text)
                        }
                    }
            }
            field(prompt.text, placeholder: "")
            DrawerKeyboard(compact: compact, symbols: prompt.symbols, registry: registry, idPrefix: zone("prompt")) {
                pressPrompt($0)
            }
            Spacer(minLength: 0)
        }
    }

    private func pressPrompt(_ press: DrawerKeyboard.Press) {
        guard var current = prompt else { return }
        switch press {
        case .backspace: current.text = String(current.text.dropLast())
        case .clear: current.text = ""
        case .hide:
            prompt = nil
            return
        case .character(let text): current.text += text
        }
        prompt = current
    }

    // MARK: - Pieces

    private func title(_ key: DeckKey) -> String { key.title(appName: service.appName) }

    private func subtitle(_ key: DeckKey) -> String {
        key.action.subtitle + (key.hold.map { " · Hold: " + $0.defaultTitle(appName: service.appName) } ?? "")
    }

    private func rank(_ bundleId: String) -> Int? { service.rank(of: bundleId, recent: deck.order == .recent) }

    private func look(_ key: DeckKey) -> DrawerTile.Look {
        DrawerTile.look(key, service: service, decks: decks)
    }

    private func rowIcon(_ look: DrawerTile.Look, color: Color?, side: CGFloat = 26) -> some View {
        DrawerIcon(
            tile: DrawerTile(id: "", label: "", look: look, color: color, action: .back), side: side, palette: palette,
            images: service.images)
    }

    private func label(_ title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(Theme.label(ts)).foregroundStyle(Theme.text1(ts)).lineLimit(1)
            Text(sub).font(Theme.micro(ts)).foregroundStyle(Theme.text3(ts)).lineLimit(1)
        }
        // The name before the buttons beside it.
        .frame(minWidth: 90, alignment: .leading)
        .layoutPriority(1)
    }
}
