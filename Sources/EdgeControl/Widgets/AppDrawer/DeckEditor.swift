import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Deck editor
//
// The Mac side of setting up decks: what the dashboard's touch keyboard is
// no good for, like typing a link or a snippet, choosing a file, recording a
// hotkey, building a multi-action or giving a key its own look. It edits the
// same decks the tiles show, so a change appears on them straight away.

@MainActor
final class DeckEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = DeckEditorWindowController()

    private var window: NSWindow?
    private var model: DeckEditorModel?

    /// Opens the editor on a deck, with keys drawn in the colours of the tile
    /// it was opened from.
    func show(service: AppDrawerService, deckId: String?, palette: KeyPalette? = nil) {
        service.decks.loadIfNeeded()
        let model = self.model ?? DeckEditorModel(service: service)
        self.model = model
        if let deckId, service.decks.decks[deckId] != nil { model.deckId = deckId }
        if let palette { model.palette = palette }
        if window == nil {
            let hosting = NSHostingController(rootView: DeckEditorView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "App Drawer Decks"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1040, height: 640))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        guard let window else { return }
        window.level = .normal
        moveOffKioskScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keeps the window off the dashboard's display, where the dashboard
    /// would bury it.
    private func moveOffKioskScreen(_ window: NSWindow) {
        guard let kiosk = NSApp.windows.first(where: { $0 is KioskWindow })?.screen,
            window.screen == kiosk || window.screen == nil,
            let other = NSScreen.screens.first(where: { $0 != kiosk })
        else { return }
        let frame = window.frame
        window.setFrameOrigin(
            NSPoint(x: other.visibleFrame.midX - frame.width / 2, y: other.visibleFrame.midY - frame.height / 2))
    }
}

@MainActor
final class DeckEditorModel: ObservableObject {
    let service: AppDrawerService
    var decks: DeckStore { service.decks }

    @Published var deckId: String? {
        didSet {
            if deckId != oldValue {
                path = []
                selection = nil
            }
        }
    }
    @Published var path: [String] = []
    @Published var selection: String?
    /// How keys without a colour of their own are drawn.
    @Published var palette: KeyPalette

    private var watching: Set<AnyCancellable> = []

    init(service: AppDrawerService) {
        self.service = service
        palette = KeyPalette(accent: Theme.accentCyan, fullAccent: false, whiteIcons: false)
        deckId = service.decks.deckIds.first
        // Decks change from tiles and other Macs too.
        service.decks.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &watching)
        service.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &watching)
    }

    var deck: Deck? { deckId.flatMap { decks.decks[$0] } }

    func deckName(_ id: String) -> String { decks.decks[id]?.name ?? id }

    var level: [DeckKey] { deck?.keys.level(path) ?? [] }

    /// The keys in the order the tile shows them.
    var shown: [DeckKey] {
        guard let deck else { return [] }
        return deck.order.arrange(
            level, title: title, appRank: { self.service.rank(of: $0, recent: deck.order == .recent) })
    }

    func title(_ key: DeckKey) -> String { key.title(appName: service.appName) }

    func key(_ id: String) -> DeckKey? { deck?.keys.find(id) }

    func tile(_ key: DeckKey) -> DrawerTile { DrawerTile.key(key, service: service, decks: decks) }

    // MARK: Changes

    func edit(_ change: (inout Deck) -> Void) {
        guard let deckId else { return }
        decks.edit(deckId, change)
    }

    func update(_ id: String, _ change: (inout DeckKey) -> Void) {
        edit { $0.keys.update(id, change) }
    }

    func add(_ action: KeyAction, title: String? = nil) {
        let key = DeckKey(title: title, action: action)
        let path = path
        edit { $0.keys.editLevel(path) { $0.append(key) } }
        selection = key.id
    }

    func delete(_ id: String) {
        edit { $0.keys.remove(id) }
        if selection == id { selection = nil }
    }

    /// Drag and drop: puts `id` just before or after `target`, as the keys
    /// are shown. A deck sorted another way keeps the order it was showing,
    /// with this one change, and is sorted by hand from then on.
    func move(_ id: String, to target: String, after: Bool) {
        guard let order = Self.reordered(shown.map(\.id), moving: id, to: target, after: after) else { return }
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let path = path
        edit { deck in
            deck.keys.editLevel(path) { keys in
                keys.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
            }
            deck.order = .manual
        }
    }

    /// The ids with `id` taken out and put back beside `target`; nil when
    /// that changes nothing or either isn't there.
    nonisolated static func reordered(
        _ ids: [String], moving id: String, to target: String, after: Bool
    )
        -> [String]?
    {
        guard id != target, let from = ids.firstIndex(of: id) else { return nil }
        var order = ids
        order.remove(at: from)
        guard let at = order.firstIndex(of: target) else { return nil }
        order.insert(id, at: after ? at + 1 : at)
        return order == ids ? nil : order
    }

    func newDeck(named name: String) {
        let display = name.trimmingCharacters(in: .whitespaces)
        let id = display.lowercased()
        guard !display.isEmpty else { return }
        if decks.decks[id] == nil { decks.edit(id) { $0.name = display } }
        deckId = id
    }
}

