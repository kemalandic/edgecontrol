import Foundation
import Testing
@testable import EdgeControl

@Suite("go2rtc API")
struct Go2RTCTests {

    @Test(
        "server addresses are read the way people type them",
        arguments: [
            ("192.168.1.20", "http://192.168.1.20:1984"),
            ("192.168.1.20:1984/", "http://192.168.1.20:1984"),
            (" nvr.local ", "http://nvr.local:1984"),
            ("http://nvr.local:8080", "http://nvr.local:8080"),
            ("HTTP://NVR.local:1984", "http://nvr.local:1984"),
            ("ws://192.168.1.20:1984/api/ws?src=front", "http://192.168.1.20:1984"),
            ("https://home.example.com/go2rtc/api/streams", "https://home.example.com/go2rtc"),
            ("https://home.example.com/go2rtc/", "https://home.example.com/go2rtc"),
            ("https://home.example.com", "https://home.example.com"),
        ])
    func serverURL(input: String, expected: String) {
        #expect(Go2RTC.serverURL(from: input)?.absoluteString == expected)
    }

    @Test("nothing usable gives no server", arguments: ["", "   ", "rtsp://192.168.1.20", "http://"])
    func noServer(input: String) {
        #expect(Go2RTC.serverURL(from: input) == nil)
    }

    @Test("API addresses sit under the server, including behind a proxy path")
    func apiURLs() throws {
        let server = try #require(Go2RTC.serverURL(from: "https://home.example.com/go2rtc"))
        #expect(Go2RTC.streamsURL(server: server).absoluteString == "https://home.example.com/go2rtc/api/streams")
        #expect(
            Go2RTC.hlsURL(server: server, stream: "front_door").absoluteString
                == "https://home.example.com/go2rtc/api/stream.m3u8?src=front_door")
    }

    @Test("stream names are escaped in the query")
    func escaping() throws {
        let server = try #require(Go2RTC.serverURL(from: "192.168.1.20"))
        let url = Go2RTC.hlsURL(server: server, stream: "Back Yard & Gate")
        let src = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "src" }
        #expect(src?.value == "Back Yard & Gate")
        #expect(!url.absoluteString.contains(" "))
    }

    @Test("the stream list is sorted naturally and leaves out URL-named streams")
    func streamNames() throws {
        let data = try fixture("go2rtc-streams")
        let names = try Go2RTC.streamNames(from: data)
        #expect(names == ["Back_Yard", "camera9", "camera10", "front_door", "garage"])
        #expect(!names.contains { $0.contains("secret") }, "a stream named after its source URL leaked a password")
    }

    @Test("a body that isn't go2rtc's stream list is an error, not an empty list")
    func notAStreamList() {
        #expect(throws: CIError.self) { try Go2RTC.streamNames(from: Data("[1, 2]".utf8)) }
        #expect(throws: CIError.self) { try Go2RTC.streamNames(from: Data("<html>".utf8)) }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: StubTransport.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
