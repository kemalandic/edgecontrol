import Foundation

/// One delivery as Parcel reports it.
public struct ParcelDelivery: Identifiable, Equatable, Sendable {
    /// Parcel's `status_code`, in its own numbering.
    public enum Status: Int, Equatable, Sendable {
        case delivered = 0
        /// No updates for a long time, or none expected.
        case frozen = 1
        case inTransit = 2
        case awaitingPickup = 3
        case outForDelivery = 4
        case notFound = 5
        case failedAttempt = 6
        /// Something the recipient needs to sort out.
        case exception = 7
        /// The carrier has the label but not the package.
        case infoReceived = 8
        case unknown = -1

        /// Still coming: everything but delivered.
        public var isUnderway: Bool { self != .delivered }
    }

    /// One tracking scan. Carriers write these, so `date` stays as they
    /// wrote it; `ParcelSchedule` reads the forms it can.
    public struct Event: Equatable, Sendable {
        public var text: String
        public var date: String
        public var location: String?
        public var additional: String?

        public init(text: String, date: String, location: String? = nil, additional: String? = nil) {
            self.text = text
            self.date = date
            self.location = location
            self.additional = additional
        }
    }

    public var carrier: String
    public var description: String
    public var status: Status
    public var trackingNumber: String
    public var extraInformation: String?
    /// Newest first, as Parcel sends them.
    public var events: [Event]
    public var expected: ParcelSchedule.Expected?

    public var id: String { carrier + "/" + trackingNumber }
    /// What the person called it, or the tracking number when they didn't.
    public var title: String { description.isEmpty ? trackingNumber : description }
    public var latestEvent: Event? { events.first }

    public init(
        carrier: String, description: String, status: Status, trackingNumber: String,
        extraInformation: String? = nil, events: [Event] = [], expected: ParcelSchedule.Expected? = nil
    ) {
        self.carrier = carrier
        self.description = description
        self.status = status
        self.trackingNumber = trackingNumber
        self.extraInformation = extraInformation
        self.events = events
        self.expected = expected
    }
}

/// Reads Parcel's replies.
///
/// The API is unversioned and its values come from hundreds of carriers, so
/// reading is forgiving: a field that is missing, null or of another type is
/// absent; a malformed event is dropped rather than costing its delivery; a
/// malformed delivery is dropped rather than costing the list. Only a reply
/// with no list at all is an error, since showing "nothing on the way" for a
/// changed format would be a confident wrong answer.
public enum ParcelAPI {
    public struct Reply: Equatable, Sendable {
        public var success: Bool
        public var errorMessage: String?
        public var deliveries: [ParcelDelivery]
    }

    public enum DecodingError: Error, Equatable {
        case notJSON
        case missingDeliveries
    }

    public static func decodeDeliveries(
        _ data: Data, calendar: Calendar = .current, now: Date = Date()
    ) throws -> Reply {
        guard let object = try? JSONSerialization.jsonObject(with: data), let body = object as? [String: Any]
        else { throw DecodingError.notJSON }
        let success = (body["success"] as? Bool) ?? false
        let message = string(body["error_message"])
        guard let items = body["deliveries"] as? [Any] else {
            if success { throw DecodingError.missingDeliveries }
            return Reply(success: false, errorMessage: message, deliveries: [])
        }
        let deliveries = items.compactMap { delivery($0, calendar: calendar, now: now) }
        return Reply(success: success, errorMessage: message, deliveries: deliveries)
    }

    /// Parcel's own explanation in a failed reply, if the body has one.
    public static func errorMessage(_ data: Data) -> String? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return string(body["error_message"])
    }

    /// `supported_carriers.json`: code to name. Each value was a name until
    /// 2026 and is `{"name": …}` now; both are read.
    public static func decodeCarriers(_ data: Data) -> [String: String] {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var names: [String: String] = [:]
        for (code, value) in body {
            if let name = string(value) ?? string((value as? [String: Any])?["name"]) {
                names[code] = name
            }
        }
        return names
    }

    static func delivery(_ item: Any, calendar: Calendar, now: Date) -> ParcelDelivery? {
        guard let item = item as? [String: Any], let code = number(item["status_code"]) else { return nil }
        let tracking = string(item["tracking_number"]) ?? ""
        let description = string(item["description"]) ?? ""
        guard !(tracking.isEmpty && description.isEmpty) else { return nil }
        let events = (item["events"] as? [Any] ?? []).compactMap(event)
        return ParcelDelivery(
            carrier: string(item["carrier_code"]) ?? "",
            description: description,
            status: ParcelDelivery.Status(rawValue: Int(code)) ?? .unknown,
            trackingNumber: tracking,
            extraInformation: string(item["extra_information"]),
            events: events,
            expected: ParcelSchedule.expected(
                timestamp: number(item["timestamp_expected"]),
                timestampEnd: number(item["timestamp_expected_end"]),
                date: string(item["date_expected"]),
                dateEnd: string(item["date_expected_end"]),
                calendar: calendar, near: now))
    }

    static func event(_ item: Any) -> ParcelDelivery.Event? {
        guard let item = item as? [String: Any] else { return nil }
        let text = string(item["event"]) ?? ""
        let date = string(item["date"]) ?? ""
        guard !(text.isEmpty && date.isEmpty) else { return nil }
        return ParcelDelivery.Event(
            text: text, date: date, location: string(item["location"]), additional: string(item["additional"]))
    }

    /// A non-empty string, from a string or a plain number.
    static func string(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber, !isBool(number) { return number.stringValue }
        return nil
    }

    /// A finite number, from a number or a string of digits.
    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, !isBool(number) {
            return number.doubleValue.isFinite ? number.doubleValue : nil
        }
        if let text = value as? String, let number = Double(text.trimmingCharacters(in: .whitespaces)),
            number.isFinite
        {
            return number
        }
        return nil
    }

    private static func isBool(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
