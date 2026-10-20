import Foundation
import Testing
@testable import EdgeControl

@Suite("MQTT")
struct MQTTTests {
    @Test("CONNECT carries the protocol, the login and a keep-alive, as MQTT 3.1.1 lays them out")
    func connect() {
        let packet = [UInt8](MQTT.connect(clientID: "ec", username: "bblp", password: "12345678", keepAlive: 60))
        var body: [UInt8] = [0, 4]
        body += Array("MQTT".utf8)
        body += [4, 0xC2, 0, 60, 0, 2]
        body += Array("ec".utf8)
        body += [0, 4]
        body += Array("bblp".utf8)
        body += [0, 8]
        body += Array("12345678".utf8)
        let expected: [UInt8] = [0x10, UInt8(body.count)] + body
        #expect(packet == expected)
    }

    @Test("SUBSCRIBE asks for one topic at QoS 0")
    func subscribe() {
        let packet = [UInt8](MQTT.subscribe("device/X/report", packetID: 1))
        var expected: [UInt8] = [0x82, 20, 0, 1, 0, 15]
        expected += Array("device/X/report".utf8)
        expected.append(0)
        #expect(packet == expected)
    }

    @Test("a payload over 127 bytes takes a second length byte")
    func longLength() {
        let packet = [UInt8](MQTT.publish("t", payload: Data(repeating: 0x41, count: 200)))
        // 2 + 1 topic bytes + 200 payload = 203 = 0x4B + 1 × 128.
        #expect(Array(packet.prefix(3)) == [0x30, 0xCB, 0x01])
        #expect(packet.count == 3 + 203)
    }

    @Test("packets split across reads come out whole, and several in one read come out in order")
    func decoderSplits() throws {
        let stream = Data([0x20, 0x02, 0x00, 0x00, 0x90, 0x03, 0x00, 0x01, 0x00, 0xD0, 0x00])
        var decoder = MQTT.Decoder()
        decoder.append(stream.prefix(3))
        #expect(try decoder.next() == nil)
        decoder.append(stream.dropFirst(3))
        #expect(try decoder.next() == .connAck(returnCode: 0))
        #expect(try decoder.next() == .subAck(packetID: 1, granted: [0]))
        #expect(try decoder.next() == .pingResponse)
        #expect(try decoder.next() == nil)
    }

    @Test("a QoS 0 publish has no packet id; a QoS 1 publish does")
    func publishes() throws {
        var decoder = MQTT.Decoder()
        decoder.append(MQTT.publish("a/b", payload: Data("{}".utf8)))
        #expect(try decoder.next() == .publish(topic: "a/b", payload: Data("{}".utf8), packetID: nil))

        var qos1 = Data([0x32, 9, 0, 3])
        qos1.append(Data("a/b".utf8))
        qos1.append(Data([0, 7]))
        qos1.append(Data("{}".utf8))
        decoder.append(qos1)
        #expect(try decoder.next() == .publish(topic: "a/b", payload: Data("{}".utf8), packetID: 7))
    }

    @Test("a refused login says which way")
    func refusedLogin() throws {
        var decoder = MQTT.Decoder()
        decoder.append(Data([0x20, 0x02, 0x00, 0x05]))
        #expect(try decoder.next() == .connAck(returnCode: 5))
    }

    @Test("a length longer than four bytes is malformed, not a wait for more")
    func malformedLength() {
        var decoder = MQTT.Decoder()
        decoder.append(Data([0x30, 0xFF, 0xFF, 0xFF, 0xFF, 0x01]))
        #expect(throws: MQTT.DecodingError.malformed) { try decoder.next() }
    }
}
