import SwiftUI

/// 8pt green dot with a radial pulse halo. Drop-in for "live / realtime"
/// indicators like the active-users pill.
public struct PulsingDot: View {
    public var color: Color = Color(red: 0.20, green: 0.90, blue: 0.50)
    public var size: CGFloat = 8

    @State private var pulsing = false

    public init(color: Color = Color(red: 0.20, green: 0.90, blue: 0.50), size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.5))
                .frame(width: size * 2, height: size * 2)
                .scaleEffect(pulsing ? 1.0 : 0.5)
                .opacity(pulsing ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}
