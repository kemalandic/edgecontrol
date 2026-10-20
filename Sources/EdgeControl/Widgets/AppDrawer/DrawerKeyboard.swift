import SwiftUI

/// The tile's own keyboard, for searching and naming on the dashboard,
/// which has no keyboard of its own. On a short tile it has letters only,
/// with the hide key beside Z, so some of the list still shows.
struct DrawerKeyboard: View {
    enum Press: Equatable {
        case character(String)
        case backspace
        case clear
        case hide
    }

    let compact: Bool
    /// A row of the characters links and addresses need.
    let symbols: Bool
    let registry: TouchZoneRegistry
    let idPrefix: String
    let press: @MainActor (Press) -> Void

    @Environment(\.themeSettings) private var ts

    var body: some View {
        VStack(spacing: 5) {
            if !compact { characterRow("1234567890") }
            if symbols { characterRow(".:/-_@?=&#") }
            characterRow("qwertyuiop")
            characterRow("asdfghjkl")
            HStack(spacing: 5) {
                if compact { key("hide", symbol: "keyboard.chevron.compact.down", wide: true, .hide) }
                ForEach(Array("zxcvbnm").map(String.init), id: \.self) { key($0, .character($0)) }
                key("backspace", symbol: "delete.left", wide: true, .backspace)
            }
            if !compact {
                HStack(spacing: 5) {
                    key("hide", symbol: "keyboard.chevron.compact.down", wide: true, .hide)
                    key("space", label: "space", .character(" "))
                    key("clear", label: "clear", wide: true, .clear)
                }
            }
        }
    }

    private func characterRow(_ characters: String) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(characters).map(String.init), id: \.self) { key($0, .character($0)) }
        }
    }

    private func key(
        _ id: String, label: String? = nil, symbol: String? = nil, wide: Bool = false, _ value: Press
    ) -> some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            } else {
                Text(label ?? id).font(
                    .system(size: 15 * ts.fontScale, weight: .semibold, design: ts.fontFamily.design))
            }
        }
        .foregroundStyle(Theme.text1(ts))
        .frame(maxWidth: wide ? 56 : .infinity, minHeight: compact ? 28 : 32)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .touchTappable(id: "\(idPrefix)-key-\(id)", registry: registry) {
            Task { @MainActor in press(value) }
        }
    }
}

// MARK: - Touch zones in a scrolling list

private struct TouchViewportKey: EnvironmentKey {
    static let defaultValue: CGRect? = nil
}

extension EnvironmentValues {
    /// The part of the dashboard a scrolling list shows, in touch
    /// coordinates. Rows outside it don't take taps.
    var touchViewport: CGRect? {
        get { self[TouchViewportKey.self] }
        set { self[TouchViewportKey.self] = newValue }
    }
}

/// Like `touchTappable`, for a row in a scrolling list: only the part of
/// the row the list shows is a touch zone, so a row scrolled out of the
/// tile can't take taps meant for the widget beside it.
private struct ClippedTouchTappable: ViewModifier {
    let id: String
    let registry: TouchZoneRegistry
    let action: @Sendable () -> Void
    @Environment(\.touchViewport) private var viewport

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .background(
                GeometryReader { geo in
                    let frame = geo.frame(in: .named(TouchCoordinate.name))
                    Color.clear
                        .onAppear { update(frame) }
                        .onChange(of: frame) { _, newFrame in update(newFrame) }
                        .onChange(of: viewport) { _, _ in update(frame) }
                }
            )
            .onDisappear { registry.unregister(id: id) }
    }

    private func update(_ frame: CGRect) {
        let shown = viewport.map { frame.intersection($0) } ?? frame
        if shown.isNull || shown.width < 8 || shown.height < 8 {
            registry.unregister(id: id)
        } else {
            registry.register(id: id, frame: shown, action: action)
        }
    }
}

extension View {
    func listTouchTappable(id: String, registry: TouchZoneRegistry, action: @escaping @Sendable () -> Void) -> some View
    {
        modifier(ClippedTouchTappable(id: id, registry: registry, action: action))
    }
}
