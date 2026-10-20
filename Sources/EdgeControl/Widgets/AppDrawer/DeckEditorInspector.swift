import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The kinds of action, in the order they're offered.
let deckActionTypes: [(kind: KeyAction.Kind, name: String)] = [
    (.app, "Open an app"), (.shortcut, "Run a Shortcut"), (.url, "Open a link"), (.file, "Open a file or folder"),
    (.text, "Copy or type text"), (.hotkey, "Press a keyboard shortcut"), (.media, "Press a media key"),
    (.multi, "Do several things"), (.folder, "Open a folder of keys"),
]

/// SF Symbols worth offering first; any other symbol name works too.
let suggestedSymbols = [
    "star.fill", "heart.fill", "bolt.fill", "flame.fill", "moon.fill", "sun.max.fill", "cloud.fill", "house.fill",
    "lightbulb.fill", "lock.fill", "bell.fill", "music.note", "play.fill", "pause.fill", "forward.fill",
    "speaker.wave.2.fill", "mic.fill", "video.fill", "camera.fill", "photo.fill", "film", "gamecontroller.fill",
    "keyboard", "desktopcomputer", "laptopcomputer", "display", "printer.fill", "wifi", "globe", "link",
    "envelope.fill", "message.fill", "phone.fill", "calendar", "clock.fill", "timer", "alarm.fill",
    "checkmark.circle.fill", "list.bullet", "doc.fill", "folder.fill", "paperclip", "terminal.fill", "hammer.fill",
    "wrench.and.screwdriver.fill", "gearshape.fill", "paintbrush.fill", "pencil", "scissors", "trash.fill",
    "cart.fill", "creditcard.fill", "car.fill", "airplane", "figure.walk", "leaf.fill", "pawprint.fill",
    "cup.and.saucer.fill", "fork.knife", "sparkles", "wand.and.stars", "brain.head.profile", "person.fill",
    "person.2.fill", "building.2.fill",
]

extension KeyAction {
    /// A new action of a kind, or this one if it's that kind already.
    func changed(to kind: KeyAction.Kind, shortcuts: [DrawerShortcut]) -> KeyAction {
        guard self.kind != kind else { return self }
        switch kind {
        case .app: return .app("com.apple.finder")
        case .shortcut: return .shortcut(id: shortcuts.first?.id ?? "", name: shortcuts.first?.name ?? "")
        case .url: return .link("https://")
        case .file: return .file(FileManager.default.homeDirectoryForCurrentUser.path)
        case .text: return .text("")
        case .media: return .media(.playPause)
        case .multi: return .multi()
        case .wait: return .wait()
        case .folder: return .folder()
        case .hotkey: return KeyAction(.hotkey)
        }
    }
}

struct KeyInspector: View {
    @ObservedObject var model: DeckEditorModel
    let id: String

    private var key: DeckKey? { model.key(id) }

    var body: some View {
        if let key {
            Form {
                Section("Look") {
                    HStack {
                        Spacer()
                        DrawerKey(
                            tile: model.tile(key), side: 96, palette: model.palette,
                            labelFont: .system(size: 11, weight: .bold), images: model.service.images)
                        Spacer()
                    }
                    TextField(
                        "Title",
                        text: Binding(
                            get: { model.key(id)?.title ?? "" },
                            set: { text in model.update(id) { $0.title = text.isEmpty ? nil : text } }),
                        prompt: Text(key.action.defaultTitle(appName: model.service.appName)))
                    KeyColorRow(model: model, id: id)
                    KeyIconPicker(model: model, id: id)
                }
                Section("When pressed") {
                    ActionTypePicker(
                        label: "Action", action: action, types: deckActionTypes, shortcuts: model.service.shortcuts)
                    ActionFields(action: action, service: model.service)
                }
                Section {
                    ActionTypePicker(
                        label: "Action", action: hold, types: deckActionTypes.filter { $0.kind != .folder },
                        shortcuts: model.service.shortcuts, none: "Nothing")
                    if hold.wrappedValue.kind != nil {
                        ActionFields(action: hold, service: model.service)
                    }
                } header: {
                    Text("When held")
                } footer: {
                    Text("Holding the key for half a second does this instead.")
                }
                if !model.service.canPostEvents, key.action.needsEventAccess || key.hold?.needsEventAccess == true {
                    Section { AccessNotice(service: model.service) }
                }
                Section {
                    HStack {
                        if key.action.kind == .folder {
                            Button("Open Folder") {
                                model.path.append(id)
                                model.selection = nil
                            }
                        }
                        Spacer()
                        Button("Delete Key", role: .destructive) { model.delete(id) }
                    }
                }
            }
            .formStyle(.grouped)
            .id(id)
        }
    }

