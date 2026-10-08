import Foundation
import Testing
@testable import EdgeControl

/// Loads a reply shaped like Parcel's from the test bundle. The deliveries in
/// it are made up; the forms are the ones Parcel and its carriers send.
func parcelFixture(_ name: String) -> Data {
    let url = Bundle(for: StubTransport.self).url(forResource: name, withExtension: "json")
    guard let url, let data = try? Data(contentsOf: url) else {
        fatalError("fixture \(name).json not found in the test bundle — check project.yml resources")
    }
    return data
}

/// The Parcel tests read dates in New York, the day they were written.
let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// Thursday 8 October 2026, noon in New York.
let parcelNow = Date(timeIntervalSince1970: 1_791_475_200)

func newYorkDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@Suite("Parcel replies")
struct ParcelDeliveryTests {
    private func deliveries() throws -> [ParcelDelivery] {
        try ParcelAPI.decodeDeliveries(parcelFixture("parcel-deliveries"), calendar: newYork, now: parcelNow)
            .deliveries
    }

    @Test("reads every delivery it can, and drops the one without a status")
    func reads() throws {
        let deliveries = try deliveries()
        #expect(
            deliveries.map(\.trackingNumber) == [
                "770000000001", "1Z0000000000000002", "9400000000000000000003", "TBA000000000004",
                "JD000000000000005", "9400000000000000000007",
            ])
        let statuses: [ParcelDelivery.Status] = [
            .inTransit, .outForDelivery, .infoReceived, .awaitingPickup, .delivered, .unknown,
        ]
        #expect(deliveries.map(\.status) == statuses)
    }

    @Test("a status sent as a string still reads, and a delivery with no name goes by its tracking number")
    func tolerant() throws {
        let usps = try deliveries()[2]
        #expect(usps.status == .infoReceived)
        #expect(usps.title == "9400000000000000000003")
        #expect(try deliveries()[0].title == "Keyboard")
    }

    @Test("null and empty fields are absent, and events that say nothing are dropped")
    func absent() throws {
        let deliveries = try deliveries()
        #expect(deliveries[2].events.isEmpty)
        #expect(deliveries[0].extraInformation == nil)
        #expect(deliveries[3].extraInformation == nil)
        #expect(deliveries[3].events.map(\.text) == ["Ready for pickup at the locker"])
        #expect(deliveries[3].events[0].date == "")
        #expect(deliveries[3].expected == nil)
    }

    @Test("events stay newest first, with their place and note")
    func events() throws {
        let fedex = try deliveries()[0]
        #expect(fedex.latestEvent?.text == "Departed FedEx hub")
        #expect(fedex.latestEvent?.location == "Memphis, TN")
        #expect(fedex.events[1].additional == "Package received after cutoff")
    }

    @Test("expected: a window from the strings, the timestamps when Parcel has them, a day when that's all there is")
    func expected() throws {
        let deliveries = try deliveries()
        #expect(
            deliveries[0].expected
                == .init(start: newYorkDate(2026, 10, 9, 9), end: newYorkDate(2026, 10, 9, 13), hasTime: true))
        #expect(
            deliveries[1].expected
                == .init(
                    start: Date(timeIntervalSince1970: 1_791_468_000), end: Date(timeIntervalSince1970: 1_791_482_400),
                    hasTime: true))
        #expect(deliveries[2].expected == .init(start: newYorkDate(2026, 10, 12), hasTime: false))
    }

    @Test("a refusal carries Parcel's own message")
    func refusal() throws {
        let reply = try ParcelAPI.decodeDeliveries(Data(#"{"success":false,"error_message":"Invalid API key"}"#.utf8))
        #expect(!reply.success)
        #expect(reply.errorMessage == "Invalid API key")
        #expect(reply.deliveries.isEmpty)
    }

    @Test("a reply without its list is an error, not an empty list")
    func missingList() {
        #expect(throws: ParcelAPI.DecodingError.missingDeliveries) {
            try ParcelAPI.decodeDeliveries(Data(#"{"success":true}"#.utf8))
        }
        #expect(throws: ParcelAPI.DecodingError.notJSON) {
            try ParcelAPI.decodeDeliveries(Data("<html>Bad gateway</html>".utf8))
        }
    }

    @Test("carrier names, in the old shape and the new")
    func carriers() {
        let names = ParcelAPI.decodeCarriers(Data(#"{"ups":{"name":"UPS"},"dhl":"DHL Express","odd":{"x":1}}"#.utf8))
        #expect(names == ["ups": "UPS", "dhl": "DHL Express"])
    }
}
