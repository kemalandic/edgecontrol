import Foundation

/// What a Bambu Lab printer is doing, read from the `print` object of its
/// MQTT report.
public struct BambuStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case preparing
        case printing
        case paused
        case finished
        case failed
        case unknown
    }

    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public struct Temperature: Equatable, Sendable {
        public let current: Int
        public let target: Int
    }

    /// A spool: one AMS slot, or the external spool holder.
    public struct Filament: Equatable, Identifiable, Sendable {
        /// The printer's own slot number: AMS unit × 4 + tray, or 254 for
        /// the external spool.
        public let id: Int
        /// "A1"…"A4" for the first AMS, "B1" for the second, "Ext" outside.
        public let slot: String
        public let type: String
        public let color: RGB?
        /// Percent left; nil when the spool has no RFID tag to count from.
        public let remaining: Int?
        public let isActive: Bool
    }

    /// A Health Management System alert, as the printer's screen shows it.
    public struct Alert: Equatable, Sendable {
        public enum Severity: Int, Comparable, Sendable {
            case info = 4, common = 3, serious = 2, fatal = 1
            public static func < (a: Severity, b: Severity) -> Bool { a.rawValue > b.rawValue }
        }

        /// "0300_0100_0001_0007", the form Bambu's wiki and screen use.
        public let code: String
        public let severity: Severity
    }

    public let state: State
    /// What a print is busy with before or between layers ("Heating bed").
    public let stage: String?
    public let jobName: String?
    /// The file the printer is working from, as it names it; the model
    /// picture is read from it.
    public let jobFile: String?
    public let progress: Int
    public let remainingMinutes: Int?
    public let layer: Int?
    public let totalLayers: Int?
    public let nozzle: Temperature?
    public let bed: Temperature?
    public let filaments: [Filament]
    /// Most serious first.
    public let alerts: [Alert]
    /// A failed print's error, in the same underscore form as alerts.
    public let printError: String?

    init(_ print: BambuJSON) {
        state = Self.state(print["gcode_state"]?.text ?? "")
        stage = [.printing, .preparing, .paused].contains(state) ? print["stg_cur"]?.int.flatMap(Self.stageName) : nil

        let name = print["subtask_name"]?.text.flatMap { $0.isEmpty ? nil : $0 } ?? print["gcode_file"]?.text
        jobName = name.flatMap(Self.jobName)
        jobFile = print["gcode_file"]?.text.flatMap { $0.isEmpty ? nil : $0 }
        progress = min(100, max(0, print["mc_percent"]?.int ?? 0))
        remainingMinutes = print["mc_remaining_time"]?.int
        layer = print["layer_num"]?.int
        totalLayers = print["total_layer_num"]?.int.flatMap { $0 > 0 ? $0 : nil }

        nozzle = Self.temperature(print["nozzle_temper"], print["nozzle_target_temper"])
        bed = Self.temperature(print["bed_temper"], print["bed_target_temper"])

        filaments = Self.filaments(print)
        alerts = (print["hms"]?.array ?? []).compactMap(Self.alert).sorted { $0.severity > $1.severity }
        printError = print["print_error"]?.int.flatMap { $0 == 0 ? nil : Self.code(UInt32(truncatingIfNeeded: $0)) }
    }

    public var isActive: Bool { [.preparing, .printing, .paused].contains(state) }

    /// How much of the model to draw as printed, 0…1: the same percentage
    /// as the progress bar. Layers would be truer to height, but the picture
    /// is drawn at an angle, so a flat part fills most of its height, and a
    /// print with a wide base and a thin top spends most of its time in the
    /// first layers. A shelf at 63% on layer 14 of 122 would look barely begun.
    public var printedFraction: Double {
        switch state {
        case .finished: return 1
        case .printing, .paused, .failed: return Double(progress) / 100
        default: return 0
        }
    }

    // MARK: - Interpreting values

    /// `gcode_state`. Heating and levelling report RUNNING like printing
    /// does; `stage` says which.
    static func state(_ gcodeState: String) -> State {
        switch gcodeState.uppercased() {
        case "IDLE": return .idle
        case "PREPARE", "SLICING", "INIT": return .preparing
        case "RUNNING": return .printing
        case "PAUSE": return .paused
        case "FINISH": return .finished
        case "FAILED": return .failed
        default: return .unknown
        }
    }

    /// `stg_cur`: what the printer is doing. Only the stages people see often
    /// get words; the rest show the plain state.
    static func stageName(_ stage: Int) -> String? {
        switch stage {
        case 1: return "Auto bed levelling"
        case 2: return "Heating bed"
        case 3: return "Sweeping XY"
        case 4: return "Changing filament"
        case 6: return "Out of filament"
        case 7: return "Heating nozzle"
        case 8: return "Calibrating extrusion"
        case 9: return "Scanning bed"
        case 10: return "Checking first layer"
        case 11: return "Identifying plate"
        case 13: return "Homing"
        case 14: return "Cleaning nozzle"
        case 16: return "Paused"
        case 17: return "Front cover fell"
        case 22: return "Unloading filament"
        case 24: return "Loading filament"
        default: return nil
        }
    }

    /// "Desk_Organizer_plate_2.gcode.3mf" → "Desk Organizer plate 2".
    static func jobName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespaces)
        for suffix in [".gcode.3mf", ".3mf", ".gcode"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        return name.isEmpty ? nil : name
    }

    private static func temperature(_ current: BambuJSON?, _ target: BambuJSON?) -> Temperature? {
        guard let current = current?.double else { return nil }
        return Temperature(current: Int(current.rounded()), target: Int((target?.double ?? 0).rounded()))
    }

    private static func filaments(_ print: BambuJSON) -> [Filament] {
        let active = print["ams"]?["tray_now"]?.int
        var result: [Filament] = []
        for unit in print["ams"]?["ams"]?.array ?? [] {
            guard let unitID = unit["id"]?.int else { continue }
            let letter = String(UnicodeScalar(UInt8(65 + min(unitID, 25))))
            for tray in unit["tray"]?.array ?? [] {
                guard let trayID = tray["id"]?.int, let filament = Self.filament(tray) else { continue }
                let id = unitID * 4 + trayID
                result.append(
                    Filament(
                        id: id, slot: "\(letter)\(trayID + 1)", type: filament.type, color: filament.color,
                        remaining: filament.remaining, isActive: id == active))
            }
        }
        if let external = print["vt_tray"], let filament = Self.filament(external) {
            result.append(
                Filament(
                    id: 254, slot: "Ext", type: filament.type, color: filament.color, remaining: filament.remaining,
                    isActive: active == 254))
        }
        return result
    }

    /// An empty slot has no tray_type.
    private static func filament(_ tray: BambuJSON) -> (type: String, color: RGB?, remaining: Int?)? {
        guard let type = tray["tray_type"]?.text, !type.isEmpty else { return nil }
        let remaining = tray["remain"]?.int.flatMap { (0...100).contains($0) ? $0 : nil }
        return (type, tray["tray_color"]?.text.flatMap(Self.color), remaining)
    }

    /// "2850E0FF": RRGGBBAA.
    static func color(_ hex: String) -> RGB? {
        guard hex.count >= 6, let value = UInt32(hex.prefix(6), radix: 16) else { return nil }
        return RGB(
            red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    private static func alert(_ hms: BambuJSON) -> Alert? {
        guard let attr = hms["attr"]?.double, let code = hms["code"]?.double else { return nil }
        let attrBits = UInt32(truncatingIfNeeded: Int64(attr))
        let codeBits = UInt32(truncatingIfNeeded: Int64(code))
        let severity = Alert.Severity(rawValue: Int(codeBits >> 16)) ?? .common
        return Alert(code: Self.code(attrBits) + "_" + Self.code(codeBits), severity: severity)
    }

    /// 0x0300400C → "0300_400C".
    static func code(_ value: UInt32) -> String {
        String(format: "%04X_%04X", value >> 16, value & 0xFFFF)
    }

    /// The model, from the first three characters of the serial number.
    public static func model(serial: String) -> String? {
        switch serial.prefix(3) {
        case "00M": return "X1 Carbon"
        case "00W": return "X1"
        case "03W": return "X1E"
        case "01S": return "P1P"
        case "01P": return "P1S"
        case "030": return "A1 mini"
        case "039": return "A1"
        default: return nil
        }
    }
}
