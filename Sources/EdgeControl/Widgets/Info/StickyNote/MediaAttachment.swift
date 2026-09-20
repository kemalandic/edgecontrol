import AppKit

/// An image drawn into a note, standing in for a file beside it.
///
/// The same arrangement as the checkboxes: what the file holds is characters
/// — here a link carrying the file's name — and what the view shows is drawn.
/// The attachment exists only while the note is open. Serialising maps it
/// back to the link, because RTF has nowhere to put an image.
final class MediaAttachment: NSTextAttachment {
    /// The file this stands for, inside the note's own media folder.
    var filename: String = ""

    /// Wide enough to be worth having, short enough that a note is still a
    /// note. A pasted screenshot is usually far larger than any widget on
    /// the panel, so the default is to fit rather than to crop.
    static let maximumSize = NSSize(width: 420, height: 260)

    static func make(filename: String, data: Data) -> MediaAttachment? {
        guard let image = NSImage(data: data) else { return nil }
        let attachment = MediaAttachment()
        attachment.filename = filename
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: fittedSize(of: image.size))
        return attachment
    }

    /// Scaled down to fit, never up: a 16x16 favicon pasted into a note is a
    /// 16x16 favicon, not a blurry banner.
    static func fittedSize(of size: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return maximumSize }
        let scale = min(maximumSize.width / size.width, maximumSize.height / size.height, 1)
        return NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}
