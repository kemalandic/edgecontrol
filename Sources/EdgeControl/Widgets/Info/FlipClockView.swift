import SwiftUI

/// The Clock widget's "Flip Clock" style: a split-flap display. Each digit
/// sits on its own card, split across the middle; when it changes, the top
/// leaf folds down over the old digit and the bottom leaf lands with the new
/// one, as on a mechanical flip clock.
struct FlipClockView: View {
    /// Hours as shown ("9", "09" or "21"); a single digit gets a blank card
    /// in front, as on a 12-hour flip clock.
    let hours: String
    let minutes: String
    /// Nil hides the seconds cards.
    let seconds: String?
    /// "AM"/"PM" in 12-hour mode.
    let meridiem: String?
    /// Shown under the cards when there's room.
    let date: String?

    var body: some View {
        GeometryReader { geo in
            let layout = FlipClockLayout(size: geo.size, seconds: seconds != nil,
                                         meridiem: meridiem != nil, date: date != nil)
            VStack(spacing: layout.dateSpacing) {
                HStack(alignment: .top, spacing: 0) {
                    group(paddedHours, layout)
                    colon(layout)
                    group(minutes, layout)
                    if let seconds {
                        colon(layout)
                        group(seconds, layout)
                    }
                    if let meridiem {
                        FlipCard(value: meridiem, width: layout.meridiemWidth, height: layout.meridiemHeight)
                            .padding(.leading, layout.groupGap)
                    }
                }
                if let date, layout.showsDate {
                    Text(date)
                        .font(.system(size: layout.dateSize, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.55))
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([hours + ":" + minutes, meridiem, date].compactMap { $0 }.joined(separator: " "))
    }

    /// "9" becomes " 9": the blank card stands in for the leading zero.
    private var paddedHours: String { hours.count == 1 ? " " + hours : hours }

    /// Two dots between hours, minutes and seconds, centred on the cards.
    private func colon(_ layout: FlipClockLayout) -> some View {
        VStack(spacing: layout.cardHeight * 0.22) {
            Circle().fill(Color.white.opacity(0.9))
            Circle().fill(Color(white: 0.84).opacity(0.9))
        }
        .frame(width: layout.colonDot, height: layout.colonDot * 2 + layout.cardHeight * 0.22)
        .frame(width: layout.colonWidth, height: layout.cardHeight)
    }

    private func group(_ digits: String, _ layout: FlipClockLayout) -> some View {
        HStack(spacing: layout.cardGap) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                FlipCard(value: String(digit), width: layout.cardWidth, height: layout.cardHeight)
            }
        }
    }
}

/// Card sizes that fit the tile: as large as the width and height allow,
/// keeping the cards' tall proportions.
struct FlipClockLayout {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let cardGap: CGFloat
    let groupGap: CGFloat
    /// The space a colon takes between groups, and its dots' size.
    let colonWidth: CGFloat
    let colonDot: CGFloat
    let meridiemWidth: CGFloat
    let meridiemHeight: CGFloat
    let showsDate: Bool
    let dateSize: CGFloat
    let dateSpacing: CGFloat

    /// Card height to width, as on a real flip clock.
    static let aspect: CGFloat = 1.55

    init(size: CGSize, seconds: Bool, meridiem: Bool, date: Bool) {
        let cards: CGFloat = seconds ? 6 : 4
        let groups: CGFloat = seconds ? 3 : 2
        // Gaps scale with the cards: inside a group, a colon between groups,
        // and the AM/PM card (about half a card wide) with its gap.
        let cardGapRatio: CGFloat = 0.08
        let groupGapRatio: CGFloat = 0.28
        let colonRatio: CGFloat = 0.42
        let meridiemRatio: CGFloat = meridiem ? 0.62 + groupGapRatio : 0
        let widthUnits = cards + (cards - groups) * cardGapRatio + (groups - 1) * colonRatio + meridiemRatio
        let dateReserve: CGFloat = date ? min(28, size.height * 0.16) : 0
        let byWidth = size.width / widthUnits
        let byHeight = (size.height - dateReserve) / Self.aspect
        let width = max(8, min(byWidth, byHeight))
        cardWidth = width
        cardHeight = width * Self.aspect
        cardGap = width * cardGapRatio
        groupGap = width * groupGapRatio
        colonWidth = width * colonRatio
        colonDot = width * 0.13
        meridiemWidth = width * 0.62
        meridiemHeight = width * 0.42
        // The date only when it gets a legible size.
        dateSize = min(16, max(9, dateReserve * 0.55))
        showsDate = date && dateReserve >= 18
        dateSpacing = showsDate ? max(6, dateReserve * 0.3) : 0
    }
}

/// One split-flap card. A new value flips in: the upper leaf (old value)
/// folds down to the middle, then the lower leaf (new value) falls from the
/// middle to rest, revealing the new value's lower half.
struct FlipCard: View {
    let value: String
    let width: CGFloat
    let height: CGFloat

