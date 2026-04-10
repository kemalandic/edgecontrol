import SwiftUI

/// iCUE-style 270-degree arc gauge. Used by CPU, Memory, Temp, and other gauge widgets.
/// Adapts to available size — font sizes scale with frame AND theme fontScale.
struct RadialGaugeView: View {
    let value: Double
    let maxValue: Double
    let label: String
    let displayValue: String
    let unit: String
    let accentColor: Color
    var showLabel: Bool = true

    @Environment(\.themeSettings) private var ts

    private let lineWidth: CGFloat = 12
    private let startAngle: Double = 135
    private let endAngle: Double = 405

    private var progress: Double {
        min(max(value / maxValue, 0), 1)
    }

    private var gaugeColor: Color {
        if progress < 0.5 { return Theme.accentCyan }
        if progress < 0.75 { return Theme.accentYellow }
        return Theme.accentRed
    }

    var body: some View {
        GeometryReader { geo in
            let minDim = min(geo.size.width, geo.size.height)
            let scale = ts.fontScale
            let isCompact = minDim < 150
            // Gauge fonts scale proportionally to gauge size AND respond to font level settings.
            // Dampened ratio (0.5x) — gauge already has large proportional sizes, full ratio overshoots.
            let valueRatio = 1.0 + (ts.fontSizeValue / 28.0 - 1.0) * 0.5
            let captionRatio = 1.0 + (ts.fontSizeCaption / 11.0 - 1.0) * 0.5
            let titleRatio = 1.0 + (ts.fontSizeTitle / 18.0 - 1.0) * 0.5
            let valueFontSize = (isCompact ? minDim * 0.28 : minDim * 0.20) * scale * valueRatio
            let unitFontSize = (isCompact ? minDim * 0.10 : minDim * 0.07) * scale * captionRatio
            let labelFontSize = (isCompact ? minDim * 0.10 : minDim * 0.08) * scale * titleRatio
            let lwScaled = isCompact ? lineWidth * 0.7 : lineWidth
            let design = ts.fontFamily.design

            VStack(spacing: isCompact ? 2 : 6) {
                ZStack {
                    Circle()
                        .fill(Theme.glowGradient(gaugeColor))
                        .scaleEffect(1.3)
                        .opacity(0.4)

                    ArcShape(startAngle: startAngle, endAngle: endAngle)
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lwScaled, lineCap: .round))

                    ArcShape(startAngle: startAngle, endAngle: startAngle + (endAngle - startAngle) * progress)
                        .stroke(
                            AngularGradient(
                                stops: [
                                    .init(color: accentColor, location: 0.0),
                                    .init(color: gaugeColor, location: 1.0)
                                ],
                                center: .center,
                                startAngle: .degrees(startAngle),
                                endAngle: .degrees(startAngle + (endAngle - startAngle) * progress)
                            ),
                            style: StrokeStyle(lineWidth: lwScaled, lineCap: .round)
                        )

                    VStack(spacing: 2) {
                        Text(displayValue)
                            .font(.system(size: valueFontSize, weight: .bold, design: design))
                            .foregroundStyle(Theme.text1(ts))
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5)
                        if !unit.isEmpty && !isCompact {
                            Text(unit)
                                .font(.system(size: unitFontSize, weight: .semibold, design: design))
                                .foregroundStyle(Theme.text2(ts))
                                .textCase(.uppercase)
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)

                if showLabel {
                    Text(label)
                        .font(.system(size: labelFontSize, weight: .bold, design: design))
                        .foregroundStyle(Theme.text2(ts))
                        .textCase(.uppercase)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
