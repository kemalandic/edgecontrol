import SwiftUI

/// The Cameras widget's camera list: the cameras on its go2rtc server to
/// choose from, any HLS streams added by URL, and their order.
///
/// An empty list means every camera on the server, so a new widget works as
/// soon as it has a server, and cameras added to go2rtc later just appear.
struct CameraListEditor: View {
    let entry: ConfigSchemaEntry
    @Binding var config: WidgetConfig
    let accent: Color

    @EnvironmentObject private var model: AppModel

    var body: some View {
        CameraListEditorContent(entry: entry, config: $config, accent: accent, service: model.cameraService)
    }
}

private struct CameraListEditorContent: View {
    let entry: ConfigSchemaEntry
    @Binding var config: WidgetConfig
    let accent: Color
    @ObservedObject var service: CameraService

    @State private var newName = ""
    @State private var newURL = ""
    @State private var problem: String?

    private var chosen: [String] { config.stringArray(entry.key) }
    private var server: URL? { Go2RTC.serverURL(from: config.string(CamerasSettings.serverKey)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            if chosen.isEmpty {
                Text(
                    server == nil
                        ? "Set a go2rtc server above, or add an HLS stream." : "Showing every camera on the server."
                )
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            }
            ForEach(Array(chosen.enumerated()), id: \.element) { index, item in
                row(item, at: index)
            }

            if let server {
                serverCameras(server)
            }
            addByURL
        }
        // Read the list as soon as a server is typed, not on the next poll.
        .task(id: server) {
            if let server { await service.refresh(server) }
        }
    }

    private func row(_ item: String, at index: Int) -> some View {
        let camera = CameraSource(entry: item)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(camera?.name ?? item)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(camera?.location ?? "Can't be played")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            iconButton("chevron.up", help: "Move earlier", disabled: index == 0) { move(index, by: -1) }
            iconButton("chevron.down", help: "Move later", disabled: index == chosen.count - 1) { move(index, by: 1) }
            Button {
                config[entry.key] = .stringArray(chosen.filter { $0 != item })
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.accentRed)
            }
            .buttonStyle(.plain)
            .help("Take this camera off the widget")
        }
    }

    private func iconButton(
        _ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .help(help)
    }

    private func move(_ index: Int, by offset: Int) {
        var items = chosen
        let target = index + offset
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        items.swapAt(index, target)
        config[entry.key] = .stringArray(items)
    }

    @ViewBuilder
    private func serverCameras(_ server: URL) -> some View {
        switch service.lists[server] {
        case .loaded(let names):
            let available = names.filter { !chosen.contains($0) }
            if names.isEmpty {
                caption("go2rtc on \(server.host ?? "this server") has no cameras yet.")
            } else if !available.isEmpty {
                Menu(chosen.isEmpty ? "Choose Cameras" : "Add a Camera") {
                    if available.count > 1 {
                        Button("All Cameras") { config[entry.key] = .stringArray(chosen + available) }
                        Divider()
                    }
                    ForEach(available, id: \.self) { name in
                        Button(CameraSource.displayName(forStream: name)) {
                            config[entry.key] = .stringArray(chosen + [name])
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .tint(accent)
                .frame(maxWidth: 200, alignment: .leading)
            }
        case .failed(let reason):
            caption("go2rtc on \(server.host ?? "this server") is \(reason).")
        case .loading, nil:
            caption("Reading cameras from go2rtc…")
        }
    }

    private var addByURL: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("https://…/live.m3u8", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.accentRed)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                caption("Or add an HLS stream by URL.")
            }
        }
    }

    private func add() {
        let url = newURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        if let problem = CameraSource.problem(withURL: url) {
            self.problem = problem
            return
        }
        let item = CameraSource.entry(name: newName, url: url)
        if !chosen.contains(item) {
            config[entry.key] = .stringArray(chosen + [item])
        }
        newName = ""
        newURL = ""
        problem = nil
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
