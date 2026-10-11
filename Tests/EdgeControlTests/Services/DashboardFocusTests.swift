import AppKit
import Foundation
import SwiftUI
import Testing

@testable import EdgeControl

/// The dashboard never takes focus from the display you're working on, and
/// opens its controls to assistive tools when one is in use.
@MainActor
@Suite struct DashboardFocusTests {
    @Test func dashboardIsANonActivatingPanelThatStaysVisibleInTheBackground() {
        _ = NSApplication.shared
        let panel = KioskWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), neverActivates: true)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.becomesKeyOnlyIfNeeded)
        #expect(panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.identifier == DashboardFocus.windowIdentifier)
    }

    @Test func withTheSettingOffTheDashboardIsAnOrdinaryWindow() {
        _ = NSApplication.shared
        let window = KioskWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), neverActivates: false)
        #expect(!window.styleMask.contains(.nonactivatingPanel))
        #expect(window.canBecomeMain)
    }

    @Test func placementKeepsTheNonActivatingStyle() {
        _ = NSApplication.shared
        let panel = KioskWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), neverActivates: true)
        WindowPlacement.configure(panel, display: nil, kioskMode: false)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.styleMask.contains(.titled))
    }

    @Test func voiceControlAndKeyboardAccessPreferencesAreReadAsFlags() {
        #expect(AccessibilityExposure.anyEnabled([NSNumber(value: 0), nil, NSNumber(value: 1)]))
        #expect(!AccessibilityExposure.anyEnabled([NSNumber(value: 0), nil]))
    }

    /// SwiftUI only builds its elements once an assistive client connects,
    /// so this checks the hand-off: hidden returns nil, exposed defers to
    /// SwiftUI.
    @Test func dashboardTreeIsHiddenUntilAnAssistiveToolNeedsIt() {
        let host = KioskHostingView(rootView: AnyView(Button("Play") {}))
        AccessibilityExposure.testOverride = false
        #expect(host.accessibilityChildren() == nil)
        #expect(host.accessibilityLabel() == "EdgeControl dashboard")
        AccessibilityExposure.testOverride = true
        #expect(host.accessibilityChildren() != nil)
        AccessibilityExposure.testOverride = nil
        AccessibilityExposure.alwaysExpose = true
        #expect(host.accessibilityChildren() != nil)
        AccessibilityExposure.alwaysExpose = false
    }

    @Test func existingLayoutsDefaultToNeverTakingFocus() throws {
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
        #expect(decoded.dashboardNeverTakesFocus)
        #expect(!decoded.alwaysExposeAccessibility)
        var changed = decoded
        changed.dashboardNeverTakesFocus = false
        changed.alwaysExposeAccessibility = true
        let roundTrip = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(changed))
        #expect(!roundTrip.dashboardNeverTakesFocus && roundTrip.alwaysExposeAccessibility)
    }
}
