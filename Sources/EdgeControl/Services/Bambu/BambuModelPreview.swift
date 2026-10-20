import Compression
import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Network

/// The plate as the slicer drew it, from the job's .3mf file.
public struct BambuModelPreview: @unchecked Sendable {
    public let image: CGImage
    /// Where the model sits in the picture, as fractions of its size from the
    /// top left. The widget fills this in from the bottom as the print goes.
    public let modelBounds: CGRect
    /// Black or dark grey filament, which would vanish on a dark dashboard.
    public let isDark: Bool

    init?(png: Data) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        self.image = image

        // A 64×64 copy is plenty to find the model and judge its colour.
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        var minX = side
        var minY = side
        var maxX = -1
        var maxY = -1
        var luminance = 0.0
        var counted = 0
        if drawn {
            // Rows run top to bottom in the bitmap's memory.
            for y in 0..<side {
                for x in 0..<side {
                    let index = (y * side + x) * 4
                    let alpha = Int(pixels[index + 3])
                    guard alpha > 25 else { continue }
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    guard alpha > 128 else { continue }
                    let scale = 255.0 / Double(alpha)
                    let red = Double(pixels[index]) * scale / 255
                    let green = Double(pixels[index + 1]) * scale / 255
                    let blue = Double(pixels[index + 2]) * scale / 255
                    luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
                    counted += 1
                }
            }
        }
        modelBounds =
            maxX >= minX
            ? CGRect(
                x: Double(minX) / Double(side), y: Double(minY) / Double(side),
                width: Double(maxX - minX + 1) / Double(side), height: Double(maxY - minY + 1) / Double(side))
            : CGRect(x: 0, y: 0, width: 1, height: 1)
        isDark = counted > 0 && luminance / Double(counted) < 0.3
    }
}

/// Picks the plate picture out of a .3mf file as it downloads.
///
/// A .3mf is a ZIP. Bambu Studio and OrcaSlicer write the plate pictures
/// first and the G-code last, and Bambu printers serve files without
/// support for starting partway, so reading from the start and stopping
/// once the picture is in costs about 100 KB however big the project is.
/// Which plate is printing comes from the entry named after it
/// ("Metadata/plate_2.json", "Metadata/plate_2.gcode").
struct ThreeMFPreviewReader {
    enum Result: Equatable {
        case needMore
        case found(Data)
        case missing
    }

    private var buffer = Data()
    private var offset = 0
    private var previews: [Int: Data] = [:]
    private var plate: Int?
    private var ended = false
    /// How far the search for the current entry's descriptor has got, so a
    /// long entry isn't searched from its start on every read.
    private var scannedTo = 0
    /// From a file name like "Shelf_plate_2.3mf", used only if the file never says.
    private let plateHint: Int?
    private(set) var bytesRead = 0

