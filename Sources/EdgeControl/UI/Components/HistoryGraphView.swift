import SwiftUI

/// Time-series graph with area fill, curved line, and optional axis labels.
/// Adapts to available size and theme settings.
struct HistoryGraphView: View {
    let history: [Double]
    let color: Color
    var showAxisLabels: Bool = true
    var showCurrentDot: Bool = true

    @Environment(\.themeSettings) private var ts

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let isCompact = h < 80

            ZStack(alignment: .bottomLeading) {
                // Grid lines
                if !isCompact {
                    ForEach([0.25, 0.50, 0.75], id: \.self) { level in
                        Path { p in
                            let y = h * (1 - level)
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                        .stroke(Theme.border(ts).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }

                if history.count > 1 {
                    areaPath(in: geo.size)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.30), color.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(in: geo.size)
                        .stroke(color, style: StrokeStyle(lineWidth: isCompact ? 2 : 3, lineCap: .round, lineJoin: .round))

                    if showCurrentDot, let last = history.last {
                        let x = w
                        let y = h * (1 - last)
                        Circle()
                            .fill(color)
                            .frame(width: isCompact ? 6 : 10, height: isCompact ? 6 : 10)
                            .shadow(color: color.opacity(0.6), radius: 4)
                            .position(x: x, y: y)
                    }
                }

                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w, y: h))
                }
                .stroke(Theme.border(ts), lineWidth: 1)
            }
        }
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            guard history.count > 1 else { return }
            let stepX = size.width / CGFloat(max(history.count - 1, 1))
            for (i, val) in history.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - val)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    let px = CGFloat(i - 1) * stepX
                    let py = size.height * (1 - history[i - 1])
                    let mx = (px + x) / 2
                    path.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: mx, y: py),
                                  control2: CGPoint(x: mx, y: y))
                }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        Path { path in
            guard history.count > 1 else { return }
            let stepX = size.width / CGFloat(max(history.count - 1, 1))
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, val) in history.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - val)
                if i == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let px = CGFloat(i - 1) * stepX
                    let py = size.height * (1 - history[i - 1])
                    let mx = (px + x) / 2
                    path.addCurve(to: CGPoint(x: x, y: y),
                                  control1: CGPoint(x: mx, y: py),
                                  control2: CGPoint(x: mx, y: y))
                }
            }
            path.addLine(to: CGPoint(x: CGFloat(history.count - 1) * stepX, y: size.height))
            path.closeSubpath()
        }
    }
}
