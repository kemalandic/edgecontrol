import Foundation
import IOKit

// MARK: - SMC Data Structures (matching Stats/SMC layout exactly)

private struct SMCKeyData_t {
    typealias SMCBytes_t = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                            UInt8, UInt8, UInt8, UInt8)

    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }

    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let KERNEL_INDEX_SMC: UInt8 = 2
private let SMC_CMD_READ_BYTES: UInt8 = 5
private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_INDEX: UInt8 = 8

// MARK: - Low-Level SMC Access

private class SMCConnection {
    private var conn: io_connect_t = 0

    init?() {
        var iterator: io_iterator_t = 0
        let matchingDictionary = IOServiceMatching("AppleSMC")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)
        guard result == kIOReturnSuccess else { return nil }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else { return nil }

        let openResult = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        guard openResult == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(conn)
    }

    func call(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        var inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }

    func readKey(_ key: String) -> (dataType: String, dataSize: UInt32, bytes: [UInt8])? {
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()

        input.key = fourCharCode(key)
        input.data8 = SMC_CMD_READ_KEYINFO

        var result = call(KERNEL_INDEX_SMC, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return nil }

        let dataType = output.keyInfo.dataType
        let dataSize = output.keyInfo.dataSize

        input.keyInfo.dataSize = dataSize
        input.keyInfo.dataType = dataType
        input.data8 = SMC_CMD_READ_BYTES

        result = call(KERNEL_INDEX_SMC, input: &input, output: &output)
        guard result == kIOReturnSuccess else { return nil }

        let typeBytes = withUnsafeBytes(of: dataType.bigEndian) { Array($0) }
        let typeStr = String(bytes: typeBytes, encoding: .ascii) ?? "????"

        let rawBytes = withUnsafeBytes(of: output.bytes) { Array($0) }

        return (typeStr, UInt32(dataSize), Array(rawBytes.prefix(Int(dataSize))))
    }

    func getValue(_ key: String) -> Double? {
        guard let data = readKey(key) else { return nil }
        let bytes = data.bytes

        // Check all zero
        if bytes.allSatisfy({ $0 == 0 }) { return nil }

        switch data.dataType {
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "sp78":
            let raw = Int16(Int16(bytes[0]) << 8 | Int16(bytes[1]))
            return Double(raw) / 256.0
        case "sp87":
            let raw = Int16(Int16(bytes[0]) << 8 | Int16(bytes[1]))
            return Double(raw) / 128.0
        case "sp96":
            let raw = Int16(Int16(bytes[0]) << 8 | Int16(bytes[1]))
            return Double(raw) / 64.0
        case "spa5":
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 32.0
        case "spb4":
            let raw = Int16(Int16(bytes[0]) << 8 | Int16(bytes[1]))
            return Double(raw) / 16.0
        case "spf0":
            return Double(Int16(bytes[0]) << 8 | Int16(bytes[1]))
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let value = bytes.withUnsafeBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: Float32.self, capacity: 1) { $0.pointee }
            }
            return Double(value)
        case "fpe2":
            return Double((Int(bytes[0]) << 6) + (Int(bytes[1]) >> 2))
        default:
            return nil
        }
    }
}

