import AppKit
import SwiftUI

// The checkbox drawn into the text, rather than a character typed into it.

final class CheckboxAttachment: NSTextAttachment {
    var checked = false

    static func make(checked: Bool, font: NSFont, stroke: NSColor, accent: NSColor) -> CheckboxAttachment {
        let side = (font.pointSize * 1.2).rounded()
        let attachment = CheckboxAttachment()
        attachment.checked = checked
        attachment.image = drawImage(checked: checked, side: side, stroke: stroke, accent: accent)
        // Center against the cap height so the box reads as part of the line.
        attachment.bounds = CGRect(
            x: 0, y: (font.capHeight - side) / 2, width: side, height: side
        )
        return attachment
    }

    private static func drawImage(checked: Bool, side: CGFloat, stroke: NSColor, accent: NSColor) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)
            let radius = side * 0.24
            let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
            if checked {
                accent.setFill()
                path.fill()
                // Checkmark in whichever of black/white reads against the accent.
                let rgb = accent.usingColorSpace(.deviceRGB)
                let luminance =
                    rgb.map {
                        0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent
                    } ?? 1
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: side * 0.26, y: side * 0.52))
                mark.line(to: NSPoint(x: side * 0.44, y: side * 0.32))
                mark.line(to: NSPoint(x: side * 0.76, y: side * 0.70))
                mark.lineWidth = max(1.5, side * 0.14)
                mark.lineCapStyle = .round
                mark.lineJoinStyle = .round
                (luminance > 0.6 ? NSColor.black.withAlphaComponent(0.85) : .white).setStroke()
                mark.stroke()
            } else {
                stroke.withAlphaComponent(0.75).setStroke()
                path.lineWidth = max(1.5, side * 0.11)
                path.stroke()
            }
            return true
        }
    }
}
