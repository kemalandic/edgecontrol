import Foundation
import Testing
@testable import EdgeControl

/// Loads a recorded MQTT report from the test bundle and returns its `print` object.
func bambuFixture(_ name: String) throws -> BambuJSON {
    let url = Bundle(for: StubTransport.self).url(forResource: name, withExtension: "json")
    guard let url, let data = try? Data(contentsOf: url) else {
        fatalError("fixture \(name).json not found in the test bundle — check project.yml resources")
    }
    return try #require(try BambuJSON.parse(data)["print"])
}

func bambuJSON(_ text: String) throws -> BambuJSON {
    try BambuJSON.parse(Data(text.utf8))
}

@Suite("Bambu status")
struct BambuStatusTests {
    @Test("a P1S mid-print: job, progress, layers, temperatures and four AMS spools")
    func printing() throws {
        let status = BambuStatus(try bambuFixture("bambu-p1s-pushall"))

        #expect(status.state == .printing)
        #expect(status.stage == nil)
        #expect(status.jobName == "Desk Organizer plate 2")
        #expect(status.progress == 7)
        #expect(status.remainingMinutes == 180)
        #expect(status.layer == 1)
        #expect(status.totalLayers == 122)
        #expect(status.nozzle == .init(current: 220, target: 220))
        #expect(status.bed == .init(current: 45, target: 45))
        #expect(status.alerts.isEmpty)
        #expect(status.printError == nil)

        #expect(status.filaments.map(\.slot) == ["A1", "A2", "A3", "A4"])
        #expect(status.filaments.map(\.type) == ["PLA", "PLA", "PLA", "PLA"])
        #expect(status.filaments.filter(\.isActive).map(\.slot) == ["A2"])
        let red = BambuStatus.RGB(red: 247.0 / 255, green: 35.0 / 255, blue: 35.0 / 255)
        #expect(status.filaments[3].color == red)
        // Spools without an RFID tag report -1: unknown, not empty.
        #expect(status.filaments.allSatisfy { $0.remaining == nil })
    }

    @Test(
        "gcode_state",
        arguments: [
            ("IDLE", BambuStatus.State.idle), ("PREPARE", .preparing), ("RUNNING", .printing), ("PAUSE", .paused),
            ("FINISH", .finished), ("FAILED", .failed), ("", .unknown),
        ])
    func states(raw: String, state: BambuStatus.State) {
        #expect(BambuStatus.state(raw) == state)
    }

