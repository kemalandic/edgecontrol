import SwiftUI

struct WidgetGaugeView: View {
    let value: Double     // 0-100
    let label: String
    let displayValue: String
    let accentColor: Color

    private let lineWidth: CGFloat = 8
    private let startAngle: Double = 135
    private let endAngle: Double = 405

    private var progress: Double { min(max(value / 100, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let isCompact = size < 80

            VStack(spacing: isCompact ? 1 : 4) {
                ZStack {
                    // Background arc
                    Arc(startAngle: .degrees(startAngle), endAngle: .degrees(endAngle))
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                    // Value arc
                    Arc(startAngle: .degrees(startAngle),
                        endAngle: .degrees(startAngle + (endAngle - startAngle) * progress))
                        .stroke(accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                    // Center text
                    Text(displayValue)
                        .font(.system(size: isCompact ? size * 0.22 : size * 0.2, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .aspectRatio(1, contentMode: .fit)

                if !isCompact {
                    Text(label)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 6
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
