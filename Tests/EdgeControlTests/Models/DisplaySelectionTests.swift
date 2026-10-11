import Testing

@testable import EdgeControl

/// The dashboard's display choice while monitors sleep, unplug and come back.
/// Before this, a missing preferred display was replaced in memory by whatever
/// screen was first, so the dashboard stayed there after the display returned.
@Suite struct DisplaySelectionTests {
    private func screen(_ name: String, main: Bool = false, id: String? = nil) -> DisplayDescriptor {
        DisplayDescriptor(id: id ?? name, name: name, width: 2560, height: 720, scaleFactor: 1, isMain: main)
    }

    @Test func choosesThePreferredDisplay() {
        let edge = screen("XENEON EDGE")
        #expect(
            DisplaySelection.resolve(
                [screen("Built-in", main: true), screen("Studio Display"), edge], preferredName: edge.name) == edge)
    }

    @Test func unpluggedPreferredDisplayIsUnavailableRatherThanReplaced() {
        #expect(
            DisplaySelection.resolve(
                [screen("Built-in", main: true), screen("Studio Display")], preferredName: "XENEON EDGE") == nil)
    }

    @Test func emptyTopologyDuringWakeLeavesNoTarget() {
        #expect(DisplaySelection.resolve([], preferredName: "XENEON EDGE") == nil)
    }

    @Test func reconnectedDisplayIsFoundDespiteNewIDAndOrder() {
        let returned = screen("XENEON EDGE", id: "new-display-id")
        #expect(
            DisplaySelection.resolve(
                [screen("Studio Display"), returned, screen("Built-in", main: true)], preferredName: "XENEON EDGE")
                == returned)
    }

    /// NSScreen.main follows keyboard focus, so the dashboard's own display
    /// can be "main" while the dashboard is key.
    @Test func preferredDisplayStaysEligibleWhenItIsMain() {
        let focused = screen("XENEON EDGE", main: true)
        #expect(DisplaySelection.resolve([screen("Built-in"), focused], preferredName: "XENEON EDGE") == focused)
    }

    @Test func firstLaunchPrefersASecondaryDisplay() {
        let studio = screen("Studio Display")
        #expect(DisplaySelection.resolve([screen("Built-in", main: true), studio], preferredName: nil) == studio)
    }

    @Test func firstLaunchWorksOnALaptopAlone() {
        let laptop = screen("Built-in", main: true)
        #expect(DisplaySelection.resolve([laptop], preferredName: nil) == laptop)
    }
}
