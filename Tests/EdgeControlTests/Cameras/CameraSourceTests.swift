import Foundation
import Testing
@testable import EdgeControl

@Suite("Camera sources")
struct CameraSourceTests {

    @Test("a bare name is a go2rtc stream, shown the way people read it")
    func go2rtcStream() throws {
        let camera = try #require(CameraSource(entry: "plant_wall"))
        #expect(camera.feed == .go2rtc(stream: "plant_wall"))
        #expect(camera.name == "Plant wall")
        #expect(camera.id == "plant_wall")
        #expect(camera.location == "go2rtc · plant_wall")
    }

    @Test("display names tidy separators without inventing capitals")
    func displayNames() {
        #expect(CameraSource.displayName(forStream: "front_door") == "Front door")
        #expect(CameraSource.displayName(forStream: "back-yard__cam") == "Back yard cam")
        #expect(CameraSource.displayName(forStream: "NVR_1") == "NVR 1")
        #expect(CameraSource.displayName(forStream: "beans") == "Beans")
    }

    @Test("a named URL keeps its name; an unnamed one is called after its host")
    func hlsEntries() throws {
        let named = try #require(CameraSource(entry: "Driveway | https://nvr.local/live/driveway.m3u8"))
        #expect(named.name == "Driveway")
        #expect(named.feed == .hls(URL(string: "https://nvr.local/live/driveway.m3u8")!))
        #expect(named.location == "HLS · nvr.local")

        let unnamed = try #require(CameraSource(entry: "http://192.168.1.30:8888/porch/index.m3u8"))
        #expect(unnamed.name == "192.168.1.30")
    }

    @Test("writing an entry and reading it back gives the same camera")
    func entryRoundTrip() throws {
        let item = CameraSource.entry(name: "  Side gate ", url: " https://cams.example.com/side.m3u8 ")
        #expect(item == "Side gate | https://cams.example.com/side.m3u8")
        let camera = try #require(CameraSource(entry: item))
        #expect(camera.name == "Side gate")

        // A name can't smuggle in the separator and shift the URL.
        let tricky = CameraSource.entry(name: "a | b", url: "https://x.example/y.m3u8")
        #expect(try #require(CameraSource(entry: tricky)).feed == .hls(URL(string: "https://x.example/y.m3u8")!))
    }

    @Test("RTSP and other camera protocols are sent to go2rtc, not added directly")
    func unsupportedSchemes() {
        #expect(CameraSource.problem(withURL: "https://cams.example.com/live.m3u8") == nil)
        #expect(CameraSource.problem(withURL: "rtsp://admin:pw@192.168.1.10/live")?.contains("go2rtc") == true)
        #expect(CameraSource.problem(withURL: "ftp://example.com/x") != nil)
        #expect(CameraSource.problem(withURL: "not a url") != nil)
        #expect(CameraSource(entry: "Gate | rtsp://192.168.1.10/live") == nil)
    }

    @Test("blank entries are skipped")
    func blank() {
        #expect(CameraSource(entry: "") == nil)
        #expect(CameraSource(entry: "   ") == nil)
    }
}
