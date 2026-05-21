import SwiftUI

/// Coordinator other code uses to ask for a confetti burst. Single
/// in-flight burst at a time — celebrate() updates `pendingBurst`,
/// the overlay drains it.
@MainActor
public final class ConfettiCoordinator: ObservableObject {
    public static let shared = ConfettiCoordinator()

    public enum BurstKind {
        case milestone   // MRR boundary crossed — big, gold-heavy
        case conversion  // Free → Paid — medium, warm palette
        case signup      // New signup — small puff, mixed colors
    }

    @Published public var pendingBurst: BurstKind?

    public func celebrate(_ kind: BurstKind) {
        pendingBurst = kind
    }

    public func consume() {
        pendingBurst = nil
    }
}

/// Visual confetti layer. Rendered as the topmost child of DashboardShell
/// (above Pip + brightness dim). Hit-testing off so it never blocks the
/// dashboard underneath.
public struct ConfettiOverlay: View {
    @StateObject private var coord = ConfettiCoordinator.shared
    @State private var bursts: [Burst] = []

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(bursts) { burst in
                    ConfettiBurstView(burst: burst, viewport: geo.size)
                }
            }
            .allowsHitTesting(false)
            .onReceive(coord.$pendingBurst.compactMap { $0 }) { kind in
                spawn(kind: kind, viewport: geo.size)
                coord.consume()
            }
        }
        .allowsHitTesting(false)
    }

    private func spawn(kind: ConfettiCoordinator.BurstKind, viewport: CGSize) {
        let burst = Burst.make(kind: kind, viewport: viewport)
        bursts.append(burst)
        DispatchQueue.main.asyncAfter(deadline: .now() + burst.duration + 0.2) {
            bursts.removeAll { $0.id == burst.id }
        }
    }
}

// MARK: - Burst model

private struct Burst: Identifiable {
    let id = UUID()
    let pieces: [Piece]
    let duration: Double

    struct Piece: Identifiable {
        let id = UUID()
        let color: Color
        let startX: CGFloat
        let endX: CGFloat
        let startY: CGFloat
        let endY: CGFloat
        let endRotation: Double
        let width: CGFloat
        let height: CGFloat
        let isCircle: Bool
        let delay: Double
        let fallDuration: Double
    }

    static func make(kind: ConfettiCoordinator.BurstKind, viewport: CGSize) -> Burst {
        let count: Int
        let palette: [Color]
        let durationRange: ClosedRange<Double>
        switch kind {
        case .milestone:
            count = 180
            palette = [
                Color(red: 1.00, green: 0.80, blue: 0.20), // gold
                Color(red: 1.00, green: 0.55, blue: 0.10), // orange
                Color(red: 1.00, green: 0.90, blue: 0.55), // pale gold
                Color(red: 0.55, green: 0.30, blue: 1.00), // purple
                Color(red: 0.20, green: 0.90, blue: 0.50), // green
                Color(red: 0.00, green: 0.85, blue: 1.00), // cyan
            ]
            durationRange = 3.2...4.6
        case .conversion:
            count = 120
            palette = [
                Color(red: 0.55, green: 0.30, blue: 1.00),
                Color(red: 0.20, green: 0.90, blue: 0.50),
                Color(red: 1.00, green: 0.80, blue: 0.20),
                Color(red: 0.00, green: 0.85, blue: 1.00),
            ]
            durationRange = 2.8...4.0
        case .signup:
            count = 70
            palette = [
                Color(red: 0.96, green: 0.77, blue: 0.09),
                Color(red: 1.00, green: 0.55, blue: 0.30),
                Color(red: 0.20, green: 0.90, blue: 0.50),
            ]
            durationRange = 2.2...3.4
        }

        let width = max(1, viewport.width)
        let height = max(1, viewport.height)

        var pieces: [Piece] = []
        for _ in 0..<count {
            let startX = CGFloat.random(in: 0...width)
            let drift = CGFloat.random(in: -120...120)
            let endX = max(0, min(width, startX + drift))
            let isCircle = Bool.random()
            let isLarge = Double.random(in: 0...1) < 0.2
            let baseW = CGFloat.random(in: isLarge ? 9...14 : 5...9)
            let pieceW = isCircle ? baseW : baseW
            let pieceH = isCircle ? baseW : baseW * CGFloat.random(in: 0.4...0.7)
            let dur = Double.random(in: durationRange)
            pieces.append(Piece(
                color: palette.randomElement()!,
                startX: startX,
                endX: endX,
                startY: -CGFloat.random(in: 20...80),
                endY: height + 40,
                endRotation: Double.random(in: -540...540),
                width: pieceW,
                height: pieceH,
                isCircle: isCircle,
                delay: Double.random(in: 0...0.55),
                fallDuration: dur
            ))
        }
        return Burst(pieces: pieces, duration: durationRange.upperBound + 0.6)
    }
}

private struct ConfettiBurstView: View {
    let burst: Burst
    let viewport: CGSize

    var body: some View {
        ZStack {
            ForEach(burst.pieces) { p in
                PieceView(piece: p)
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .clipped()
    }
}

private struct PieceView: View {
    let piece: Burst.Piece
    @State private var animated = false

    var body: some View {
        Group {
            if piece.isCircle {
                Circle().fill(piece.color)
            } else {
                Rectangle().fill(piece.color)
            }
        }
        .frame(width: piece.width, height: piece.height)
        .rotationEffect(.degrees(animated ? piece.endRotation : 0))
        .position(
            x: animated ? piece.endX : piece.startX,
            y: animated ? piece.endY : piece.startY
        )
        .opacity(animated ? 0 : 1)
        .onAppear {
            // Slight delay then animate to end — eases the fall, fades out
            // near the bottom, spins along the way.
            DispatchQueue.main.asyncAfter(deadline: .now() + piece.delay) {
                withAnimation(.easeIn(duration: piece.fallDuration)) {
                    animated = true
                }
            }
        }
    }
}