    /// The value at rest (and being flipped to).
    @State private var current: String
    /// The value being flipped away from.
    @State private var previous: String
    /// Upper leaf: 0 (up) to -90 (edge-on at the middle, so out of sight).
    @State private var upperAngle: Double = -90
    /// Lower leaf: 90 (edge-on at the middle) to 0 (down).
    @State private var lowerAngle: Double = 0

    static let flipDuration: Double = 0.18

    init(value: String, width: CGFloat, height: CGFloat) {
        self.value = value
        self.width = width
        self.height = height
        _current = State(initialValue: value)
        _previous = State(initialValue: value)
    }

    var body: some View {
        VStack(spacing: hinge) {
            ZStack {
                half(current, upper: true)
                // The old value's upper half, folding down over the new one.
                half(previous, upper: true)
                    .rotation3DEffect(.degrees(upperAngle), axis: (1, 0, 0), anchor: .bottom, perspective: 0.45)
            }
            ZStack {
                // The old lower half stays until the new leaf covers it.
                half(previous, upper: false)
                half(current, upper: false)
                    .rotation3DEffect(.degrees(lowerAngle), axis: (1, 0, 0), anchor: .top, perspective: 0.45)
            }
        }
        .frame(width: width, height: height)
        // One shadow for the whole card: without the group, each half casts
        // its own and the lower half's darkens the digit above the split.
        .compositingGroup()
        .shadow(color: .black.opacity(0.55), radius: width * 0.06, y: width * 0.04)
        .onChange(of: value) { _, new in flip(to: new) }
    }

    /// The thin dark gap where the card is split.
    private var hinge: CGFloat { max(1, height * 0.008) }

    private func flip(to new: String) {
        guard new != current else { return }
        previous = current
        current = new
        upperAngle = 0
        lowerAngle = 90
        withAnimation(.easeIn(duration: Self.flipDuration)) {
            upperAngle = -90
        } completion: {
            withAnimation(.easeOut(duration: Self.flipDuration)) {
                lowerAngle = 0
            } completion: {
                // At rest: both halves show the new value.
                if current == new { previous = new }
            }
        }
    }

    /// One half of the card: the whole card drawn, clipped to its half, so
    /// the digit is split exactly at the hinge.
    private func half(_ text: String, upper: Bool) -> some View {
        let radius = width * 0.07
        let halfHeight = (height - hinge) / 2
        return ZStack {
            LinearGradient(
                colors: upper
                    ? [Color(white: 0.20), Color(white: 0.15)]
                    : [Color(white: 0.13), Color(white: 0.10)],
                startPoint: .top, endPoint: .bottom)
            Text(text)
                .font(.system(size: height * (text.count > 1 ? 0.36 : 0.78), weight: .heavy))
                .fontWidth(.compressed)
                .monospacedDigit()
                // The lower half sits slightly in shadow, as on the real thing.
                .foregroundStyle(upper ? Color.white : Color(white: 0.84))
                .frame(width: width, height: height)
                .offset(y: upper ? halfHeight / 2 + hinge / 2 : -(halfHeight / 2 + hinge / 2))
        }
        .frame(width: width, height: halfHeight)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: upper ? radius : 0, bottomLeadingRadius: upper ? 0 : radius,
                bottomTrailingRadius: upper ? 0 : radius, topTrailingRadius: upper ? radius : 0,
                style: .continuous))
    }
}
