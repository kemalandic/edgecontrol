import Foundation

/// Just enough of IPP, the Internet Printing Protocol (RFC 8010 and 8011), to
/// ask a printer how it is.
///
/// Every printer that works with AirPrint or Mopria speaks IPP, so one
/// request covers nearly every printer made in the last decade: its state,
/// what is wrong with it, and how much ink or toner is left. The request and
/// the reply are a compact binary format carried over HTTP.
enum IPP {
    /// The attributes the Printers widget asks for.
    static let statusAttributes = [
        "printer-name", "printer-info", "printer-make-and-model", "printer-location",
        "printer-state", "printer-state-reasons", "printer-state-message",
        "printer-is-accepting-jobs", "queued-job-count", "printer-more-info",
        "marker-names", "marker-colors", "marker-levels", "marker-low-levels",
        "marker-high-levels", "marker-types",
    ]

    enum Value: Equatable, Sendable {
        case integer(Int)
        case boolean(Bool)
        case text(String)
        /// Out-of-band values ("unknown", "no-value"), dates, resolutions and
        /// collections: nothing the widget reads.
        case other
    }

    struct Response: Equatable, Sendable {
        /// 0x0000–0x00FF is success; 0x0400 and up are client errors, 0x0500 and up server errors.
        let statusCode: Int
        /// Printer attributes, each with all its values in order.
        let attributes: [String: [Value]]

        var succeeded: Bool { statusCode < 0x0100 }

        func integers(_ name: String) -> [Int] {
            attributes[name, default: []].compactMap { if case .integer(let v) = $0 { v } else { nil } }
        }

        func strings(_ name: String) -> [String] {
            attributes[name, default: []].compactMap { if case .text(let v) = $0 { v } else { nil } }
        }

        func string(_ name: String) -> String? { strings(name).first }
        func integer(_ name: String) -> Int? { integers(name).first }
    }

    enum DecodingError: Error, Equatable {
        case truncated
    }

    // MARK: - Request

    /// A Get-Printer-Attributes request for `printerURI`.
    static func getPrinterAttributes(
        printerURI: String, requested: [String] = statusAttributes, requestID: Int32 = 1
    ) -> Data {
        var data = Data([2, 0])  // IPP 2.0
        data.append(uint16: 0x000B)  // Get-Printer-Attributes
        data.append(int32: requestID)
        data.append(0x01)  // operation-attributes-tag
        data.appendAttribute(tag: 0x47, name: "attributes-charset", value: "utf-8")
        data.appendAttribute(tag: 0x48, name: "attributes-natural-language", value: "en")
        data.appendAttribute(tag: 0x45, name: "printer-uri", value: printerURI)
        for (index, name) in requested.enumerated() {
            // Further values of the same attribute go out with an empty name.
            data.appendAttribute(tag: 0x44, name: index == 0 ? "requested-attributes" : "", value: name)
        }
        data.append(0x03)  // end-of-attributes-tag
        return data
    }

    // MARK: - Response

    static func parse(_ data: Data) throws -> Response {
        var reader = Reader(data: data)
        _ = try reader.uint16()  // version
        let status = Int(try reader.uint16())
        _ = try reader.int32()  // request id

        var attributes: [String: [Value]] = [:]
        var group: UInt8 = 0
        var current: String?
        var collectionDepth = 0

        while !reader.isAtEnd {
            let tag = try reader.byte()
            if tag <= 0x0F {
                // A delimiter: 0x03 ends the message, the others start a group.
                if tag == 0x03 { break }
                group = tag
                current = nil
                continue
            }
            let name = try reader.string(length: Int(try reader.uint16()))
            let value = try reader.bytes(Int(try reader.uint16()))

            // Members of a collection are skipped along with it.
            if tag == 0x34 {
                collectionDepth += 1
                if collectionDepth == 1, !name.isEmpty { current = name }
                continue
            }
            if tag == 0x37 {
                collectionDepth = max(0, collectionDepth - 1)
                if collectionDepth == 0, group == 0x04, let current { attributes[current, default: []].append(.other) }
                continue
            }
            if collectionDepth > 0 { continue }

            if !name.isEmpty { current = name }
            // Only the printer group describes the printer; the operation
            // group repeats the charset and language.
            guard group == 0x04, let current else { continue }
            attributes[current, default: []].append(decode(tag: tag, value: value))
        }
        return Response(statusCode: status, attributes: attributes)
    }

    private static func decode(tag: UInt8, value: Data) -> Value {
        switch tag {
        case 0x21, 0x23:  // integer, enum
            guard value.count == 4 else { return .other }
            return .integer(Int(Int32(bigEndian: value.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })))
        case 0x22:  // boolean
            return value.first.map { .boolean($0 != 0) } ?? .other
        case 0x35, 0x36:  // textWithLanguage, nameWithLanguage: language, then text
            var inner = Reader(data: value)
            guard let languageLength = try? inner.uint16(), (try? inner.bytes(Int(languageLength))) != nil,
                let textLength = try? inner.uint16(), let text = try? inner.string(length: Int(textLength))
            else { return .other }
            return .text(text)
        case 0x30, 0x41...0x49:  // octetString and the string types: text, name, keyword, uri, …
            return .text(String(decoding: value, as: UTF8.self))
        default:
            return .other
        }
    }

    private struct Reader {
        let data: Data
        var offset: Int

        init(data: Data) {
            self.data = data
            self.offset = data.startIndex
        }

        var isAtEnd: Bool { offset >= data.endIndex }

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, offset + count <= data.endIndex else { throw DecodingError.truncated }
            defer { offset += count }
            return data[offset..<offset + count]
        }

        mutating func byte() throws -> UInt8 { try bytes(1).first! }

        mutating func uint16() throws -> UInt16 {
            let b = try bytes(2)
            return UInt16(b[b.startIndex]) << 8 | UInt16(b[b.startIndex + 1])
        }

        mutating func int32() throws -> Int32 {
            let b = try bytes(4)
            return Int32(bitPattern: b.reduce(0) { $0 << 8 | UInt32($1) })
        }

        mutating func string(length: Int) throws -> String {
            String(decoding: try bytes(length), as: UTF8.self)
        }
    }
}

extension Data {
    fileprivate mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    fileprivate mutating func append(int32 value: Int32) {
        let bits = UInt32(bitPattern: value)
        append(contentsOf: [UInt8(bits >> 24), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits & 0xFF)])
    }

    fileprivate mutating func appendAttribute(tag: UInt8, name: String, value: String) {
        append(tag)
        append(uint16: UInt16(name.utf8.count))
        append(contentsOf: Array(name.utf8))
        append(uint16: UInt16(value.utf8.count))
        append(contentsOf: Array(value.utf8))
    }
}
