import SwiftUI

/// Touch-friendly vertical scroll container. macOS's stock ScrollView only
/// responds to scroll wheel / two-finger trackpad gestures — it ignores
/// click-and-drag, which is exactly what the Xeneon Edge's TouchscreenDriver
/// emits when a finger drags down the panel.
///
/// This view wires up a DragGesture against an internal offset state +
/// clipping bounds. Drag down → content moves down (recent stuff stays at
/// the top, older items reveal at the bottom). Bounds-clamped so you can't
/// drag past either edge.
public struct TouchScrollView<Content: View>: View {
    private let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var offsetAtDragStart: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollbarOpacity: Double = 0
    @State private var fadeOutWorkItem: DispatchWorkItem?

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        GeometryReader { geo in
            let maxScroll = max(0, contentHeight - geo.size.height)

            ZStack(alignment: .top) {
                content()
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .preference(key: ContentHeightKey.self, value: inner.size.height)
                        }
                    )
                    .offset(y: offset)

                // Subtle scrollbar — fades in during interaction, out at rest.
                if maxScroll > 0 {
                    let clampedForBar = min(0, max(-maxScroll, offset))
                    scrollIndicator(viewportHeight: geo.size.height,
                                    contentHeight: contentHeight,
                                    offset: clampedForBar)
                        .padding(.trailing, 2)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(scrollbarOpacity)
                        .allowsHitTesting(false)
                }
            }
            // The viewport, stated exactly. Two things are load-bearing here.
            //
            // Fixed, not `maxHeight: .infinity`: a flexible frame grows to its
            // child, so once the content is taller than the viewport the frame
            // grows with it and `clipped()` has nothing left to cut — rows
            // spill out over the widget card and the drag area spills too.
            //
            // `.top`, not the default `.center`: the ZStack takes the height of
            // its tallest child, which is the full content. Centering that in
            // the viewport puts offset 0 in the middle of the list, so the rows
            // above it sit outside the clip and no amount of dragging brings
            // them back. Top-aligned, offset 0 is the first row.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        // Cancel any pending fade-out and reveal the bar.
                        fadeOutWorkItem?.cancel()
                        if scrollbarOpacity < 1 {
                            withAnimation(.easeOut(duration: 0.12)) {
                                scrollbarOpacity = 1
                            }
                        }
                        let raw = offsetAtDragStart + value.translation.height
                        offset = TouchScrollView.applyRubberBand(
                            raw: raw,
                            maxScroll: maxScroll,
                            viewportHeight: geo.size.height
                        )
                    }
                    .onEnded { value in
                        let projectedRaw = offsetAtDragStart + value.predictedEndTranslation.height
                        let inBounds = min(0, max(-maxScroll, projectedRaw))

                        // Past-bounds release → fast spring straight back to
                        // legal bounds (one stage, no pause). Bounce comes
                        // from the spring's natural overshoot at low damping.
                        if projectedRaw != inBounds {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.68)) {
                                offset = inBounds
                            }
                            offsetAtDragStart = inBounds
                        } else {
                            // In-bounds release → carry inertia and settle.
                            withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.82)) {
                                offset = inBounds
                            }
                            offsetAtDragStart = inBounds
                        }

                        // Schedule scrollbar fade-out after the spring settles.
                        // Cancelable so a new drag interrupts and re-shows it.
                        fadeOutWorkItem?.cancel()
                        let work = DispatchWorkItem {
                            withAnimation(.easeIn(duration: 0.45)) {
                                scrollbarOpacity = 0
                            }
                        }
                        fadeOutWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
                    }
            )
            .onPreferenceChange(ContentHeightKey.self) { h in
                if h > 0 { contentHeight = h }
            }
        }
    }

    /// iOS-style rubber-band: linear inside the legal range, then asymptotic
    /// resistance once past either edge. Formula matches Apple's pattern
    /// y = (x * d * c) / (d + c * x), where d is viewport dimension and
    /// c ≈ 0.55 — gives a familiar feel without going Calder-mobile.
    private static func applyRubberBand(raw: CGFloat, maxScroll: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let upper: CGFloat = 0
        let lower: CGFloat = -maxScroll
        if raw <= upper && raw >= lower { return raw }
        let c: CGFloat = 0.55
        let d = max(1, viewportHeight)
        if raw > upper {
            let over = raw - upper
            return upper + (over * d * c) / (d + c * over)
        } else {
            let over = lower - raw
            return lower - (over * d * c) / (d + c * over)
        }
    }

    @ViewBuilder
    private func scrollIndicator(viewportHeight: CGFloat, contentHeight: CGFloat, offset: CGFloat) -> some View {
        let thumbRatio = min(1, viewportHeight / max(1, contentHeight))
        let trackHeight = max(0, viewportHeight - 8)
        let thumbHeight = max(20, trackHeight * thumbRatio)
        let scrollableTrack = max(0, trackHeight - thumbHeight)
        let progress = contentHeight > viewportHeight
            ? min(1, max(0, -offset / max(1, contentHeight - viewportHeight)))
            : 0
        let thumbY = scrollableTrack * progress

        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 3, height: thumbHeight)
            .offset(y: thumbY)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