// MARK: - Views

struct DeckEditorView: View {
    @ObservedObject var model: DeckEditorModel

    var body: some View {
        NavigationSplitView {
            DeckSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if model.deck != nil {
                DeckDetail(model: model)
            } else {
                ContentUnavailableView(
                    "No deck chosen", systemImage: "square.grid.3x3",
                    description: Text(
                        "Make a deck with + below. An App Drawer in Deck mode shows the deck whose name matches its Deck Name."
                    ))
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}

struct DeckSidebar: View {
    @ObservedObject var model: DeckEditorModel
    @State private var naming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        List(selection: $model.deckId) {
            Section("Decks") {
                ForEach(model.decks.deckIds, id: \.self) { id in
                    Label(model.deckName(id), systemImage: "square.grid.3x3.fill").tag(id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Button {
                        naming = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New deck")
                    Button {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Delete this deck")
                    .disabled(model.deckId == nil)
                }
                .buttonStyle(.borderless)
                Divider()
                DeckLocationPicker(decks: model.decks)
            }
            .padding(12)
        }
        .alert("New Deck", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Make Deck") {
                model.newDeck(named: newName)
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("An App Drawer shows it when its Deck Name is the same.")
        }
        .confirmationDialog(
            "Delete \(model.deckId.map(model.deckName) ?? "this deck")?", isPresented: $confirmDelete
        ) {
            Button("Delete Deck", role: .destructive) {
                if let id = model.deckId {
                    model.decks.remove(id)
                    model.deckId = model.decks.deckIds.first
                }
            }
        } message: {
            Text("Its keys go with it, from every tile and every Mac that shares these decks.")
        }
    }
}

/// Where Decks.json is saved: this Mac, or a folder a cloud drive syncs.
struct DeckLocationPicker: View {
    @ObservedObject var decks: DeckStore
    @State private var pending: DeckStore.Location?
    @State private var error: String?

    var body: some View {
        let current = decks.currentLocation
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved in").font(.caption).foregroundStyle(.secondary)
            Menu(current.name) {
                ForEach(decks.locations()) { location in
                    Button(location.name) { choose(location) }
                        .disabled(location.folder.standardizedFileURL == current.folder.standardizedFileURL)
                }
                Divider()
                Button("Other Folder…") { chooseFolder() }
            }
            .fixedSize()
            Text(
                current.id == "local"
                    ? "Only this Mac has these decks." : "Macs that point at this folder share these decks."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(
            "\(pending?.name ?? "That folder") already has decks",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
        ) {
            Button("Use Both, Newest Wins") { move(pending, adopt: true) }
            Button("Replace Them With This Mac’s") { move(pending, adopt: false) }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Another Mac saved decks there. Using both keeps each deck as it was last changed on either Mac.")
        }
        .alert("Couldn’t Move the Decks", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }))
        {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func choose(_ location: DeckStore.Location) {
        if decks.folderHasDecks(location.folder) { pending = location } else { move(location, adopt: false) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Save Decks Here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose(DeckStore.Location(id: "custom", name: url.lastPathComponent, folder: url))
    }

    private func move(_ location: DeckStore.Location?, adopt: Bool) {
        pending = nil
        guard let location else { return }
        do {
            try decks.move(to: location.folder, adopt: adopt)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DeckDetail: View {
    @ObservedObject var model: DeckEditorModel
    @State private var choosingApp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                breadcrumbs
                Spacer()
                Picker(
                    "Order",
                    selection: Binding(
                        get: { model.deck?.order ?? .manual }, set: { order in model.edit { $0.order = order } })
                ) {
                    ForEach(DeckOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 210)
                addMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                DeckKeyGrid(model: model)
                Divider()
                Group {
                    if let id = model.selection, model.key(id) != nil {
                        KeyInspector(model: model, id: id)
                    } else {
                        ContentUnavailableView(
                            "Choose a key", systemImage: "hand.tap",
                            description: Text(
                                "Click a key to change how it looks and what it does. Drag keys to reorder them."))
                    }
                }
                .frame(width: 340)
            }
        }
        .sheet(isPresented: $choosingApp) {
            AppChooser(service: model.service) { id in
                if let id { model.add(.app(id)) }
                choosingApp = false
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            Button(model.deck?.name ?? "Deck") {
                model.path = []
                model.selection = nil
            }
            .buttonStyle(.plain)
            .font(.headline)
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, id in
                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                Button(model.key(id).map(model.title) ?? "Folder") {
                    model.path = Array(model.path.prefix(index + 1))
                    model.selection = nil
                }
                .buttonStyle(.plain)
                .font(.headline)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button("App…") { choosingApp = true }
            Menu("Shortcut") {
                if model.service.shortcuts.isEmpty { Text("No Shortcuts on this Mac") }
                ForEach(model.service.shortcuts) { shortcut in
                    Button(shortcut.name) { model.add(.shortcut(id: shortcut.id, name: shortcut.name)) }
                }
            }
            Button("Link") { model.add(.link("https://")) }
            Button("File or Folder…") {
                if let url = chooseFile() { model.add(.file(url.path)) }
            }
            Button("Text") { model.add(.text("")) }
            Divider()
            Button("Keyboard Shortcut") { model.add(KeyAction(.hotkey)) }
            Menu("Media Key") {
                ForEach(MediaKey.allCases, id: \.self) { key in
                    Button(key.title) { model.add(.media(key)) }
                }
            }
            Button("Multi-Action") { model.add(.multi()) }
            Divider()
            Button("Folder of Keys") { model.add(.folder(), title: "Folder") }
        } label: {
            Label("Add Key", systemImage: "plus")
        }
        .fixedSize()
    }
}

@MainActor
func chooseFile() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
}

struct DeckKeyGrid: View {
    @ObservedObject var model: DeckEditorModel
    /// Where a dragged key would land, shown as a bar in the gap.
    @State private var spot: DeckDropSpot?
    /// The key being dragged, so a spot that wouldn't move it shows no bar.
    @State private var dragging: String?

    /// Each key's cell reaches halfway across the gaps around it, so a drag
    /// always has a key under it and the bar doesn't flicker between keys.
    private static let gap: CGFloat = 14

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 106 + Self.gap, maximum: 126), spacing: 0)], spacing: 0) {
                if !model.path.isEmpty {
                    face(
                        DrawerTile(
                            id: "back", label: "Back", look: .symbol("chevron.left"), neutral: true, action: .back),
                        selected: false
                    )
                    .onTapGesture {
                        model.path.removeLast()
                        model.selection = nil
                    }
                }
                let order = model.shown.map(\.id)
                ForEach(model.shown) { key in
                    face(model.tile(key), selected: model.selection == key.id)
                        .onTapGesture(count: 2) {
                            if key.action.kind == .folder {
                                model.path.append(key.id)
                                model.selection = nil
                            }
                        }
                        .onTapGesture { model.selection = key.id }
                        .overlay(alignment: spot?.after == true ? .trailing : .leading) {
                            if spot?.id == key.id { insertionBar }
                        }
                        // The key itself under the pointer, and a move, not
                        // the copy badge a plain drop destination shows.
                        .onDrag {
                            dragging = key.id
                            return NSItemProvider(object: key.id as NSString)
                        } preview: {
                            DrawerKey(
                                tile: model.tile(key), side: 84, palette: model.palette,
                                labelFont: .system(size: 10, weight: .bold), images: model.service.images)
                        }
                        .onDrop(
                            of: [.plainText],
                            delegate: DeckKeyDrop(
                                target: key.id, order: order, dragging: dragging, spot: $spot, model: model))
                }
            }
            .animation(.easeOut(duration: 0.12), value: spot)
            .padding(18 - Self.gap / 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var insertionBar: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 4, height: 92)
            .offset(x: spot?.after == true ? 2 : -2, y: -10)
            .allowsHitTesting(false)
    }

    private func face(_ tile: DrawerTile, selected: Bool) -> some View {
        VStack(spacing: 6) {
            DrawerKey(
                tile: tile, side: 84, palette: model.palette, labelFont: .system(size: 10, weight: .bold),
                images: model.service.images)
            Text(tile.label).font(.caption).lineLimit(1).frame(width: 96)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .padding(Self.gap / 2)
        .contentShape(Rectangle())
    }
}

/// Where a dragged key would land: just before or after another.
struct DeckDropSpot: Equatable {
    var id: String
    var after: Bool
}

/// Shows where a dragged key will go while it's over another, and puts it
/// there when it's let go.
private struct DeckKeyDrop: DropDelegate {
    let target: String
    let order: [String]
    let dragging: String?
    @Binding var spot: DeckDropSpot?
    let model: DeckEditorModel

    func dropUpdated(info: DropInfo) -> DropProposal? {
        // The left half of a key puts it before; the right half, after.
        let after = info.location.x > (106 + 14) / 2
        let moves =
            dragging.map {
                DeckEditorModel.reordered(order, moving: $0, to: target, after: after) != nil
            } ?? true
        let next = moves ? DeckDropSpot(id: target, after: after) : nil
        if spot != next { spot = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if spot?.id == target { spot = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = spot?.after ?? false
        spot = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            // Text dragged in from another app isn't a key, and moves nothing.
            guard let moved = object as? String else { return }
            Task { @MainActor in model.move(moved, to: target, after: after) }
        }
        return true
    }
}