    @Test("the stage shows while printing, and not once the printer is idle")
    func stage() throws {
        let heating = BambuStatus(try bambuJSON(#"{"gcode_state":"RUNNING","stg_cur":2}"#))
        #expect(heating.stage == "Heating bed")
        let idle = BambuStatus(try bambuJSON(#"{"gcode_state":"IDLE","stg_cur":2}"#))
        #expect(idle.stage == nil)
        #expect(BambuStatus(try bambuJSON(#"{"gcode_state":"RUNNING","stg_cur":0}"#)).stage == nil)
    }

    @Test(
        "job names lose their file extension and underscores",
        arguments: [
            ("Desk_Organizer_plate_2", "Desk Organizer plate 2"), ("Benchy.gcode.3mf", "Benchy"),
            ("calibration.gcode", "calibration"), ("Lid.3MF", "Lid"), ("  ", nil),
        ])
    func jobNames(raw: String, name: String?) {
        #expect(BambuStatus.jobName(raw) == name)
    }

    @Test("with no subtask name the file name is used")
    func jobFromFile() throws {
        let status = BambuStatus(try bambuJSON(#"{"subtask_name":"","gcode_file":"Clip_x4.gcode.3mf"}"#))
        #expect(status.jobName == "Clip x4")
    }

    @Test("HMS alerts read as the printer's own codes, most serious first")
    func alerts() throws {
        let status = BambuStatus(
            try bambuJSON(
                #"{"hms":[{"attr":50331904,"code":262145},{"attr":117440512,"code":131074}],"print_error":0}"#))
        #expect(status.alerts.map(\.code) == ["0700_0000_0002_0002", "0300_0100_0004_0001"])
        #expect(status.alerts.map(\.severity) == [.serious, .info])
        #expect(status.alerts[0].severity > status.alerts[1].severity)
    }

    @Test("a print error is shown in the same form")
    func printError() throws {
        #expect(BambuStatus(try bambuJSON(#"{"print_error":50348044}"#)).printError == "0300_400C")
    }

    @Test("the external spool counts, and an empty slot doesn't")
    func externalSpool() throws {
        let status = BambuStatus(
            try bambuJSON(
                #"""
                {"ams":{"tray_now":"254","ams":[{"id":"1","tray":[{"id":"0","tray_type":"PETG","tray_color":"FFFFFFFF","remain":40},{"id":"1","tray_type":""}]}]},
                 "vt_tray":{"id":"254","tray_type":"TPU","tray_color":"000000FF","remain":-1}}
                """#))
        #expect(status.filaments.map(\.slot) == ["B1", "Ext"])
        #expect(status.filaments.map(\.id) == [4, 254])
        #expect(status.filaments[0].remaining == 40)
        #expect(status.filaments.filter(\.isActive).map(\.slot) == ["Ext"])
    }

    @Test(
        "models from the serial prefix",
        arguments: [
            ("01P00A000000000", "P1S"), ("00M09A000000000", "X1 Carbon"), ("0300000000", "A1 mini"), ("ZZZ", nil),
        ])
    func models(serial: String, model: String?) {
        #expect(BambuStatus.model(serial: serial) == model)
    }
}

@Suite("Bambu JSON")
struct BambuJSONTests {
    @Test("numbers and numeric strings read as either")
    func loose() throws {
        let json = try bambuJSON(#"{"a":"12","b":7,"c":"-39dBm","d":1.5}"#)
        #expect(json["a"]?.int == 12)
        #expect(json["b"]?.text == "7")
        #expect(json["c"]?.int == nil)
        #expect(json["d"]?.text == "1.5")
    }

    @Test("a P1 delta changes only what it mentions")
    func delta() throws {
        let full = try bambuFixture("bambu-p1s-pushall")
        let delta = try bambuFixture("bambu-p1s-delta")
        let merged = full.merging(delta)

        #expect(merged["nozzle_temper"]?.double == delta["nozzle_temper"]?.double)
        #expect(merged["mc_percent"]?.int == 7)
        #expect(merged["ams"] == full["ams"])
    }

    @Test("trays merge by id, so an update about one tray leaves the others")
    func traysById() throws {
        let base = try bambuJSON(
            #"{"ams":{"ams":[{"id":"0","tray":[{"id":"0","tray_type":"PLA"},{"id":"1","tray_type":"PETG"}]}]}}"#)
        let update = try bambuJSON(#"{"ams":{"ams":[{"id":"0","tray":[{"id":"1","tray_type":"ABS"}]}]}}"#)
        let trays = base.merging(update)["ams"]?["ams"]?.array?.first?["tray"]?.array ?? []
        #expect(trays.map { $0["tray_type"]?.text } == ["PLA", "ABS"])
    }

    @Test("lists without ids are replaced, so a cleared alert goes away")
    func listsReplace() throws {
        let base = try bambuJSON(#"{"hms":[{"attr":1,"code":2}]}"#)
        let merged = base.merging(try bambuJSON(#"{"hms":[]}"#))
        #expect(merged["hms"]?.array?.isEmpty == true)
    }
}

@Suite("Bambu Lab Printer: on screen or not")
struct BambuVisibilityTests {
    private let tile = CGSize(width: 640, height: 360)

    @Test("on the right half of the dashboard, the camera still streams")
    func rightHalf() {
        // A 2560-wide dashboard as a widget at x = 1536 sees it.
        #expect(BambuVisibility.isOnScreen(size: tile, dashboard: CGRect(x: -1536, y: -120, width: 2560, height: 720)))
    }

    @Test("on the next page, or with no dashboard around it")
    func elsewhere() {
        #expect(!BambuVisibility.isOnScreen(size: tile, dashboard: CGRect(x: -2660, y: -120, width: 2560, height: 720)))
        #expect(BambuVisibility.isOnScreen(size: tile, dashboard: nil))
    }
}
