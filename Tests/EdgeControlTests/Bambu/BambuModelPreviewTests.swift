import Compression
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import EdgeControl

/// A PNG with a filled rectangle on a transparent background.
func testPNG(gray: Double, rect: CGRect = CGRect(x: 16, y: 16, width: 32, height: 16)) -> Data {
    let context = CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(rect)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// Writes a ZIP the way Bambu Studio does: sizes after each entry's data
/// (flag 0x08), not in its header, with pictures stored as they are.
struct ZipWriter {
    private(set) var data = Data()

    mutating func add(_ name: String, _ content: Data, deflate: Bool = false, sizesInHeader: Bool = false) {
        let stored = deflate ? Self.deflate(content) : content
        let flags: UInt16 = sizesInHeader ? 0x800 : 0x808
        append32(0x0403_4B50)
        append16(20)
        append16(flags)
        append16(deflate ? 8 : 0)
        append16(0)
        append16(0)
        append32(0)  // CRC: not checked by the reader
        append32(sizesInHeader ? UInt32(stored.count) : 0)
        append32(sizesInHeader ? UInt32(content.count) : 0)
        append16(UInt16(name.utf8.count))
        append16(0)
        data.append(contentsOf: Array(name.utf8))
        data.append(stored)
        if !sizesInHeader {
            append32(0x0807_4B50)
            append32(0)
            append32(UInt32(stored.count))
            append32(UInt32(content.count))
        }
    }

    mutating func end() {
        append32(0x0201_4B50)  // the central directory starts here
        data.append(Data(repeating: 0, count: 42))
    }

    private mutating func append16(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private mutating func append32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func deflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 1024)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return output.prefix(written)
    }
}

@Suite("Bambu model picture")
struct BambuModelPreviewTests {
    private let plate1 = testPNG(gray: 0.9)
    private let plate2 = testPNG(gray: 0.1)