private func fourCharCode(_ str: String) -> UInt32 {
    str.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

// MARK: - Core Temperature Data

public struct CoreTemp: Identifiable, Equatable {
    public let id: String      // "P0", "E3", etc.
    public let label: String   // "P0", "E3"
    public let temperature: Double
    public let isPerformance: Bool

    public init(id: String, label: String, temperature: Double, isPerformance: Bool) {
        self.id = id
        self.label = label
        self.temperature = temperature
        self.isPerformance = isPerformance
    }
}

// MARK: - Public SMC Service

@MainActor
public final class SMCService: ObservableObject {
    @Published public var cpuTemperature: Double?
    @Published public var gpuTemperature: Double?
    @Published public var ssdTemperature: Double?
    @Published public var memoryTemperature: Double?
    @Published public var fanCount: Int = 0
    @Published public var fanSpeeds: [Double] = []

    // Temperature history (60 samples = ~3 minutes at 3s interval)
    @Published public var cpuTempHistory: [Double] = []
    @Published public var gpuTempHistory: [Double] = []
    @Published public var ssdTempHistory: [Double] = []
    @Published public var memTempHistory: [Double] = []

    // Per-core CPU temperatures
    @Published public var cpuCoreTemps: [CoreTemp] = []

    private var smc: SMCConnection?
    private var timer: Timer?
    private let maxHistory = 60

    // Apple Silicon M-series temperature keys
    private let cpuKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp0T",
        // Fallback Intel keys
        "TC0D", "TC0E", "TC0F", "TC0P", "TCAD",
        "TC1c", "TC2c", "TC3c", "TC4c", "TC5c", "TC6c", "TC7c", "TC8c",
        "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C"
    ]
    private let gpuKeys = [
        "Tg05", "Tg0D", "Tg0L", "Tg0T",
        "TG0D", "TG0H", "TG0P", "TCGC"
    ]
    private let ssdKeys = ["TH0a", "TH0b", "TH0x", "TH0A", "TH0B", "TH0C", "TH1A", "TPSD"]
    private let memKeys = ["Th00", "Th04", "Th08", "Th0C", "Th50", "Th54", "Th58", "Th5C", "TMVR", "Tm02", "Tm06", "Tm08", "Tm09", "Tm0P"]

    // M3 Ultra per-core keys (from SMC scan)
    // P-cores: Tp04-Tp3X series (high values ~60-80°C)
    // E-cores: Tp54-Tp8X series (lower values ~50-65°C)
    private let pCoreKeys: [(String, String)] = [
        ("Tp06", "P0"), ("Tp0c", "P1"), ("Tp0E", "P2"), ("Tp0i", "P3"),
        ("Tp0M", "P4"), ("Tp0W", "P5"), ("Tp10", "P6"), ("Tp1G", "P7"),
        ("Tp1i", "P8"), ("Tp1K", "P9"), ("Tp1q", "P10"), ("Tp1S", "P11"),
        ("Tp2B", "P12"), ("Tp2J", "P13"), ("Tp2R", "P14"), ("Tp2t", "P15"),
        ("Tp31", "P16"), ("Tp35", "P17"), ("Tp3D", "P18"), ("Tp3P", "P19"),
    ]
    private let eCoreKeys: [(String, String)] = [
        ("Tp56", "E0"), ("Tp5c", "E1"), ("Tp5i", "E2"), ("Tp5W", "E3"),
        ("Tp68", "E4"), ("Tp6G", "E5"), ("Tp6S", "E6"), ("Tp7B", "E7"),
    ]

    public init() {}

    public func start() {
        stop()
        smc = SMCConnection()
        guard smc != nil else {
            print("SMCService: Failed to connect to AppleSMC")
            return
        }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        smc = nil
    }

    private func sample() {
        guard let smc else { return }

        cpuTemperature = averageTemp(smc: smc, keys: cpuKeys)
        gpuTemperature = averageTemp(smc: smc, keys: gpuKeys)
        ssdTemperature = averageTemp(smc: smc, keys: ssdKeys)
        memoryTemperature = averageTemp(smc: smc, keys: memKeys)

        // Temperature history
        if let t = cpuTemperature { appendHistory(&cpuTempHistory, value: t) }
        if let t = gpuTemperature { appendHistory(&gpuTempHistory, value: t) }
        if let t = ssdTemperature { appendHistory(&ssdTempHistory, value: t) }
        if let t = memoryTemperature { appendHistory(&memTempHistory, value: t) }

        // Per-core temperatures
        var cores: [CoreTemp] = []
        for (key, label) in pCoreKeys {
            if let temp = smc.getValue(key), temp > 0, temp < 130 {
                cores.append(CoreTemp(id: label, label: label, temperature: temp, isPerformance: true))
            }
        }
        for (key, label) in eCoreKeys {
            if let temp = smc.getValue(key), temp > 0, temp < 130 {
                cores.append(CoreTemp(id: label, label: label, temperature: temp, isPerformance: false))
            }
        }
        cpuCoreTemps = cores

        // Fan count and speeds
        if let count = smc.getValue("FNum") {
            fanCount = Int(count)
            fanSpeeds = (0..<fanCount).compactMap { i in
                smc.getValue("F\(i)Ac")
            }
        }
    }

    private func appendHistory(_ history: inout [Double], value: Double) {
        history.append(value)
        if history.count > maxHistory { history.removeFirst() }
    }

    private func averageTemp(smc: SMCConnection, keys: [String]) -> Double? {
        let values = keys.compactMap { smc.getValue($0) }.filter { $0 > 0 && $0 < 130 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
