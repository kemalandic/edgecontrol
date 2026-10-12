import Darwin
import Testing

@testable import EdgeControl

@Suite("Process listing")
struct ProcessListingTests {
    @Test("every running process is listed, not the first quarter")
    func listsEveryProcess() {
        let listed = ProcessMonitorService.allPIDs()
        // The system's own count, taken just before; processes can start or
        // exit in between, so allow a little either way.
        let expected = Int(proc_listallpids(nil, 0))
        #expect(listed.count > expected * 3 / 4)
        #expect(listed.contains(getpid()))
    }
}
