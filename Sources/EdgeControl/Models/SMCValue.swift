import Foundation

/// Decoding the bytes an SMC key returns into a number.
///
/// The SMC reports a four-character type alongside a byte count, and both come
/// from hardware. The decoding used to index straight into the buffer —
/// `bytes[1]`, `bytes[3]` — with no check that the buffer was that long, so a
/// short read from a sensor would have taken the app down rather than the
/// reading. Every case now requires its bytes.
public enum SMCValue {

    /// The number a key's bytes represent, or nil when the type is unknown, the
    /// buffer is too short for it, or every byte is zero.
    ///
    /// All-zero is treated as "no reading" rather than a temperature of zero:
    /// keys that exist but are not wired on a given machine answer that way,
    /// and 0 degrees would look like a plausible measurement.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        guard !bytes.isEmpty, bytes.contains(where: { $0 != 0 }) else { return nil }

        switch type {
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(
                UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            )

        // The sp** family is signed fixed-point: the digits name how many bits
        // sit after the point, so each divisor is the next power of two.
        case "sp78": return signedFixedPoint(bytes, divisor: 256)
        case "sp87": return signedFixedPoint(bytes, divisor: 128)
        case "sp96": return signedFixedPoint(bytes, divisor: 64)
        case "spb4": return signedFixedPoint(bytes, divisor: 16)
        case "spf0": return signedFixedPoint(bytes, divisor: 1)

        case "spa5":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 32.0

        case "fpe2":
            // 16-bit with two fractional bits: (b0 << 8 | b1) / 4, written as a
            // shift pair to keep it in integers.
            guard bytes.count >= 2 else { return nil }
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))

        case "flt ":
            guard bytes.count >= 4 else { return nil }
            // loadUnaligned rather than rebinding the array's base address: a
            // [UInt8] buffer carries no guarantee of four-byte alignment, and
            // reinterpreting it as Float32 through a rebind is undefined.
            let value = bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) }
            return value.isFinite ? Double(value) : nil

        default:
            return nil
        }
    }

    private static func signedFixedPoint(_ bytes: [UInt8], divisor: Double) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / divisor
    }
}