    init(fileName: String = "") {
        plateHint = Self.number(in: fileName, pattern: #"_plate_(\d+)(\.gcode)?\.3mf$"#)
    }

    mutating func append(_ data: Data) {
        buffer.append(data)
        bytesRead += data.count
    }

    mutating func parse() -> Result {
        while !ended {
            if let plate, let png = previews[plate] { return .found(png) }
            guard readEntry() else { return .needMore }
        }
        return bestGuess()
    }

    /// The whole file has arrived: settle for the likeliest picture.
    mutating func finish() -> Result {
        ended = true
        if let plate, let png = previews[plate] { return .found(png) }
        return bestGuess()
    }

    private func bestGuess() -> Result {
        if let plate = plate ?? plateHint, let png = previews[plate] { return .found(png) }
        if previews.count == 1, let png = previews.values.first { return .found(png) }
        if let first = previews.keys.min(), plate == nil, plateHint == nil { return .found(previews[first]!) }
        return .missing
    }

    /// Reads one entry if it has fully arrived; false when more bytes are needed.
    private mutating func readEntry() -> Bool {
        let start = buffer.startIndex + offset
        guard buffer.count - offset >= 30 else { return false }
        let signature = uint32(at: start)
        guard signature == 0x0403_4B50 else {
            // The central directory: no more file entries.
            ended = true
            return true
        }
        let flags = uint16(at: start + 6)
        let method = uint16(at: start + 8)
        var compressedSize = Int(uint32(at: start + 18))
        var size = Int(uint32(at: start + 22))
        let nameLength = Int(uint16(at: start + 26))
        let extraLength = Int(uint16(at: start + 28))
        guard buffer.count - offset >= 30 + nameLength + extraLength else { return false }
        let name = String(decoding: buffer[(start + 30)..<(start + 30 + nameLength)], as: UTF8.self)
        let dataStart = start + 30 + nameLength + extraLength

        if plate == nil,
            let number = Self.number(in: name, pattern: #"^Metadata/plate_(\d+)\.(json|gcode|gcode\.md5)$"#)
        {
            plate = number
            if previews[number] != nil { return true }
        }

        let hasDescriptor = flags & 0x08 != 0
        var descriptorLength = 0
        if hasDescriptor && compressedSize == 0 {
            // Sizes follow the data: find the descriptor whose size matches
            // the distance to it.
            guard let found = descriptor(from: dataStart) else { return false }
            compressedSize = found.compressedSize
            size = found.size
            descriptorLength = 16
        } else if hasDescriptor {
            descriptorLength = 16
        }
        guard buffer.endIndex - dataStart >= compressedSize + descriptorLength else { return false }

        if let number = Self.number(in: name, pattern: #"^Metadata/plate_(\d+)\.png$"#) {
            let stored = Data(buffer[dataStart..<(dataStart + compressedSize)])
            switch method {
            case 0: previews[number] = stored
            case 8: previews[number] = Self.inflate(stored, size: size)
            default: break
            }
        }
        offset = dataStart + compressedSize + descriptorLength - buffer.startIndex
        scannedTo = 0
        // Nothing before here is needed again.
        if offset > 1 << 20 {
            buffer = Data(buffer[(buffer.startIndex + offset)...])
            offset = 0
            scannedTo = 0
        }
        return true
    }

    private mutating func descriptor(from dataStart: Int) -> (compressedSize: Int, size: Int)? {
        var search = max(dataStart, scannedTo)
        let marker = Data([0x50, 0x4B, 0x07, 0x08])
        while let found = buffer.range(of: marker, in: search..<buffer.endIndex) {
            guard buffer.endIndex - found.lowerBound >= 16 else {
                scannedTo = found.lowerBound
                return nil
            }
            let compressedSize = Int(uint32(at: found.lowerBound + 8))
            if compressedSize == found.lowerBound - dataStart {
                return (compressedSize, Int(uint32(at: found.lowerBound + 12)))
            }
            search = found.lowerBound + 1
        }
        // The marker may be split across reads: look again from its possible start.
        scannedTo = max(dataStart, buffer.endIndex - 3)
        return nil
    }

    private func uint16(at index: Int) -> UInt16 {
        UInt16(buffer[index]) | UInt16(buffer[index + 1]) << 8
    }

    private func uint32(at index: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(buffer[index + $1]) << (8 * UInt32($1)) }
    }

    private static func number(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }

    /// ZIP's deflate is raw DEFLATE, which is what Compression calls ZLIB.
    static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0, size <= 32 << 20, !data.isEmpty else { return nil }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, size,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? output : nil
    }
}

/// FTP replies: a three-digit code, and on a multi-line reply further lines
/// until one starts with the same code and a space.
struct FTPReplyReader {
    struct Reply: Equatable {
        let code: Int
        let text: String
    }

    private var buffer = Data()
    private var pending: [String] = []

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    mutating func next() -> Reply? {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            buffer = Data(buffer[(newline + 1)...])
            if pending.isEmpty {
                guard let code = Self.code(line) else { continue }
                if Self.isLast(line) { return Reply(code: code, text: Self.text(of: line)) }
                pending = [line]
            } else {
                pending.append(line)
                if let code = Self.code(line), code == Self.code(pending[0]), Self.isLast(line) {
                    let text = pending.map { Self.text(of: $0) }.joined(separator: "\n")
                    pending.removeAll()
                    return Reply(code: code, text: text)
                }
            }
        }
        return nil
    }

    private static func code(_ line: String) -> Int? {
        guard line.count >= 3, let code = Int(line.prefix(3)), (100...599).contains(code) else { return nil }
        return code
    }

    /// A line without its "230 " or "230-"; lines between have no code.
    private static func text(of line: String) -> String {
        code(line) != nil && line.count >= 4 ? String(line.dropFirst(4)) : line.trimmingCharacters(in: .whitespaces)
    }

    /// "230 Logged in" ends a reply; "230-Welcome" starts a longer one.
    private static func isLast(_ line: String) -> Bool {
        line.count == 3 || line[line.index(line.startIndex, offsetBy: 3)] == " "
    }

    /// "227 Entering Passive Mode (192,168,1,60,195,80)." → 50000.
    static func passivePort(_ text: String) -> Int? {
        guard let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") else { return nil }
        let numbers = text[text.index(after: open)..<close].split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard numbers.count == 6 else { return nil }
        return numbers[4] * 256 + numbers[5]
    }
}

/// Fetches a job's plate picture from the printer over FTPS (TLS from the
/// first byte, port 990), with the same user and access code as MQTT. It
/// reads only as far into the file as the picture, then hangs up.
final class BambuPreviewSession: BambuLink, @unchecked Sendable {
    enum Event: Sendable {
        case preview(BambuModelPreview)
        case failed(String)
    }

    private enum Step {
        case greeting, user, password, protectionBuffer, protection, binary, passive, retrieve, transferring
    }

