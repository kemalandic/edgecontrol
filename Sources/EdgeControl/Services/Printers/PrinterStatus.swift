import Foundation

/// What a printer reported about itself, read from an IPP Get-Printer-Attributes reply.
public struct PrinterStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case printing
        case stopped
        case unknown
    }

    /// A problem the printer reported, from `printer-state-reasons`.
    public struct Problem: Equatable, Sendable {
        public enum Severity: Int, Comparable, Sendable {
            case report, warning, error
            public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        }

        public let keyword: String
        public let severity: Severity
        public var text: String { PrinterStatus.describe(keyword) }
    }

    /// An ink tank, toner cartridge or similar, from the marker-* attributes.
    public struct Supply: Equatable, Identifiable, Sendable {
        public enum Level: Equatable, Sendable {
            case percent(Int)
            /// Not empty, but the printer can't say how full (marker-level -3).
            case someRemaining
            case unknown
        }

        public let id: Int
        public let name: String
        /// sRGB colors from `marker-colors`: one for most supplies, several
        /// for a multi-color cartridge, none when the printer gives "none".
        public let colors: [RGB]
        public let level: Level
        /// At or below this percentage the printer considers the supply low.
        public let lowLevel: Int?
        public let type: String?

        public var isLow: Bool {
            guard case .percent(let percent) = level else { return false }
            return percent <= (lowLevel ?? 10)
        }
    }

    public struct RGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double
    }

    public let name: String
    public let model: String?
    public let state: State
    public let problems: [Problem]
    /// The printer's own sentence about its state, when it has one.
    public let message: String?
    public let queuedJobs: Int
    public let supplies: [Supply]
    /// The printer's web page, for its own settings and supply details.
    public let webPage: URL?

    init(_ response: IPP.Response, fallbackName: String) {
        let info = response.string("printer-info")?.trimmed.nonEmpty
        let model = response.string("printer-make-and-model")?.trimmed.nonEmpty
        name = Self.displayName(info ?? model ?? fallbackName)
        self.model = model

        switch response.integer("printer-state") {
        case 3: state = .idle
        case 4: state = .printing
        case 5: state = .stopped
        default: state = .unknown
        }

        problems = response.strings("printer-state-reasons")
            .filter { $0 != "none" }
            .map(Self.problem(from:))
            .sorted { $0.severity > $1.severity }

        message = response.string("printer-state-message")?.trimmed.nonEmpty
        queuedJobs = response.integer("queued-job-count") ?? 0
        webPage = response.string("printer-more-info").flatMap(URL.init(string:))

        let names = response.strings("marker-names")
        let colors = response.strings("marker-colors")
        let levels = response.integers("marker-levels")
        let lows = response.integers("marker-low-levels")
        let types = response.strings("marker-types")
        supplies = names.indices.map { index in
            Supply(
                id: index,
                name: Self.supplyName(names[index]),
                colors: index < colors.count ? Self.colors(from: colors[index]) : [],
                level: index < levels.count ? Self.level(levels[index]) : .unknown,
                lowLevel: index < lows.count && lows[index] >= 0 ? lows[index] : nil,
                type: index < types.count ? types[index] : nil)
        }
    }

    /// The most important problem, if any.
    public var topProblem: Problem? { problems.first }

    // MARK: - Interpreting values

    /// AirPrint names often end in a serial-number tag: "HP Smart Tank 6000 series [115A08]".
    static func displayName(_ raw: String) -> String {
        let trimmed = raw.trimmed
        guard let open = trimmed.range(of: " [", options: .backwards), trimmed.hasSuffix("]") else { return trimmed }
        return String(trimmed[..<open.lowerBound])
    }

    /// "cyan cartridge" → "Cyan"; "Black Toner" → "Black".
    static func supplyName(_ raw: String) -> String {
        var words = raw.trimmed.split(separator: " ").map(String.init)
        let containers = ["cartridge", "cartridges", "toner", "ink", "tank", "bottle"]
        if words.count > 1, let last = words.last, containers.contains(last.lowercased()) { words.removeLast() }
        let name = words.joined(separator: " ")
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// marker-levels: 0–100 is a percentage; -3 means some left, -1 and -2 unknown.
    static func level(_ value: Int) -> Supply.Level {
        switch value {
        case 0...100: return .percent(value)
        case -3: return .someRemaining
        default: return .unknown
        }
    }

    /// "#00FFFF", "#00FFFF#FF00FF" for a multi-color cartridge, or "none".
    static func colors(from text: String) -> [RGB] {
        text.split(separator: "#").compactMap { hex in
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            return RGB(
                red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255)
        }
    }

    static func problem(from keyword: String) -> Problem {
        for (suffix, severity) in [("-error", Problem.Severity.error), ("-warning", .warning), ("-report", .report)]
        where keyword.hasSuffix(suffix) {
            return Problem(keyword: String(keyword.dropLast(suffix.count)), severity: severity)
        }
        // RFC 8011: a reason without a suffix is an error.
        return Problem(keyword: keyword, severity: .error)
    }

    /// Words for the reasons people actually meet; anything else is spelled out.
    static func describe(_ keyword: String) -> String {
        switch keyword {
        case "media-empty", "media-needed": return "Out of paper"
        case "media-jam": return "Paper jam"
        case "media-low": return "Paper low"
        case "door-open", "cover-open", "interlock-open": return "Cover open"
        case "input-tray-missing": return "Tray missing"
        case "output-area-full", "output-tray-missing": return "Output tray full"
        case "marker-supply-low", "toner-low": return "Ink low"
        case "marker-supply-empty", "toner-empty": return "Ink empty"
        case "marker-waste-almost-full": return "Waste ink almost full"
        case "marker-waste-full": return "Waste ink full"
        case "offline", "shutdown": return "Offline"
        case "paused", "moving-to-paused": return "Paused"
        case "connecting-to-device": return "Connecting"
        case "spool-area-full": return "Print queue full"
        case "cleaning", "warming-up": return keyword == "cleaning" ? "Cleaning" : "Warming up"
        default:
            let words = keyword.replacingOccurrences(of: "-", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
