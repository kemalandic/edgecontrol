import Foundation
import Testing
@testable import EdgeControl

@Suite("Printer status")
struct PrinterStatusTests {
    private func reading(_ attributes: [String: [IPP.Value]], fallbackName: String = "Printer") -> PrinterStatus {
        PrinterStatus(IPP.Response(statusCode: 0, attributes: attributes), fallbackName: fallbackName)
    }

    @Test("an HP ink tank printer: name, state, and four inks in their own colors")
    func hp() throws {
        let status = PrinterStatus(try IPP.parse(ippFixture("ipp-hp-smart-tank")), fallbackName: "HP115A08")

        #expect(status.name == "HP Smart Tank 6000 series")
        #expect(status.model == "HP Smart Tank 6000 series")
        #expect(status.state == .idle)
        #expect(status.problems.isEmpty)
        #expect(status.message == nil)
        #expect(status.queuedJobs == 0)
        #expect(status.webPage?.host == "192.168.1.150")
        #expect(status.supplies.map(\.name) == ["Cyan", "Magenta", "Yellow", "Black"])
        #expect(status.supplies.map(\.level) == Array(repeating: .percent(100), count: 4))
        #expect(status.supplies[0].colors == [PrinterStatus.RGB(red: 0, green: 1, blue: 1)])
        #expect(status.supplies[3].colors == [PrinterStatus.RGB(red: 0, green: 0, blue: 0)])
        #expect(status.supplies.allSatisfy { $0.lowLevel == 2 && !$0.isLow })
    }

    @Test("a printer without marker attributes has no supplies")
    func epson() throws {
        let status = PrinterStatus(try IPP.parse(ippFixture("ipp-epson-sc-f100")), fallbackName: "EPSON")
        #expect(status.name == "EPSON SC-F100 Series")
        #expect(status.supplies.isEmpty)
        #expect(status.webPage?.absoluteString == "http://192.168.1.151:80/PRESENTATION/")
    }

    @Test("with no info or model, the Bonjour name is used, without its serial tag")
    func fallbackName() {
        #expect(reading([:], fallbackName: "Office Laser [A1B2C3]").name == "Office Laser")
        #expect(reading(["printer-info": [.text("  ")]], fallbackName: "Office Laser").name == "Office Laser")
    }

    @Test(
        "printer-state",
        arguments: [(3, PrinterStatus.State.idle), (4, .printing), (5, .stopped), (9, .unknown)])
    func state(value: Int, expected: PrinterStatus.State) {
        #expect(reading(["printer-state": [.integer(value)]]).state == expected)
    }

    @Test("problems come out most serious first, and 'none' is no problem")
    func problems() {
        let reasons: [IPP.Value] = [.text("toner-low-warning"), .text("media-empty-error"), .text("none")]
        let status = reading(["printer-state-reasons": reasons])
        #expect(status.problems.map(\.severity) == [.error, .warning])
        #expect(status.topProblem?.text == "Out of paper")
        #expect(self.reading(["printer-state-reasons": [.text("none")]]).topProblem == nil)
    }

    @Test(
        "reason suffixes set the severity; a bare reason is an error",
        arguments: [
            ("media-jam-error", "media-jam", PrinterStatus.Problem.Severity.error),
            ("marker-supply-low-warning", "marker-supply-low", .warning),
            ("cleaning-report", "cleaning", .report),
            ("cover-open", "cover-open", .error),
        ])
    func severity(reason: String, keyword: String, severity: PrinterStatus.Problem.Severity) {
        let problem = PrinterStatus.problem(from: reason)
        #expect(problem.keyword == keyword)
        #expect(problem.severity == severity)
    }

    @Test(
        "reasons read as words",
        arguments: [
            ("media-empty", "Out of paper"), ("media-jam", "Paper jam"), ("door-open", "Cover open"),
            ("marker-supply-low", "Ink low"), ("cleaning", "Cleaning"), ("warming-up", "Warming up"),
            ("fuser-over-temp", "Fuser over temp"),
        ])
    func describe(keyword: String, text: String) {
        #expect(PrinterStatus.describe(keyword) == text)
    }

    @Test(
        "supply names lose the container word",
        arguments: [
            ("cyan cartridge", "Cyan"), ("Black Toner", "Black"), ("photo black ink", "Photo black"),
            ("Ink", "Ink"), ("tri-color cartridge", "Tri-color"), ("Waste Ink Box", "Waste Ink Box"),
        ])
    func supplyName(raw: String, name: String) {
        #expect(PrinterStatus.supplyName(raw) == name)
    }

    @Test(
        "marker-levels",
        arguments: [
            (0, PrinterStatus.Supply.Level.percent(0)), (55, .percent(55)), (100, .percent(100)),
            (-3, .someRemaining), (-2, .unknown), (-1, .unknown), (101, .unknown),
        ])
    func level(value: Int, level: PrinterStatus.Supply.Level) {
        #expect(PrinterStatus.level(value) == level)
    }

    @Test("marker-colors: one color, several for a tri-color cartridge, none for 'none'")
    func colors() {
        #expect(PrinterStatus.colors(from: "#FF0000") == [.init(red: 1, green: 0, blue: 0)])
        #expect(PrinterStatus.colors(from: "#00FFFF#FF00FF#FFFF00").count == 3)
        #expect(PrinterStatus.colors(from: "none").isEmpty)
    }

    @Test("a supply is low at the printer's own threshold, or 10% when it gives none")
    func low() {
        let supplies = reading([
            "marker-names": [.text("a"), .text("b"), .text("c")],
            "marker-levels": [.integer(3), .integer(8), .integer(-3)],
            "marker-low-levels": [.integer(2), .integer(-1), .integer(5)],
        ]).supplies
        #expect(supplies.map(\.isLow) == [false, true, false])
    }

    @Test("missing marker values leave a supply unknown rather than misaligned")
    func shortMarkerLists() {
        let supplies = reading([
            "marker-names": [.text("Black"), .text("Color")],
            "marker-levels": [.integer(40)],
        ]).supplies
        #expect(supplies.map(\.level) == [.percent(40), .unknown])
        #expect(supplies[1].colors.isEmpty)
    }

    @Test("a stopped printer keeps its own message")
    func stoppedMessage() {
        let status = reading(["printer-state": [.integer(5)], "printer-state-message": [.text("Paused by user ")]])
        #expect(status.state == .stopped)
        #expect(status.message == "Paused by user")
    }
}
