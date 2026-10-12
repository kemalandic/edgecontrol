import Foundation
import os

/// Decoding that keeps the rest of a layout when one part can't be read.
///
/// layout.json is decoded as a whole: one unknown enum value (a theme name
/// from a newer version, a hand edit) or one malformed widget used to fail
/// the entire document, and the store then fell back to the default layout.
/// These fall back per field and skip per item instead, and log what was
/// dropped.
private let lenientLog = Logger(subsystem: "ai.pakslab.edgecontrol", category: "Persistence")

/// Counts what the lenient decoder had to replace or skip, so callers can tell
/// a clean read from a recovered one. A missing key isn't counted (older
/// files lack newer settings); a key that's present but unreadable is.
final class LenientDecodingReport: @unchecked Sendable {
    // Decoding is synchronous and the report is local to one decode call.
    private(set) var fallbacks = 0
    func record(_ count: Int = 1) { fallbacks += count }

    @TaskLocal static var current: LenientDecodingReport?

    /// Decodes `type`, returning how many fallbacks were applied.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> (value: T, fallbacks: Int) {
        let report = LenientDecodingReport()
        let value = try $current.withValue(report) { try JSONDecoder().decode(T.self, from: data) }
        return (value, report.fallbacks)
    }
}

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when it's missing or unreadable.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key, default fallback: @autoclosure () -> T) -> T {
        do {
            return try decodeIfPresent(T.self, forKey: key) ?? fallback()
        } catch {
            lenientLog.error("layout: using the default for unreadable \(key.stringValue, privacy: .public)")
            LenientDecodingReport.current?.record()
            return fallback()
        }
    }

    /// An optional value, nil when missing or unreadable.
    func lenientOptional<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        lenient(T?.self, forKey: key, default: nil)
    }

    /// The readable elements of an array; unreadable ones are skipped.
    func lenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        guard contains(key), (try? decodeNil(forKey: key)) == false else { return [] }
        guard var items = try? nestedUnkeyedContainer(forKey: key) else {
            // Present but not a list: everything in it is lost.
            lenientLog.error("layout: \(key.stringValue, privacy: .public) isn't a list; ignoring it")
            LenientDecodingReport.current?.record()
            return []
        }
        var result: [T] = []
        var skipped = 0
        while !items.isAtEnd {
            if let item = try? items.decode(T.self) {
                result.append(item)
            } else if (try? items.decode(Skipped.self)) != nil {
                skipped += 1
            } else {
                skipped += 1
                break  // can't advance past it
            }
        }
        if !items.isAtEnd { LenientDecodingReport.current?.record() }
        if skipped > 0 {
            LenientDecodingReport.current?.record(skipped)
            lenientLog.error("layout: skipped \(skipped) unreadable item(s) in \(key.stringValue, privacy: .public)")
        }
        return result
    }
}

/// Consumes one array element of any shape.
private struct Skipped: Decodable {
    init(from decoder: Decoder) throws {}
}
