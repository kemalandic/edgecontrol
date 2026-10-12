import Testing

@testable import EdgeControl

@Suite("Weather retries")
struct WeatherRetryTests {
    @Test("a failed fetch is retried after 30 s, 2 min and 5 min, then waits for the regular refresh")
    func retrySchedule() {
        let delays = (0...4).map { WeatherDataService.retryDelay(afterFailures: $0) }
        #expect(delays == [nil, .seconds(30), .seconds(120), .seconds(300), nil])
    }
}
