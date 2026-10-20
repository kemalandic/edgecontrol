import SwiftUI

/// View modifier that makes any view tappable via both mouse click AND HID touch input.
/// Registers the view's frame as a touch zone in TouchZoneRegistry for hardware touch support.
struct TouchTappable: ViewModifier {
    let id: String
    let registry: TouchZoneRegistry
    let layer: Int
    let action: @Sendable () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .named(TouchCoordinate.name))
                            registry.register(id: id, frame: frame, layer: layer, action: action)
                        }
                        .onChange(of: geo.frame(in: .named(TouchCoordinate.name))) { _, newFrame in
                            registry.register(id: id, frame: newFrame, layer: layer, action: action)
                        }
                }
            )
            .onDisappear {
                registry.unregister(id: id)
            }
    }
}

extension View {
    /// Make this view tappable via both mouse and HID touch input. `layer`
    /// is above 0 only for views drawn over the dashboard (see `TouchZone`).
    func touchTappable(
        id: String, registry: TouchZoneRegistry, layer: Int = 0, action: @escaping @Sendable () -> Void
    ) -> some View {
        modifier(TouchTappable(id: id, registry: registry, layer: layer, action: action))
    }
}