    private var action: Binding<KeyAction> {
        Binding(
            get: { model.key(id)?.action ?? KeyAction(.app) },
            set: { value in model.update(id) { $0.action = value } })
    }

    /// What holding the key does; an action with no type is none.
    private var hold: Binding<KeyAction> {
        Binding(
            get: { model.key(id)?.hold ?? KeyAction(type: "") },
            set: { value in model.update(id) { $0.hold = value.type.isEmpty ? nil : value } })
    }
}

extension KeyAction {
    /// An action of a type by name, empty for none.
    init(type: String) {
        self.type = type
    }
}

struct KeyColorRow: View {
    @ObservedObject var model: DeckEditorModel
    let id: String

    var body: some View {
        let key = model.key(id)
        let hex = key?.color
        let start = key?.action.kind == .app ? "#5B5F6B" : "#" + (Self.hex(model.palette.accent) ?? "33E6FF")
        HStack {
            Toggle(
                "Own color",
                isOn: Binding(get: { hex != nil }, set: { on in model.update(id) { $0.color = on ? start : nil } }))
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(deckHex: hex ?? start) ?? .gray },
                    set: { color in model.update(id) { $0.color = Self.hex(color).map { "#" + $0 } } }),
                supportsOpacity: false
            )
            .labelsHidden()
            .disabled(hex == nil)
        }
    }

    static func hex(_ color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded()))
    }
}

struct KeyIconPicker: View {
    @ObservedObject var model: DeckEditorModel
    let id: String
    @State private var choosingApp = false

    var body: some View {
        let icon = model.key(id)?.icon ?? ""
        let kind = icon.split(separator: ":").first.map(String.init) ?? "default"
        VStack(alignment: .leading, spacing: 8) {
            Picker("Icon", selection: Binding(get: { kind }, set: { setKind($0) })) {
                Text("Usual").tag("default")
                Text("Symbol").tag("symbol")
                Text("Emoji").tag("emoji")
                Text("Picture").tag("image")
                Text("App").tag("app")
            }
            .pickerStyle(.menu)
            switch kind {
            case "symbol":
                TextField(
                    "SF Symbol name",
                    text: Binding(
                        get: { String(icon.dropFirst(7)) },
                        set: { name in
                            setIcon(name.isEmpty ? nil : "symbol:" + name.replacingOccurrences(of: " ", with: ""))
                        }))
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 8), spacing: 4) {
                        ForEach(suggestedSymbols, id: \.self) { name in
                            Button {
                                setIcon("symbol:" + name)
                            } label: {
                                Image(systemName: name)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(icon == "symbol:" + name ? Color.accentColor.opacity(0.3) : .clear))
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                }
                .frame(height: 130)
                Text("Any SF Symbol name works; the SF Symbols app lists them all.")
                    .font(.caption).foregroundStyle(.secondary)
            case "emoji":
                TextField(
                    "Emoji",
                    text: Binding(
                        get: { String(icon.dropFirst(6)) },
                        set: { text in setIcon(text.isEmpty ? nil : "emoji:" + String(text.prefix(2))) }))
                Text("Press Control-Command-Space for the emoji picker.").font(.caption).foregroundStyle(.secondary)
            case "image":
                Button("Choose Picture…") { choosePicture() }
                Text("It’s cropped to a square and fills the key.").font(.caption).foregroundStyle(.secondary)
            case "app":
                Button(
                    icon.hasPrefix("app:")
                        ? (model.service.appName(String(icon.dropFirst(4))) ?? "Choose App…") : "Choose App…"
                ) {
                    choosingApp = true
                }
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: $choosingApp) {
            AppChooser(service: model.service) { bundleId in
                if let bundleId { setIcon("app:" + bundleId) }
                choosingApp = false
            }
        }
    }

