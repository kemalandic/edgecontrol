import Foundation

/// Just enough MQTT 3.1.1 to listen to a Bambu Lab printer.
///
/// Bambu printers run an MQTT broker on port 8883 and publish their status to
/// it about once a second. Reading that needs five packets: CONNECT,
/// SUBSCRIBE, one PUBLISH to ask for the full status, PINGREQ to keep the
/// connection open, and DISCONNECT. Everything goes out at QoS 0.
enum MQTT {
    enum Packet: Equatable, Sendable {
        /// 0 is accepted; 4 is a wrong username or password, 5 not authorized.
        case connAck(returnCode: UInt8)
        /// One granted QoS per topic; 0x80 is a refusal.
        case subAck(packetID: UInt16, granted: [UInt8])
        /// `packetID` is set for QoS 1 and 2, which must be acknowledged.
        case publish(topic: String, payload: Data, packetID: UInt16?)
        case pingResponse
        case other(type: UInt8)
    }

    enum DecodingError: Error, Equatable {
        case malformed
    }

    // MARK: - Encoding

    static func connect(clientID: String, username: String, password: String, keepAlive: UInt16) -> Data {
        var body = Data()
        body.append(mqttString: "MQTT")
        body.append(4)  // protocol level: 3.1.1
        body.append(0xC2)  // username, password, clean session
        body.append(uint16: keepAlive)
        body.append(mqttString: clientID)
        body.append(mqttString: username)
        body.append(mqttString: password)
        return packet(0x10, body)
    }

    static func subscribe(_ topic: String, packetID: UInt16) -> Data {
        var body = Data()
        body.append(uint16: packetID)
        body.append(mqttString: topic)
        body.append(0)  // QoS 0
        return packet(0x82, body)
    }

    static func publish(_ topic: String, payload: Data) -> Data {
        var body = Data()
        body.append(mqttString: topic)
        body.append(payload)
        return packet(0x30, body)
    }

    static func publishAck(_ packetID: UInt16) -> Data {
        var body = Data()
        body.append(uint16: packetID)
        return packet(0x40, body)
    }

    static let pingRequest = Data([0xC0, 0x00])
    static let disconnect = Data([0xE0, 0x00])

    private static func packet(_ header: UInt8, _ body: Data) -> Data {
        var data = Data([header])
        // Remaining length: seven bits a byte, high bit set while more follow.
        var length = body.count
        repeat {
            var byte = UInt8(length % 128)
            length /= 128
            if length > 0 { byte |= 0x80 }
            data.append(byte)
        } while length > 0
        data.append(body)
        return data
    }

    // MARK: - Decoding

    /// Cuts a byte stream into packets. TLS hands bytes over in whatever
    /// pieces it likes, so a packet can arrive split or several at once.
    struct Decoder {
        private var buffer = Data()

        mutating func append(_ data: Data) {
            buffer.append(data)
        }

        /// The next whole packet, or nil until more bytes arrive.
        mutating func next() throws -> Packet? {
            let bytes = [UInt8](buffer.prefix(5))
            guard bytes.count >= 2 else { return nil }
            var length = 0
            var multiplier = 1
            var index = 1
            while true {
                guard index < bytes.count else {
                    // Four length bytes is the most MQTT allows.
                    if index >= 5 { throw DecodingError.malformed }
                    return nil
                }
                let byte = bytes[index]
                length += Int(byte & 0x7F) * multiplier
                multiplier *= 128
                index += 1
                if byte & 0x80 == 0 { break }
                if index == 5 { throw DecodingError.malformed }
            }
            guard buffer.count >= index + length else { return nil }
            let start = buffer.startIndex
            let header = bytes[0]
            let body = Data(buffer[(start + index)..<(start + index + length)])
            buffer = Data(buffer[(start + index + length)...])
            return try Self.packet(header: header, body: body)
        }

        private static func packet(header: UInt8, body: Data) throws -> Packet {
            let bytes = [UInt8](body)
            switch header >> 4 {
            case 2:
                guard bytes.count >= 2 else { throw DecodingError.malformed }
                return .connAck(returnCode: bytes[1])
            case 3:
                guard bytes.count >= 2 else { throw DecodingError.malformed }
                let topicLength = Int(bytes[0]) << 8 | Int(bytes[1])
                var offset = 2 + topicLength
                guard bytes.count >= offset else { throw DecodingError.malformed }
                let topic = String(decoding: bytes[2..<offset], as: UTF8.self)
                var packetID: UInt16?
                if (header >> 1) & 0x03 > 0 {
                    guard bytes.count >= offset + 2 else { throw DecodingError.malformed }
                    packetID = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
                    offset += 2
                }
                return .publish(topic: topic, payload: Data(bytes[offset...]), packetID: packetID)
            case 9:
                guard bytes.count >= 2 else { throw DecodingError.malformed }
                return .subAck(packetID: UInt16(bytes[0]) << 8 | UInt16(bytes[1]), granted: Array(bytes[2...]))
            case 13:
                return .pingResponse
            default:
                return .other(type: header >> 4)
            }
        }
    }
}

extension Data {
    fileprivate mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    fileprivate mutating func append(mqttString value: String) {
        append(uint16: UInt16(value.utf8.count))
        append(contentsOf: Array(value.utf8))
    }
}