    /// Laid out like a real job file: pictures, the plate's JSON, then G-code.
    private func jobFile(gcode: Int = 200_000) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data("<Types/>".utf8), deflate: true)
        zip.add("Metadata/plate_1.png", plate1)
        zip.add("Metadata/plate_2.png", plate2)
        zip.add("Metadata/top_2.png", plate1)
        zip.add("Metadata/plate_2.json", Data("{}".utf8), deflate: true)
        zip.add("Metadata/plate_2.gcode", Data(repeating: 0x47, count: gcode))
        zip.end()
        return zip.data
    }

    @Test("finds the printing plate's picture, and stops before the G-code")
    func streams() {
        let file = jobFile()
        var reader = ThreeMFPreviewReader(fileName: "Shelf_plate_2.3mf")
        var result = ThreeMFPreviewReader.Result.needMore
        var offset = 0
        while result == .needMore, offset < file.count {
            reader.append(file[offset..<min(offset + 1000, file.count)])
            offset += 1000
            result = reader.parse()
        }
        #expect(result == .found(plate2))
        // The G-code's own header names the plate too, so reading stops there.
        #expect(reader.bytesRead < file.count / 2)
    }

    @Test("the plate in the file wins over the plate in the name")
    func fileOverName() {
        var reader = ThreeMFPreviewReader(fileName: "Shelf_plate_1.3mf")
        reader.append(jobFile())
        #expect(reader.parse() == .found(plate2))
    }

    @Test("a compressed picture with sizes in its header reads too")
    func deflated() {
        var zip = ZipWriter()
        zip.add("Metadata/plate_3.png", plate1, deflate: true, sizesInHeader: true)
        zip.add("Metadata/plate_3.gcode.md5", Data("x".utf8), sizesInHeader: true)
        zip.end()
        var reader = ThreeMFPreviewReader()
        reader.append(zip.data)
        #expect(reader.parse() == .found(plate1))
    }

    @Test("without a plate entry, the name decides; with neither, a lone picture does")
    func fallbacks() {
        var zip = ZipWriter()
        zip.add("Metadata/plate_1.png", plate1)
        zip.add("Metadata/plate_2.png", plate2)
        zip.end()
        var named = ThreeMFPreviewReader(fileName: "Lid_plate_2.gcode.3mf")
        named.append(zip.data)
        #expect(named.parse() == .found(plate2))

        var lone = ZipWriter()
        lone.add("Metadata/plate_1.png", plate1)
        var reader = ThreeMFPreviewReader(fileName: "Lid.3mf")
        reader.append(lone.data)
        #expect(reader.parse() == .needMore)
        #expect(reader.finish() == .found(plate1))
    }

    @Test("a file without pictures says so")
    func missing() {
        var zip = ZipWriter()
        zip.add("Metadata/plate_1.gcode", Data("G28".utf8))
        zip.end()
        var reader = ThreeMFPreviewReader()
        reader.append(zip.data)
        #expect(reader.parse() == .missing)
    }

    @Test("dark filament is noticed, and the model's place in the picture found")
    func analysis() throws {
        let dark = try #require(BambuModelPreview(png: plate2))
        #expect(dark.isDark)
        // Drawn at y 16…32 from the bottom of a 64-pixel image: 0.5…0.75 from the top.
        #expect(abs(dark.modelBounds.minX - 0.25) < 0.02)
        #expect(abs(dark.modelBounds.width - 0.5) < 0.02)
        #expect(abs(dark.modelBounds.minY - 0.5) < 0.02)
        #expect(abs(dark.modelBounds.height - 0.25) < 0.02)
        #expect(try #require(BambuModelPreview(png: plate1)).isDark == false)
        #expect(BambuModelPreview(png: Data("not a picture".utf8)) == nil)
    }

    @Test(
        "job files are looked for where printers keep them",
        arguments: [
            ("Shelf_plate_2.3mf", ["/cache/Shelf_plate_2.3mf", "/Shelf_plate_2.3mf"]),
            ("/sdcard/Lid.gcode.3mf", ["/Lid.gcode.3mf", "/cache/Lid.gcode.3mf"]),
            ("/cache/Lid.3mf", ["/cache/Lid.3mf", "/Lid.3mf"]),
        ])
    func paths(file: String, paths: [String]) {
        #expect(BambuPreviewSession.paths(forJobFile: file) == paths)
    }

    @Test("the model fills in with the progress bar's percentage, not by layer")
    func printedFraction() throws {
        let printing = BambuStatus(
            try bambuJSON(#"{"gcode_state":"RUNNING","mc_percent":63,"layer_num":14,"total_layer_num":122}"#))
        #expect(printing.printedFraction == 0.63)
        #expect(BambuStatus(try bambuJSON(#"{"gcode_state":"FINISH"}"#)).printedFraction == 1)
        #expect(BambuStatus(try bambuJSON(#"{"gcode_state":"PREPARE","mc_percent":3}"#)).printedFraction == 0)
        #expect(BambuStatus(try bambuJSON(#"{"gcode_state":"RUNNING","mc_percent":40}"#)).printedFraction == 0.4)
    }
}

@Suite("FTP replies")
struct FTPReplyReaderTests {
    @Test("one-line replies, split across reads")
    func single() {
        var reader = FTPReplyReader()
        reader.append(Data("220 BBL-P003 FTP Ser".utf8))
        #expect(reader.next() == nil)
        reader.append(Data("ver\r\n331 \r\n".utf8))
        #expect(reader.next() == .init(code: 220, text: "BBL-P003 FTP Server"))
        #expect(reader.next() == .init(code: 331, text: ""))
        #expect(reader.next() == nil)
    }

    @Test("a multi-line reply ends at its code followed by a space")
    func multiline() {
        var reader = FTPReplyReader()
        reader.append(Data("230-Welcome\r\n to the printer\r\n230 Logged in\r\n".utf8))
        #expect(reader.next() == .init(code: 230, text: "Welcome\nto the printer\nLogged in"))
    }

    @Test("the passive port comes from the last two numbers")
    func passive() {
        #expect(FTPReplyReader.passivePort("Entering Passive Mode (192,168,1,60,195,80).") == 50000)
        #expect(FTPReplyReader.passivePort("Entering Passive Mode") == nil)
    }
}
