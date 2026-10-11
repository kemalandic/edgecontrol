import Foundation

/// The handful of sizes offered when adding a widget, so choosing one is a
/// single click instead of column/row arithmetic. Pure: takes the widget's
/// range and default plus the page grid, returns named, de-duplicated sizes
/// that the widget supports and the grid can hold.
public struct WidgetSizeOption: Hashable, Sendable {
    public let name: String
    public let size: WidgetSize
}

public enum WidgetSizeOptions {
    public static func options(
        range: WidgetSizeRange, defaultSize: WidgetSize, columns: Int, rows: Int
    )
        -> [WidgetSizeOption]
    {
        // The largest size both the widget and the page allow.
        let maxFit = WidgetSize(
            width: max(range.min.width, min(range.max.width, columns)),
            height: max(range.min.height, min(range.max.height, rows))
        )
        func clamp(_ s: WidgetSize) -> WidgetSize {
            WidgetSize(
                width: min(max(s.width, range.min.width), maxFit.width),
                height: min(max(s.height, range.min.height), maxFit.height)
            )
        }
        let medium = clamp(defaultSize)
        let candidates: [(String, WidgetSize)] = [
            ("Small", clamp(range.min)),
            ("Medium", medium),
            (
                "Large",
                clamp(
                    WidgetSize(
                        width: Int((Double(medium.width + maxFit.width) / 2).rounded()),
                        height: Int((Double(medium.height + maxFit.height) / 2).rounded())
                    ))
            ),
            ("Wide", clamp(WidgetSize(width: medium.width * 2, height: medium.height))),
            ("Tall", clamp(WidgetSize(width: medium.width, height: maxFit.height))),
        ]
        var seen = Set<WidgetSize>()
        var result: [WidgetSizeOption] = []
        for (name, size) in candidates
        where range.contains(size) && size.width <= columns && size.height <= rows && seen.insert(size).inserted {
            result.append(WidgetSizeOption(name: name, size: size))
        }
        return result
    }
}
