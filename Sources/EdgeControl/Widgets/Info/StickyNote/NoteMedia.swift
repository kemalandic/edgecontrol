import Foundation

/// Images in a note: where the file goes, and how the note points at it.
///
/// RTF carries no images, so an image cannot live inside the note the way its
/// text does. The two ways out were to change the storage format to RTFD — a
/// package, which would end "open the folder and there are your notes" — or to
/// keep the image beside the note and leave a reference in it. This is the
/// second.
///
/// The reference is a link, because links are the one rich-text attribute that
/// survives RTF, carries a string, and already means "this stands for
/// something else". The same trick the checkboxes use: the file keeps
/// characters, the view draws something else. A note opened in TextEdit shows
/// a link to the image sitting next to it rather than nothing at all.
public enum NoteMedia {

    /// Marks a link as pointing at a note's own image rather than at the web.
    public static let scheme = "edgecontrol-media"

    /// Where a note's images live, relative to the notes folder.
    public static func relativeFolder(for noteId: String) -> String {
        "Media/\(noteId)"
    }

    /// The link a media token carries.
    public static func link(forFile name: String) -> String {
        "\(scheme):\(name)"
    }

    /// The file a media link points at, or nil when the link is an ordinary
    /// one. Names are checked rather than trusted: a link is text in a file
    /// that can be edited or imported from elsewhere, and a name with a path
    /// in it would reach outside the note's own folder.
    public static func file(fromLink link: String) -> String? {
        let prefix = scheme + ":"
        guard link.hasPrefix(prefix) else { return nil }
        let name = String(link.dropFirst(prefix.count))
        return isSafeFilename(name) ? name : nil
    }

    /// A plain name: no separators, no traversal, no hidden files.
    public static func isSafeFilename(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return false }
        guard name != ".", name != "..", !name.hasPrefix(".") else { return false }
        return !name.contains("\0")
    }

    // MARK: - What was pasted

    /// The file extension for image data, read from what the bytes actually
    /// are rather than from what the pasteboard says they are.
    ///
    /// Returns nil for anything unrecognised, and the caller refuses the
    /// paste: writing bytes of an unknown kind into the notes folder under a
    /// guessed extension helps nobody.
    public static func fileExtension(for data: Data) -> String? {
        func starts(with bytes: [UInt8]) -> Bool {
            guard data.count >= bytes.count else { return false }
            return Array(data.prefix(bytes.count)) == bytes
        }

        if starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if starts(with: [0x47, 0x49, 0x46, 0x38]) { return "gif" }
        if starts(with: [0x49, 0x49, 0x2A, 0x00]) || starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if starts(with: [0x42, 0x4D]) { return "bmp" }

        // ISO base media: the brand sits after a four-byte length and "ftyp".
        if data.count >= 12, Array(data[4..<8]) == Array("ftyp".utf8) {
            switch String(decoding: data[8..<12], as: UTF8.self) {
            case "heic", "heix", "hevc", "mif1", "msf1": return "heic"
            case "avif", "avis": return "avif"
            default: return nil
            }
        }
        return nil
    }

    /// A name for freshly pasted image data.
    ///
    /// The ordinal keeps names readable in the folder; the suffix keeps two
    /// images pasted in the same second apart.
    public static func filename(for data: Data, ordinal: Int, suffix: String) -> String? {
        guard let ext = fileExtension(for: data) else { return nil }
        return "image-\(ordinal)-\(suffix).\(ext)"
    }

    /// What a media token shows when its file cannot be drawn — which is what
    /// a plain-text reader sees too, so it names the file rather than saying
    /// something went wrong.
    public static func placeholderText(for name: String) -> String {
        name
    }
}