    static let port: NWEndpoint.Port = 990
    /// Past this, the file isn't laid out the way slicers lay it out.
    static let readLimit = 16 << 20

    private let host: String
    private let accessCode: String
    private var paths: [String]
    private let handler: @MainActor @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "EdgeControl.Bambu.FTP")

    private var control: NWConnection?
    private var data: NWConnection?
    private var replies = FTPReplyReader()
    private var reader = ThreeMFPreviewReader()
    private var step = Step.greeting
    private var finished = false

    /// `paths` are tried in order; the first that exists is read.
    init(
        host: String, accessCode: String, paths: [String], handler: @escaping @MainActor @Sendable (Event) -> Void
    ) {
        self.host = host
        self.accessCode = accessCode
        self.paths = paths
        self.handler = handler
        queue.async { self.open() }
    }

    func cancel() {
        queue.async { self.finish(nil) }
    }

    /// Where a printer keeps a job's file: cloud prints go to /cache, files
    /// sent from the slicer to the top of the SD card.
    static func paths(forJobFile file: String) -> [String] {
        let name = (file as NSString).lastPathComponent
        var paths: [String] = []
        if file.hasPrefix("/") {
            paths.append(file.hasPrefix("/sdcard/") ? String(file.dropFirst("/sdcard".count)) : file)
        }
        paths += ["/cache/\(name)", "/\(name)"]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func open() {
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: Self.port, using: BambuTLS.parameters(queue: queue) { _ in })
        control = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.receiveControl()
            case .waiting(let error), .failed(let error): self?.finish(BambuTLS.describe(error))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveControl() {
        control?.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, done, error in
            guard let self, !self.finished else { return }
            if let content { self.replies.append(content) }
            while !self.finished, let reply = self.replies.next() { self.handle(reply) }
            if done || error != nil { return self.finish("Connection closed") }
            self.receiveControl()
        }
    }

    private func handle(_ reply: FTPReplyReader.Reply) {
        switch (step, reply.code) {
        case (.greeting, 220):
            send("USER bblp", next: .user)
        case (.user, 331):
            send("PASS \(accessCode)", next: .password)
        case (.user, 230), (.password, 230):
            send("PBSZ 0", next: .protectionBuffer)
        case (.password, 530):
            finish("Wrong access code")
        case (.protectionBuffer, 200):
            send("PROT P", next: .protection)
        case (.protection, 200):
            send("TYPE I", next: .binary)
        case (.binary, 200):
            nextPath()
        case (.passive, 227):
            guard let port = FTPReplyReader.passivePort(reply.text), let path = paths.first else {
                return finish("Unexpected reply")
            }
            paths.removeFirst()
            openData(port: port)
            reader = ThreeMFPreviewReader(fileName: path)
            send("RETR \(path)", next: .retrieve)
        case (.retrieve, 125), (.retrieve, 150):
            step = .transferring
        case (.retrieve, 550):
            data?.cancel()
            data = nil
            nextPath()
        case (.transferring, _):
            break  // 226 after the last byte, or 426 after hanging up early.
        default:
            if reply.code >= 400 { finish("Printer said \(reply.code)") }
        }
    }

    private func nextPath() {
        guard !paths.isEmpty else { return finish("Job file not found") }
        send("PASV", next: .passive)
    }

    private func openData(port: Int) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return finish("Unexpected reply") }
        let connection = NWConnection(
            host: NWEndpoint.Host(host), port: port, using: BambuTLS.parameters(queue: queue) { _ in })
        data = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.receiveData()
            case .failed(let error): self?.finish(BambuTLS.describe(error))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveData() {
        data?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] content, _, done, error in
            guard let self, !self.finished else { return }
            if let content { self.reader.append(content) }
            var result = self.reader.parse()
            if result == .needMore, done || error != nil || self.reader.bytesRead > Self.readLimit {
                result = self.reader.finish()
            }
            switch result {
            case .found(let png):
                if let preview = BambuModelPreview(png: png) {
                    self.emit(.preview(preview))
                    self.finish(nil)
                } else {
                    self.finish("Unreadable picture")
                }
            case .missing:
                self.finish("No picture in the job file")
            case .needMore:
                self.receiveData()
            }
        }
    }

    private func send(_ command: String, next: Step) {
        step = next
        control?.send(content: Data((command + "\r\n").utf8), completion: .contentProcessed { _ in })
    }

    private func finish(_ problem: String?) {
        guard !finished else { return }
        finished = true
        data?.cancel()
        data = nil
        if control?.state == .ready {
            control?.send(content: Data("QUIT\r\n".utf8), completion: .contentProcessed { _ in })
        }
        control?.cancel()
        control = nil
        if let problem { emit(.failed(problem)) }
    }

    private func emit(_ event: Event) {
        let handler = handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(event) } }
    }
}
