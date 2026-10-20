import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

/// One battery, as the Batteries widget shows it.
public struct BatteryReading: Identifiable, Equatable, Sendable {
    public enum Kind: Int, Sendable, Comparable {
        // In the order the widget lists them, as the macOS widget does.
        case mac, ups, earbuds, earbudsCase, headphones, keyboard, trackpad, mouse, gamepad, speaker, other

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String
    public var name: String
    public var kind: Kind
    /// 0–100.
    public var level: Int
    public var charging = false
    /// The Mac in Low Power Mode, which the macOS widget shows in yellow.
    public var lowPower = false
    /// Both earbuds' levels when they differ, e.g. "L 80% · R 75%".
    public var detail: String?
    /// Bluetooth address, lowercased with no separators, to match a
    /// Bluetooth widget's device.
    public var address: String?

    public var isLow: Bool { level <= 20 && !charging }

    public var symbol: String {
        let name = name.lowercased()
        switch kind {
        // Only a Mac with a battery of its own has a reading.
        case .mac: return "laptopcomputer"
        case .ups: return "minus.plus.batteryblock"
        case .earbuds:
            if name.contains("airpods pro") { return "airpodspro" }
            return name.contains("airpods") ? "airpods" : "earbuds"
        case .earbudsCase:
            if name.contains("airpods pro") { return "airpodspro.chargingcase.wireless" }
            return name.contains("airpods") ? "airpods.chargingcase.wireless" : "earbuds.case"
        case .headphones:
            if name.contains("airpods max") { return "airpodsmax" }
            return name.contains("beats") ? "beats.headphones" : "headphones"
        case .keyboard: return "keyboard"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .mouse: return name.contains("magic") ? "magicmouse" : "computermouse"
        case .gamepad: return "gamecontroller"
        case .speaker: return "hifispeaker"
        case .other: return "battery.100percent"
        }
    }
}

/// Reads batteries from the three places macOS keeps them: power sources
/// (this Mac and a UPS), the I/O Registry (Magic Keyboard, Mouse and
/// Trackpad, and other accessories that report a level), and System
/// Information's Bluetooth report (AirPods and other headphones). iPhone,
/// iPad and Apple Watch levels aren't available to apps.
///
/// Everything here is nonisolated and returns Sendable values, so it can run
/// on a background queue.
public enum BatteryReader {

    // MARK: - This Mac and a UPS