    private func setIcon(_ value: String?) {
        model.update(id) { $0.icon = value }
    }

    private func setKind(_ kind: String) {
        switch kind {
        case "symbol": setIcon("symbol:star.fill")
        case "emoji": setIcon("emoji:⭐️")
        case "image": choosePicture()
        case "app": choosingApp = true
        default: setIcon(nil)
        }
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use Picture"
        guard panel.runModal() == .OK, let url = panel.url, let spec = model.decks.importPicture(url) else { return }
        setIcon(spec)
    }
}

/// Chooses what kind of action it is; with `none`, it can be nothing.
struct ActionTypePicker: View {
    let label: String
    @Binding var action: KeyAction
    let types: [(kind: KeyAction.Kind, name: String)]
    let shortcuts: [DrawerShortcut]
    var none: String?

    var body: some View {
        Picker(
            label,
            selection: Binding(
                get: { action.type },
                set: { type in
                    action =
                        KeyAction.Kind(rawValue: type).map { action.changed(to: $0, shortcuts: shortcuts) }
                        ?? KeyAction(type: "")
                })
        ) {
            if let none { Text(none).tag("") }
            ForEach(types, id: \.kind) { Text($0.name).tag($0.kind.rawValue) }
        }
    }
}

/// The fields for one action: a key's own, what holding it does, or a step
/// of a multi-action.
struct ActionFields: View {
    @Binding var action: KeyAction
    let service: AppDrawerService
    @State private var choosingApp = false

