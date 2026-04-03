import SwiftUI

/// Coordinate space name used for all touch zone calculations.
/// Must match the coordinateSpace set on the root dashboard view.
enum TouchCoordinate {
    static let name = "dashboard-touch"
}

/// A button that registers itself as a touch zone for HID touch tap detection.
/// Works both with normal mouse clicks AND HID touch taps.
struct TouchButton: View {
    let id: String
    let label: String
    let isActive: Bool
    let activeColor: Color
    let registry: TouchZoneRegistry
    let action: @Sendable () -> Void

    var body: some View {
        Text(label)
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(isActive ? activeColor : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isActive ? activeColor.opacity(0.12) : Theme.backgroundCard,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? activeColor.opacity(0.3) : Theme.borderSubtle, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .named(TouchCoordinate.name))
                            registry.register(id: id, frame: frame, action: action)
                        }
                        .onChange(of: geo.frame(in: .named(TouchCoordinate.name))) { _, newFrame in
                            registry.register(id: id, frame: newFrame, action: action)
                        }
                }
            )
            .onDisappear {
                registry.unregister(id: id)
            }
    }
}
