import CoreGraphics
import Foundation
import IOKit.ps
import Testing

@testable import EdgeControl

@Suite("Batteries: reading them")
struct BatteryReaderTests {

    // MARK: - This Mac and a UPS

    /// As IOPSGetPowerSourceDescription gives it for a MacBook.
    private func internalBattery(level: Int, charging: Bool, lowPower: Bool = false) -> [String: Any] {
        [
            kIOPSIsPresentKey: true, kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSNameKey: "InternalBattery-0",
            kIOPSCurrentCapacityKey: level, kIOPSMaxCapacityKey: 100, kIOPSIsChargingKey: charging,
            kIOPSPowerSourceStateKey: charging ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSPowerSourceIDKey: 37_093_475, "LPM Active": lowPower,
        ]
    }

    @Test("the Mac's own battery, by the Mac's name")
    func macBattery() throws {
        let reading = try #require(
            BatteryReader.powerSource(internalBattery(level: 42, charging: true), macName: "Test MacBook"))
        #expect(reading.kind == .mac)
        #expect(reading.name == "Test MacBook")
        #expect(reading.level == 42)
        #expect(reading.charging)
        #expect(reading.symbol == "laptopcomputer")
    }

    @Test("Low Power Mode is noted, for the yellow ring")
    func lowPowerMode() throws {
        let reading = try #require(
            BatteryReader.powerSource(internalBattery(level: 60, charging: false, lowPower: true), macName: "Mac"))
        #expect(reading.lowPower)
        #expect(!reading.isLow)
    }

    @Test("a UPS is listed; a battery that isn't there, or another kind of source, isn't")
    func otherSources() {
        var ups = internalBattery(level: 90, charging: false)
        ups[kIOPSTypeKey] = kIOPSUPSType
        ups[kIOPSNameKey] = "Back-UPS"
        #expect(BatteryReader.powerSource(ups, macName: "Mac")?.name == "Back-UPS")

        var absent = internalBattery(level: 90, charging: false)
        absent[kIOPSIsPresentKey] = false
        #expect(BatteryReader.powerSource(absent, macName: "Mac") == nil)

        var accessory = internalBattery(level: 90, charging: false)
        accessory[kIOPSTypeKey] = "Accessory Source"
        #expect(BatteryReader.powerSource(accessory, macName: "Mac") == nil)
    }

    // MARK: - Accessories in the I/O Registry

    /// As AppleDeviceManagementHIDEventService lists a Magic Keyboard.
    private let keyboard: [String: Any] = [
        "Product": "Test Magic Keyboard", "BatteryPercent": 68, "BatteryStatusFlags": 0, "HasBattery": true,
        "DeviceAddress": "aa-bb-cc-dd-ee-01", "BatteryLowNotificationType": "ExKB2LowBattery",
        "Transport": "Bluetooth",
    ]

    @Test("a Magic Keyboard, with its address to match the Bluetooth widget's")
    func magicKeyboard() throws {
        let reading = try #require(BatteryReader.accessory(keyboard))
        #expect(reading.kind == .keyboard)
        #expect(reading.level == 68)
        #expect(!reading.charging)
        #expect(reading.address == "aabbccddee01")
    }

    @Test(
        "the status flags: 0 and 4 are on battery, others are charging",
        arguments: [(0, false), (4, false), (3, true), (1, true)])
    func statusFlags(flags: Int, charging: Bool) throws {
        var properties = keyboard
        properties["BatteryStatusFlags"] = flags
        #expect(try #require(BatteryReader.accessory(properties)).charging == charging)
    }

    @Test("a renamed accessory still gets its icon from its low-battery alert")
    func renamedAccessory() {
        #expect(BatteryReader.accessoryKind(name: "Desk", notification: "TPLowBattery") == .trackpad)
        #expect(BatteryReader.accessoryKind(name: "Desk", notification: "MMLowBattery") == .mouse)
        #expect(BatteryReader.accessoryKind(name: "Desk", notification: "KBLowBattery") == .keyboard)
        #expect(BatteryReader.accessoryKind(name: "Desk", notification: nil) == .other)
    }

    @Test("no level, a level out of range, or no battery: nothing to show")
    func notBatteries() {
        var none = keyboard
        none["BatteryPercent"] = nil
        var wild = keyboard
        wild["BatteryPercent"] = 140
        var noBattery = keyboard
        noBattery["HasBattery"] = false
        #expect(BatteryReader.accessory(none) == nil)
        #expect(BatteryReader.accessory(wild) == nil)
        #expect(BatteryReader.accessory(noBattery) == nil)
    }

    // MARK: - System Information's Bluetooth report

    /// `system_profiler -json SPBluetoothDataType`, cut down.
    private let report = Data(
        """
        {
          "SPBluetoothDataType": [{
            "controller_properties": { "controller_state": "attrib_on" },
            "device_connected": [
              { "Test AirPods Pro": {
                  "device_address": "AA:BB:CC:DD:EE:02", "device_minorType": "Headphones",
                  "device_batteryLevelLeft": "80%", "device_batteryLevelRight": "75%",
                  "device_batteryLevelCase": "+45%" } },
              { "Test Headphones": {
                  "device_address": "AA:BB:CC:DD:EE:03", "device_minorType": "Headphones",
                  "device_batteryLevelMain": "55%" } },
              { "Test Phone": { "device_address": "AA:BB:CC:DD:EE:04" } }
            ],
            "device_not_connected": [
              { "Old Mouse": { "device_address": "AA:BB:CC:DD:EE:05", "device_batteryLevelMain": "10%" } }
            ]
          }]
        }
        """.utf8)

    @Test("AirPods show the lower earbud, both when they differ, and their case")
    func airPods() throws {
        let readings = BatteryReader.bluetoothReport(report)
        let buds = try #require(readings.first { $0.name == "Test AirPods Pro" })
        #expect(buds.kind == .earbuds)
        #expect(buds.level == 75)
        #expect(buds.detail == "L 80% · R 75%")
        #expect(buds.address == "aabbccddee02")
        #expect(buds.symbol == "airpodspro")

        let box = try #require(readings.first { $0.kind == .earbudsCase })
        #expect(box.name == "Test AirPods Pro Case")
        #expect(box.level == 45)
        #expect(box.charging)
        #expect(box.symbol == "airpodspro.chargingcase.wireless")
    }

    @Test("other headphones give one level; devices without one, and disconnected ones, are left out")
    func otherDevices() {
        let readings = BatteryReader.bluetoothReport(report)
        #expect(readings.first { $0.name == "Test Headphones" }?.level == 55)
        #expect(readings.first { $0.name == "Test Headphones" }?.kind == .headphones)
        #expect(!readings.contains { $0.name == "Test Phone" || $0.name == "Old Mouse" })
        #expect(readings.count == 3)
        #expect(BatteryReader.bluetoothReport(Data("not json".utf8)).isEmpty)
    }

    @Test(
        "levels read as System Information writes them",
        arguments: [("80%", 80, false), ("+45%", 45, true), ("-30%", 30, false), (" 7 % ", 7, false)])
    func levels(text: String, level: Int, charging: Bool) throws {
        let parsed = try #require(BatteryReader.level(text.replacingOccurrences(of: " ", with: "")))
        #expect(parsed.level == level)
        #expect(parsed.charging == charging)
    }

    @Test("a level that isn't one is ignored")
    func badLevels() {
        #expect(BatteryReader.level("full") == nil)
        #expect(BatteryReader.level("140%") == nil)
        #expect(BatteryReader.level(nil) == nil)
        #expect(BatteryReader.level(64)?.level == 64)
    }

    // MARK: - Together

    @Test("the registry's reading wins for the same accessory, and the Mac comes first")
    func merges() throws {
        let fromRegistry = try #require(BatteryReader.accessory(keyboard))
        var fromReport = fromRegistry
        fromReport.id = "bluetooth-aabbccddee01"
        fromReport.level = 10
        let mac = try #require(BatteryReader.powerSource(internalBattery(level: 50, charging: false), macName: "Mac"))
        let merged = BatteryReader.merge([fromRegistry], [mac], BatteryReader.bluetoothReport(report) + [fromReport])
        #expect(merged.first?.kind == .mac)
        #expect(merged.filter { $0.address == "aabbccddee01" }.map(\.level) == [68])
        #expect(merged.map(\.kind) == [.mac, .earbuds, .earbudsCase, .headphones, .keyboard])
    }

    @Test("the Bluetooth widget gets levels by address, not the case's")
    func levelsByAddress() {
        let levels = BatteryReader.levelsByAddress(BatteryReader.bluetoothReport(report))
        #expect(levels == ["aabbccddee02": 75, "aabbccddee03": 55])
    }

    @Test("addresses match whichever way they're written")
    func addresses() {
        #expect(BatteryReader.normalizedAddress("AA:BB:CC:DD:EE:01") == "aabbccddee01")
        #expect(BatteryReader.normalizedAddress("aa-bb-cc-dd-ee-01") == "aabbccddee01")
        #expect(BatteryReader.normalizedAddress("bt-12345") == nil)
        #expect(BatteryReader.normalizedAddress(nil) == nil)
    }
}

