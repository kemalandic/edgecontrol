import Foundation
import Testing
@testable import EdgeControl

/// Loads a recorded IPP reply from the test bundle.
func ippFixture(_ name: String) -> Data {
    let url = Bundle(for: StubTransport.self).url(forResource: name, withExtension: "ipp")
    guard let url, let data = try? Data(contentsOf: url) else {
        fatalError("fixture \(name).ipp not found in the test bundle — check project.yml resources")
    }
    return data
}

/// Builds an IPP reply by hand: a header, then attributes in the printer group.
func ippReply(status: UInt16 = 0, _ attributes: [(tag: UInt8, name: String, value: [UInt8])]) -> Data {
    var data = Data([2, 0, UInt8(status >> 8), UInt8(status & 0xFF), 0, 0, 0, 1, 0x04])
    for attribute in attributes {
        data.append(attribute.tag)
        data.append(contentsOf: [UInt8(attribute.name.utf8.count >> 8), UInt8(attribute.name.utf8.count & 0xFF)])
        data.append(contentsOf: Array(attribute.name.utf8))
        data.append(contentsOf: [UInt8(attribute.value.count >> 8), UInt8(attribute.value.count & 0xFF)])
        data.append(contentsOf: attribute.value)
    }
    data.append(0x03)
    return data
}

func int32Bytes(_ value: Int32) -> [UInt8] {
    let bits = UInt32(bitPattern: value)
    return [UInt8(bits >> 24), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits & 0xFF)]
}

@Suite("IPP")
struct IPPTests {
    @Test("a Get-Printer-Attributes request has the header, operation group and terminator RFC 8010 asks for")
    func request() {
        let data = IPP.getPrinterAttributes(
            printerURI: "ipp://192.168.1.150:631/ipp/print", requested: ["printer-state", "marker-levels"],
            requestID: 7)
        let bytes = [UInt8](data)

        // Version 2.0, operation 0x000B, request id 7, operation-attributes-tag.
        #expect(Array(bytes.prefix(9)) == [2, 0, 0, 0x0B, 0, 0, 0, 7, 0x01])
        #expect(bytes.last == 0x03)
        #expect(data.range(of: Data("ipp://192.168.1.150:631/ipp/print".utf8)) != nil)
        // The first requested attribute carries the name; the next goes out nameless.
        #expect(data.range(of: Data([0x44, 0, 20] + Array("requested-attributes".utf8) + [0, 13])) != nil)
        #expect(data.range(of: Data([0x44, 0, 0, 0, 13] + Array("marker-levels".utf8))) != nil)
    }

    @Test("reads a real HP reply: state, and each marker attribute with all its values")
    func parsesHP() throws {
        let reply = try IPP.parse(ippFixture("ipp-hp-smart-tank"))

        #expect(reply.succeeded)
        #expect(reply.integer("printer-state") == 3)
        #expect(reply.string("printer-info") == "HP Smart Tank 6000 series [115A08]")
        #expect(
            reply.strings("marker-names") == [
                "cyan cartridge", "magenta cartridge", "yellow cartridge", "black cartridge",
            ])
        #expect(reply.integers("marker-levels") == [100, 100, 100, 100])
        #expect(reply.attributes["printer-is-accepting-jobs"] == [.boolean(true)])
        // The operation group's charset and language are not printer attributes.
        #expect(reply.attributes["attributes-charset"] == nil)
    }

    @Test("reads a printer that reports no supplies")
    func parsesEpson() throws {
        let reply = try IPP.parse(ippFixture("ipp-epson-sc-f100"))
        #expect(reply.string("printer-make-and-model") == "EPSON SC-F100 Series")
        #expect(reply.strings("marker-names").isEmpty)
    }

    @Test("a cut-off reply is an error, not a half-read printer")
    func truncated() {
        let data = ippFixture("ipp-hp-smart-tank")
        #expect(throws: IPP.DecodingError.truncated) { try IPP.parse(data.prefix(100)) }
        #expect(throws: IPP.DecodingError.truncated) { try IPP.parse(Data()) }
    }

    @Test("textWithLanguage values give their text without the language")
    func textWithLanguage() throws {
        let value: [UInt8] = [0, 2] + Array("en".utf8) + [0, 6] + Array("Office".utf8)
        let reply = try IPP.parse(ippReply([(0x35, "printer-info", value)]))
        #expect(reply.string("printer-info") == "Office")
    }

    @Test("collections are skipped whole, and the attributes after them still read")
    func collections() throws {
        let reply = try IPP.parse(
            ippReply([
                (0x34, "media-col-ready", []),
                (0x4A, "", Array("media-size".utf8)),
                (0x34, "", []),
                (0x4A, "", Array("x-dimension".utf8)),
                (0x21, "", int32Bytes(21000)),
                (0x37, "", []),
                (0x37, "", []),
                (0x23, "printer-state", int32Bytes(4)),
            ]))
        #expect(reply.attributes["media-col-ready"] == [.other])
        #expect(reply.integer("printer-state") == 4)
        #expect(reply.attributes.keys.sorted() == ["media-col-ready", "printer-state"])
    }

    @Test("a status of 0x0400 or above is a refusal")
    func errorStatus() throws {
        #expect(try IPP.parse(ippReply(status: 0x0400, [])).succeeded == false)
        #expect(try IPP.parse(ippReply(status: 0x0001, [])).succeeded)
    }
}
