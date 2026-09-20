import Foundation
import Testing
@testable import EdgeControl

/// The SMC answers with a four-character type and a byte count, both from
/// hardware. These tests feed it the shapes real sensors produce, and the
/// shapes a misbehaving one would.
@Suite("SMC value decoding")
struct SMCValueTests {

    // MARK: the types temperatures actually arrive in

    /// sp78 is the common temperature type: signed, eight fractional bits.
    /// 0x2D00 is 45.0 — a plausible CPU idle reading.
    @Test("sp78 reads a temperature")
    func sp78() {
        #expect(SMCValue.decode(type: "sp78", bytes: [0x2D, 0x00]) == 45.0)
        #expect(SMCValue.decode(type: "sp78", bytes: [0x2D, 0x80]) == 45.5)
    }

    /// Below freezing is what the sign is for — an SSD in a cold room, or a
    /// sensor reporting an offset. Reading it as unsigned would show 210C.
    @Test("sp78 reads a negative temperature")
    func sp78Negative() {
        #expect(SMCValue.decode(type: "sp78", bytes: [0xFF, 0x00]) == -1.0)
        #expect(SMCValue.decode(type: "sp78", bytes: [0xF6, 0x00]) == -10.0)
    }

    @Test("the sp family divides by the bits after the point", arguments: [
        ("sp87", 128.0), ("sp96", 64.0), ("spb4", 16.0), ("spf0", 1.0),
    ])
    func spFamily(type: String, divisor: Double) {
        // 0x0100 is one whole unit before the divisor is applied.
        #expect(SMCValue.decode(type: type, bytes: [0x01, 0x00]) == 256.0 / divisor)
    }

    @Test("unsigned integer types read big-endian")
    func unsignedTypes() {
        #expect(SMCValue.decode(type: "ui8 ", bytes: [0x2A]) == 42)
        #expect(SMCValue.decode(type: "ui16", bytes: [0x01, 0x00]) == 256)
        #expect(SMCValue.decode(type: "ui32", bytes: [0x00, 0x00, 0x01, 0x00]) == 256)
    }

    /// fpe2 carries two fractional bits: 0x0190 is 100.0, a fan at 100 rpm.
    @Test("fpe2 reads a fan speed")
    func fpe2() {
        #expect(SMCValue.decode(type: "fpe2", bytes: [0x01, 0x90]) == 100.0)
    }

    @Test("flt reads a float")
    func float() {
        var value: Float32 = 42.5
        let bytes = withUnsafeBytes(of: &value) { Array($0) }
        #expect(SMCValue.decode(type: "flt ", bytes: bytes) == 42.5)
    }

    // MARK: what a misbehaving sensor produces

    /// The reason this moved out of the service. Every one of these used to
    /// index past the end of the buffer, which traps — a short read from a
    /// sensor would have taken the app down rather than the reading.
    @Test("a buffer too short for its type yields nothing rather than trapping", arguments: [
        ("ui16", [UInt8(0x01)]),
        ("ui32", [UInt8(0x01), 0x02]),
        ("sp78", [UInt8(0x2D)]),
        ("sp87", [UInt8(0x01)]),
        ("spa5", [UInt8(0x01)]),
        ("fpe2", [UInt8(0x01)]),
        ("flt ", [UInt8(0x01), 0x02, 0x03]),
    ])
    func shortBufferIsRefused(type: String, bytes: [UInt8]) {
        #expect(SMCValue.decode(type: type, bytes: bytes) == nil)
    }

    @Test("an empty buffer yields nothing")
    func emptyBuffer() {
        #expect(SMCValue.decode(type: "sp78", bytes: []) == nil)
    }

    /// A key that exists but is not wired on this machine answers with zeros.
    /// Reporting 0 would look like a plausible temperature.
    @Test("all-zero bytes mean no reading, not a reading of zero")
    func allZeroIsNoReading() {
        #expect(SMCValue.decode(type: "sp78", bytes: [0x00, 0x00]) == nil)
        #expect(SMCValue.decode(type: "ui32", bytes: [0, 0, 0, 0]) == nil)
    }

    @Test("an unknown type yields nothing")
    func unknownType() {
        #expect(SMCValue.decode(type: "zzzz", bytes: [0x01, 0x02]) == nil)
    }

    /// A NaN or infinity out of a float sensor is not a temperature, and would
    /// otherwise propagate into the gauges.
    @Test("a non-finite float yields nothing")
    func nonFiniteFloat() {
        var nan = Float32.nan
        #expect(SMCValue.decode(type: "flt ", bytes: withUnsafeBytes(of: &nan) { Array($0) }) == nil)
        var inf = Float32.infinity
        #expect(SMCValue.decode(type: "flt ", bytes: withUnsafeBytes(of: &inf) { Array($0) }) == nil)
    }

    /// The buffer is longer than the type needs on some keys; the extra bytes
    /// are padding and must be ignored rather than shifting the value.
    @Test("trailing bytes beyond the type are ignored")
    func trailingBytesIgnored() {
        #expect(SMCValue.decode(type: "sp78", bytes: [0x2D, 0x00, 0xFF, 0xFF]) == 45.0)
        #expect(SMCValue.decode(type: "ui8 ", bytes: [0x2A, 0xFF]) == 42)
    }
}