@Suite("Batteries: fitting the rings")
struct BatteryRingLayoutTests {

    private func fit(_ count: Int, _ width: CGFloat, _ height: CGFloat) -> BatteryRingLayout {
        BatteryRingLayout.fit(count: count, width: width, height: height, spacing: 8, label: 22)
    }

    @Test("a wide tile puts them in a row, as the macOS widget's medium size does")
    func row() {
        let layout = fit(4, 624, 224)
        #expect(layout.rows == 1)
        #expect(layout.columns == 4)
        #expect(layout.ring > 100)
    }

    @Test("a square tile makes a grid")
    func grid() {
        let layout = fit(4, 300, 300)
        #expect(layout.rows == 2)
        #expect(layout.columns == 2)
    }

    @Test("a big tile doesn't blow one ring up into a gauge")
    func largest() {
        #expect(fit(1, 1200, 700).ring == BatteryRingLayout.largest)
    }

    @Test("no batteries, no rings")
    func empty() {
        #expect(fit(0, 300, 300).ring == 0)
    }
}

@Suite("Batteries: what a small tile shows")
struct BatteryRingFittingTests {

    @Test("a small tile shows the first batteries that fit, not rings too small to read")
    func smallTile() {
        let fitted = BatteryRingLayout.fitting(count: 6, width: 232, height: 96, spacing: 8, label: 22)
        #expect(fitted.shown < 6)
        #expect(fitted.shown >= 1)
        #expect(fitted.layout.ring >= BatteryRingLayout.smallest)
    }

    @Test("a tile with room shows them all")
    func roomForAll() {
        #expect(BatteryRingLayout.fitting(count: 6, width: 1000, height: 220, spacing: 8, label: 22).shown == 6)
    }
}

@Suite("Bluetooth widget: device icons")
struct BluetoothDeviceIconTests {
    @Test("a trackpad or mouse isn't drawn as a keyboard, though Bluetooth files them together")
    func icons() {
        let peripheral = "Peripheral/Keyboard/Mouse"
        func icon(_ name: String) -> String {
            BTDevice(id: "x", name: name, isConnected: true, deviceType: peripheral, batteryLevel: nil).icon
        }
        #expect(icon("Test Magic Trackpad") == "rectangle.and.hand.point.up.left")
        #expect(icon("Test Magic Mouse") == "computermouse")
        #expect(icon("Test Magic Keyboard") == "keyboard")
    }
}