    public static func powerSources() -> [BatteryReading] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return list.compactMap { source in
            (IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any])
                .flatMap { powerSource($0, macName: computerName) }
        }
    }

    /// Only the Mac's own battery and a UPS: accessories some versions of
    /// macOS also list here come from the I/O Registry instead, with their
    /// names and addresses.
    static func powerSource(_ description: [String: Any], macName: String) -> BatteryReading? {
        if let present = description[kIOPSIsPresentKey] as? Bool, !present { return nil }
        let kind: BatteryReading.Kind
        switch description[kIOPSTypeKey] as? String {
        case kIOPSInternalBatteryType: kind = .mac
        case kIOPSUPSType: kind = .ups
        default: return nil
        }
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
            let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
        else { return nil }
        let id = (description[kIOPSPowerSourceIDKey] as? Int).map(String.init) ?? kind.rawValue.description
        return BatteryReading(
            id: "power-\(id)",
            name: kind == .mac ? macName : (description[kIOPSNameKey] as? String ?? "UPS"),
            kind: kind,
            level: clamp(Int((Double(current) / Double(maximum) * 100).rounded())),
            charging: description[kIOPSIsChargingKey] as? Bool ?? false,
            lowPower: (description["LPM Active"] as? Bool) ?? false)
    }

    /// The Mac's name as Sharing shows it, e.g. "Mason's MacBook Pro".
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"
    }

    // MARK: - Accessories in the I/O Registry

    /// Every registry entry with a battery level: Apple's keyboards, mice and
    /// trackpads, and anything else that reports one the same way.
    public static func registryAccessories() -> [BatteryReading] {
        let matching: [String: Any] = ["IOProviderClass": "IOService", "IOPropertyExistsMatch": ["BatteryPercent"]]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var readings: [BatteryReading] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let dictionary = properties?.takeRetainedValue() as? [String: Any],
                let reading = accessory(dictionary)
            {
                readings.append(reading)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return readings
    }

    static func accessory(_ properties: [String: Any]) -> BatteryReading? {
        guard let level = properties["BatteryPercent"] as? Int, (0...100).contains(level) else { return nil }
        if let hasBattery = properties["HasBattery"] as? Bool, !hasBattery { return nil }
        let name = (properties["Product"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Accessory"
        let address = normalizedAddress(properties["DeviceAddress"] as? String ?? properties["SerialNumber"] as? String)
        // Undocumented: 0 is on battery and 4 is too (seen on some keyboards);
        // anything else is charging. Other battery apps read it the same way.
        let flags = properties["BatteryStatusFlags"] as? Int ?? 0
        return BatteryReading(
            id: "accessory-\(address ?? name)",
            name: name,
            kind: accessoryKind(name: name, notification: properties["BatteryLowNotificationType"] as? String),
            level: level,
            charging: flags != 0 && flags != 4,
            address: address)
    }

    /// From the name, or else the low-battery alert the accessory uses
    /// ("ExKB2LowBattery", "TPLowBattery", "MMLowBattery"), so a renamed one
    /// still gets its icon.
    static func accessoryKind(name: String, notification: String?) -> BatteryReading.Kind {
        let lowered = name.lowercased()
        if lowered.contains("keyboard") { return .keyboard }
        if lowered.contains("trackpad") { return .trackpad }
        if lowered.contains("mouse") { return .mouse }
        let alert = notification ?? ""
        if alert.hasPrefix("ExKB") || alert.hasPrefix("KB") { return .keyboard }
        if alert.hasPrefix("TP") { return .trackpad }
        if alert.hasPrefix("MM") || alert.hasPrefix("Mouse") { return .mouse }
        return .other
    }

    // MARK: - System Information's Bluetooth report

    /// AirPods and other headphones report their levels only here. Takes
    /// about a fifth of a second, so it's read less often than the rest.
    public static func bluetoothReport() -> [BatteryReading] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return bluetoothReport(data)
    }

    /// Connected devices only: a disconnected one keeps its last levels,
    /// which would read as current.
    static func bluetoothReport(_ data: Data) -> [BatteryReading] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = json["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        return sections.flatMap { section in
            (section["device_connected"] as? [[String: Any]] ?? []).flatMap { entry in
                entry.flatMap { name, info in (info as? [String: Any]).map { device(name: name, $0) } ?? [] }
            }
        }
    }

    private static func device(name: String, _ info: [String: Any]) -> [BatteryReading] {
        let address = normalizedAddress(info["device_address"] as? String)
        let base = "bluetooth-\(address ?? name)"
        let minorType = (info["device_minorType"] as? String ?? "").lowercased()
        let left = level(info["device_batteryLevelLeft"])
        let right = level(info["device_batteryLevelRight"])
        var readings: [BatteryReading] = []

        let buds = [left, right].compactMap { $0 }
        if let shown = buds.min(by: { $0.level < $1.level }) {
            var reading = BatteryReading(
                id: base, name: name, kind: .earbuds, level: shown.level,
                charging: buds.contains { $0.charging }, address: address)
            if let left, let right, left.level != right.level {
                reading.detail = "L \(left.level)% · R \(right.level)%"
            }
            readings.append(reading)
        } else if let main = level(info["device_batteryLevelMain"]) {
            readings.append(
                BatteryReading(
                    id: base, name: name, kind: bluetoothKind(minorType: minorType, name: name), level: main.level,
                    charging: main.charging, address: address))
        }
        if let box = level(info["device_batteryLevelCase"]) {
            readings.append(
                BatteryReading(
                    id: base + "-case", name: "\(name) Case", kind: .earbudsCase, level: box.level,
                    charging: box.charging, address: nil))
        }
        return readings
    }

    static func bluetoothKind(minorType: String, name: String) -> BatteryReading.Kind {
        let lowered = name.lowercased()
        if minorType.contains("keyboard") { return .keyboard }
        if minorType.contains("trackpad") { return .trackpad }
        if minorType.contains("mouse") { return .mouse }
        if minorType.contains("gamepad") || minorType.contains("joystick") || lowered.contains("controller") {
            return .gamepad
        }
        if minorType.contains("speaker") || minorType.contains("loudspeaker") { return .speaker }
        if minorType.contains("head") || lowered.contains("airpods") || lowered.contains("beats") {
            return .headphones
        }
        return .other
    }

    /// "80%", "+80%" while charging, or a bare number.
    static func level(_ value: Any?) -> (level: Int, charging: Bool)? {
        if let number = value as? Int { return (0...100).contains(abs(number)) ? (abs(number), false) : nil }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let digits = text.replacingOccurrences(of: "%", with: "")
        guard let number = Int(digits), (0...100).contains(abs(number)) else { return nil }
        return (abs(number), digits.hasPrefix("+"))
    }

    // MARK: - Together

    /// The registry's reading wins over System Information's for the same
    /// accessory: it's read more often, and knows when it's charging. This
    /// Mac comes first, then the rest as the macOS widget lists them.
    public static func merge(_ groups: [BatteryReading]...) -> [BatteryReading] {
        var seen = Set<String>()
        var merged: [BatteryReading] = []
        for reading in groups.joined() where seen.insert(reading.address ?? reading.id).inserted {
            merged.append(reading)
        }
        return merged.sorted {
            ($0.kind, $0.name.localizedLowercase, $0.id) < ($1.kind, $1.name.localizedLowercase, $1.id)
        }
    }

    /// Levels by Bluetooth address, for the Bluetooth widget. Earbuds give the
    /// lower of the two, as the widget shows them.
    public static func levelsByAddress(_ readings: [BatteryReading]) -> [String: Int] {
        var levels: [String: Int] = [:]
        for reading in readings where reading.kind != .earbudsCase {
            if let address = reading.address, levels[address] == nil { levels[address] = reading.level }
        }
        return levels
    }

    /// "48-e1-5c-bb-3b-13" or "48:E1:5C:BB:3B:13" → "48e15cbb3b13".
    public static func normalizedAddress(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.lowercased().filter(\.isHexDigit)
        return hex.count == 12 ? hex : nil
    }

    private static func clamp(_ level: Int) -> Int { min(100, max(0, level)) }
}