    var body: some View {
        switch action.kind {
        case .app:
            let bundleId = action.bundleId ?? ""
            Button(service.appName(bundleId) ?? (bundleId.isEmpty ? "Choose App…" : bundleId)) { choosingApp = true }
                .sheet(isPresented: $choosingApp) {
                    AppChooser(service: service) { chosen in
                        if let chosen { action.bundleId = chosen }
                        choosingApp = false
                    }
                }
        case .shortcut:
            Picker(
                "Shortcut",
                selection: Binding(
                    get: { action.shortcutId ?? "" },
                    set: { chosen in
                        action.shortcutId = chosen
                        action.name = service.shortcuts.first { $0.id == chosen }?.name
                    })
            ) {
                ForEach(service.shortcuts) { Text($0.name).tag($0.id) }
            }
        case .url:
            TextField("Link", text: field(\.url), prompt: Text("https://… or obsidian://…"))
        case .file:
            LabeledContent("File") {
                Text(((action.path ?? "") as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Choose…") {
                if let url = chooseFile() { action.path = url.path }
            }
        case .text:
            TextEditor(text: field(\.text))
                .font(.body)
                .frame(minHeight: 80)
            Picker(
                "Then",
                selection: Binding(
                    get: { action.typesText ? "type" : "copy" }, set: { action.mode = $0 == "type" ? "type" : nil })
            ) {
                Text("Copy it, ready to paste").tag("copy")
                Text("Type it into the app in front").tag("type")
            }
        case .hotkey:
            HotkeyField(action: $action)
        case .media:
            Picker(
                "Key",
                selection: Binding(
                    get: { MediaKey(rawValue: action.key ?? "") ?? .playPause }, set: { action.key = $0.rawValue })
            ) {
                ForEach(MediaKey.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case .multi:
            StepsEditor(action: $action, service: service)
        case .wait:
            let seconds = action.seconds ?? 0.5
            Stepper(
                value: Binding(get: { seconds }, set: { action.seconds = ($0 * 10).rounded() / 10 }), in: 0.1...30,
                step: 0.1
            ) {
                Text("Wait \(String(format: "%.1f", seconds)) s")
            }
        case .folder:
            let count = action.keys?.count ?? 0
            Text("\(count) key\(count == 1 ? "" : "s") inside. Double-click the folder to fill it.")
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func field(_ path: WritableKeyPath<KeyAction, String?>) -> Binding<String> {
        Binding(get: { action[keyPath: path] ?? "" }, set: { action[keyPath: path] = $0 })
    }
}

/// A multi-action's steps, run in order: add, reorder, remove.
struct StepsEditor: View {
    @Binding var action: KeyAction
    let service: AppDrawerService

    private var steps: [KeyAction] { action.steps ?? [] }
    private var stepTypes: [(kind: KeyAction.Kind, name: String)] {
        deckActionTypes.filter { $0.kind != .folder && $0.kind != .multi } + [(.wait, "Wait")]
    }

    var body: some View {
        if steps.isEmpty {
            Text("No steps yet.").foregroundStyle(.secondary)
        }
        ForEach(steps.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    ActionTypePicker(label: "", action: step(index), types: stepTypes, shortcuts: service.shortcuts)
                        .labelsHidden()
                    Button {
                        move(index, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .help("Earlier")
                    Button {
                        move(index, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == steps.count - 1)
                    .help("Later")
                    Button {
                        change { $0.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .help("Remove this step")
                }
                .buttonStyle(.borderless)
                ActionFields(action: step(index), service: service)
            }
            .padding(.vertical, 2)
        }
        Menu("Add a Step") {
            ForEach(stepTypes, id: \.kind) { type in
                Button(type.name) {
                    change { $0.append(KeyAction(type: "").changed(to: type.kind, shortcuts: service.shortcuts)) }
                }
            }
        }
        .fixedSize()
        Text("Steps run one after another; a step that fails stops the rest.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func step(_ index: Int) -> Binding<KeyAction> {
        Binding(
            get: { index < steps.count ? steps[index] : KeyAction(.wait) },
            set: { value in change { if index < $0.count { $0[index] = value } } })
    }

    private func move(_ index: Int, by offset: Int) {
        change { list in
            guard list.indices.contains(index + offset) else { return }
            list.swapAt(index, index + offset)
        }
    }

    private func change(_ edit: (inout [KeyAction]) -> Void) {
        var list = steps
        edit(&list)
        action.steps = list
    }
}

/// Records a keyboard shortcut by pressing it, or picks a common one.
/// Shortcuts the system takes first, like screenshots, are in the menu.
struct HotkeyField: View {
    @Binding var action: KeyAction
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Shortcut") {
            HStack {
                Button(recording ? "Press the keys…" : action.display ?? "Record") {
                    recording ? stop() : start()
                }
                Menu("Common") {
                    ForEach(HotkeyPreset.groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.presets, id: \.self) { preset in
                                Button("\(preset.name)   \(preset.display)") { action = .hotkey(preset) }
                            }
                        }
                    }
                }
                .fixedSize()
            }
        }
        .onDisappear { stop() }
        if recording {
            Text("Press the shortcut you want. Esc cancels.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            var modifiers: [String] = []
            if flags.contains(.control) { modifiers.append("control") }
            if flags.contains(.option) { modifiers.append("option") }
            if flags.contains(.shift) { modifiers.append("shift") }
            if flags.contains(.command) { modifiers.append("command") }
            let code = Int(event.keyCode)
            MainActor.assumeIsolated {
                if code != 53 || !modifiers.isEmpty {
                    var recorded = KeyAction(.hotkey)
                    recorded.keyCode = code
                    recorded.modifiers = modifiers
                    recorded.display = HotkeyPreset.display(keyCode: code, modifiers: modifiers)
                    action = recorded
                }
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Says when a key's hotkeys, typing or media keys can't work yet.
struct AccessNotice: View {
    let service: AppDrawerService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Hotkeys, typing and media keys need EdgeControl switched on in System Settings › Privacy & Security › Accessibility.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            Button("Open Accessibility Settings") { service.openAccessibilitySettings() }
        }
    }
}

/// Installed apps, searchable, for an app key or an app's icon on a key.
struct AppChooser: View {
    let service: AppDrawerService
    let done: (String?) -> Void
    @State private var query = ""

    var body: some View {
        let apps = service.installed.filter { id in
            query.isEmpty || (service.appName(id) ?? "").localizedCaseInsensitiveContains(query)
                || id.localizedCaseInsensitiveContains(query)
        }
        VStack(spacing: 0) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            List(apps, id: \.self) { id in
                Button {
                    done(id)
                } label: {
                    HStack {
                        if let icon = service.appIcon(id) {
                            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                        }
                        Text(service.appName(id) ?? id)
                        Spacer()
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
    }
}
