import Foundation

/// A Bambu printer's report, kept as JSON so the next report can be merged in.
///
/// X1 printers send their whole status every time, but P1 and A1 printers
/// send only what changed since the last message: a nozzle temperature here,
/// a layer number there. The full picture is the first, complete report
/// with every later one laid over it.
enum BambuJSON: Equatable, Sendable, Decodable {
    case object([String: BambuJSON])
    case array([BambuJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BambuJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BambuJSON].self))
        }
    }

    static func parse(_ data: Data) throws -> BambuJSON {
        try JSONDecoder().decode(BambuJSON.self, from: data)
    }

    subscript(key: String) -> BambuJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var array: [BambuJSON]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// Bambu sends numbers as strings about as often as not ("tray_now": "1"),
    /// so both read as either.
    var text: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value == value.rounded() ? String(Int(value)) : String(value)
        default: return nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var int: Int? { double.map { Int($0) } }

    /// This report with `update` laid over it. Objects merge key by key.
    /// Lists of objects with an "id", like AMS units and their trays, merge
    /// entry by entry, since an update may mention only the tray that
    /// changed. Anything else is replaced.
    func merging(_ update: BambuJSON) -> BambuJSON {
        switch (self, update) {
        case (.object(let base), .object(let changes)):
            var merged = base
            for (key, value) in changes {
                merged[key] = merged[key].map { $0.merging(value) } ?? value
            }
            return .object(merged)
        case (.array(let base), .array(let changes)):
            let baseIDs = base.map { $0["id"]?.text }
            let changeIDs = changes.map { $0["id"]?.text }
            guard !changes.isEmpty, !baseIDs.contains(nil), !changeIDs.contains(nil) else { return update }
            var merged = base
            for (change, id) in zip(changes, changeIDs) {
                if let index = baseIDs.firstIndex(of: id) {
                    merged[index] = merged[index].merging(change)
                } else {
                    merged.append(change)
                }
            }
            return .array(merged)
        default:
            return update
        }
    }
}
