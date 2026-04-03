import AppKit
import CoreGraphics
import Foundation
import IOKit.hid

// MARK: - Touch Logger

private enum TouchLogger {
    private static let logURL: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        let directory = base.appendingPathComponent("Logs/EdgeControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("touch.log")
    }()

    static func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
            return
        }
        try? data.write(to: logURL, options: .atomic)
    }
}

// MARK: - HID Touch Input Source

@MainActor
protocol TouchInputSource: AnyObject {
    var onSample: ((RawTouchSample) -> Void)? { get set }
    var onOpenStatus: ((String) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class HIDTouchInputSource: NSObject, TouchInputSource {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var onSample: ((RawTouchSample) -> Void)?
    var onOpenStatus: ((String) -> Void)?
    private var sample = RawTouchSample()
    private var started = false
    private var openedDevices: [IOHIDDevice] = []

    // Corsair XENEON EDGE vendor/product IDs
    private let vendorID = 10176
    private let productID = 2137

    func start() {
        guard !started else { return }
        started = true
        TouchLogger.log("HID touch source start")

        let matchings: [[String: Any]] = [
            [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: productID,
                kIOHIDPrimaryUsagePageKey as String: 1,
                kIOHIDPrimaryUsageKey as String: 2
            ],
            [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: productID,
                kIOHIDPrimaryUsagePageKey as String: 13,
                kIOHIDPrimaryUsageKey as String: 4
            ],
            [
                kIOHIDVendorIDKey as String: vendorID,
                kIOHIDProductIDKey as String: productID,
                kIOHIDPrimaryUsagePageKey as String: 65290,
                kIOHIDPrimaryUsageKey as String: 255
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matchings as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            Unmanaged<HIDTouchInputSource>.fromOpaque(context).takeUnretainedValue().handle(value: value)
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDTouchInputSource>.fromOpaque(context).takeUnretainedValue().openMatchedDevicesIfNeeded()
        }, Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDTouchInputSource>.fromOpaque(context).takeUnretainedValue().refreshOpenStatus()
        }, Unmanaged.passUnretained(self).toOpaque())

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if result != kIOReturnSuccess {
            let status = "manager open failed (\(result))"
            TouchLogger.log(status)
            onOpenStatus?(status)
            return
        }

        openMatchedDevicesIfNeeded()
    }

    func stop() {
        guard started else { return }
        TouchLogger.log("HID touch source stop")
        openedDevices.forEach { device in
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        openedDevices.removeAll()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        started = false
    }

    private func openMatchedDevicesIfNeeded() {
        let devices = ((IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? [])
            .sorted { usageKey($0) < usageKey($1) }

        openedDevices = devices.filter { device in
            guard !openedDevices.contains(where: { $0 === device }) else { return true }
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            let success = result == kIOReturnSuccess
            TouchLogger.log("device \(usageKey(device)) open \(success ? "ok" : "failed (\(result))")")
            if !success {
                IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            }
            return success
        }
        refreshOpenStatus()
    }

    private func refreshOpenStatus() {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        openedDevices = openedDevices.filter { current in devices.contains(where: { $0 === current }) }

        let status: String
        switch (openedDevices.count, devices.count) {
        case (_, 0): status = "no XENEON HID devices found"
        case let (a, t) where a == t: status = "seize active (\(a)/\(t))"
        case (0, let t): status = "seize failed (0/\(t))"
        default: status = "partial seize (\(openedDevices.count)/\(devices.count))"
        }
        TouchLogger.log(status)
        onOpenStatus?(status)
    }

    private func usageKey(_ device: IOHIDDevice) -> String {
        let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? -1
        let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? -1
        return "u\(page):\(usage)"
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        switch (IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element)) {
        case (1, 48): sample.x = IOHIDValueGetIntegerValue(value)
        case (1, 49): sample.y = IOHIDValueGetIntegerValue(value)
        case (9, 1): sample.pressed = IOHIDValueGetIntegerValue(value) != 0
        default: return
        }
        onSample?(sample)
    }
}

// MARK: - Hardware Touch Service

@MainActor
public final class HardwareTouchService: ObservableObject {
    @Published public private(set) var state = TouchRuntimeState()

    // Touch gesture detection
    @Published public private(set) var swipeDirection: SwipeDirection?

    public enum SwipeDirection: Equatable {
        case left, right
    }

    /// Zone registry for tap-to-action (no mouse movement needed)
    public let zoneRegistry = TouchZoneRegistry()

    private var touchSource: TouchInputSource?
    private var calibration = CalibrationModel()
    private var dwellCalibration = DwellCalibrationState()
    private var latestSample = RawTouchSample()
    private var renderBounds = CGRect(x: 0, y: 0, width: 2560, height: 720)
    private var timer: Timer?
    private var hidStatus = "starting"
    private var eventSequence = 0
    private var pressSequence = 0
    private var previousPressed = false

    // Swipe tracking
    private var touchStartPoint: CGPoint?
    private var touchStartTime: Date?

    public init() {}

    public func start() {
        stop()
        TouchLogger.log("hardware touch service start")

        if let saved = CalibrationPersistence.load() {
            calibration = saved
            if saved.validationError() == nil {
                dwellCalibration.markComplete()
            }
        }

        let source = HIDTouchInputSource()
        source.onSample = { [weak self] sample in
            self?.handle(sample: sample)
        }
        source.onOpenStatus = { [weak self] status in
            guard let self else { return }
            self.hidStatus = status
            self.eventSequence += 1
            self.refreshState()
        }
        source.start()
        touchSource = source

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickCalibration(delta: 1.0 / 30.0)
            }
        }
        refreshState()
    }

    public func stop() {
        TouchLogger.log("hardware touch service stop")
        timer?.invalidate()
        timer = nil
        touchSource?.stop()
        touchSource = nil
        latestSample = RawTouchSample()
        hidStatus = "inactive"
        eventSequence = 0
        pressSequence = 0
        previousPressed = false
        state = TouchRuntimeState()
    }

    public func updateRenderBounds(_ bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        renderBounds = bounds
        refreshState()
    }

    public func resetCalibration() {
        calibration = CalibrationModel()
        dwellCalibration = DwellCalibrationState()
        try? CalibrationPersistence.clear()
        refreshState()
    }

    public func consumeSwipe() {
        swipeDirection = nil
    }

    private func handle(sample: RawTouchSample) {
        let wasPressed = previousPressed

        if sample.pressed && !wasPressed {
            pressSequence += 1
            // Swipe start
            let rawPoint = CGPoint(x: sample.x, y: sample.y)
            if let mapped = calibration.mappedPoint(for: rawPoint, in: renderBounds) {
                touchStartPoint = mapped
                touchStartTime = Date()
            }
        }

        if !sample.pressed && wasPressed {
            // Touch release — classify as tap or swipe
            if let startPoint = touchStartPoint,
               let startTime = touchStartTime {
                let rawPoint = CGPoint(x: latestSample.x, y: latestSample.y)
                if let endPoint = calibration.mappedPoint(for: rawPoint, in: renderBounds) {
                    let dx = endPoint.x - startPoint.x
                    let dy = endPoint.y - startPoint.y
                    let distance = hypot(dx, dy)
                    let duration = Date().timeIntervalSince(startTime)

                    if abs(dx) > 100 && abs(dx) > abs(dy) * 2 && duration < 1.0 {
                        // Swipe
                        swipeDirection = dx < 0 ? .left : .right
                    } else if distance < 30 && duration < 0.4 {
                        // Tap — hit-test registered touch zones
                        let hit = zoneRegistry.handleTap(at: startPoint)
                        TouchLogger.log("tap at (\(Int(startPoint.x)),\(Int(startPoint.y))) — \(hit ? "hit" : "miss")")
                    }
                }
            }
            touchStartPoint = nil
            touchStartTime = nil
        }

        previousPressed = sample.pressed
        eventSequence += 1
        latestSample = sample
        refreshState()
    }

    private func tickCalibration(delta: TimeInterval) {
        if let corner = dwellCalibration.activeCorner {
            let rawPoint = CGPoint(x: latestSample.x, y: latestSample.y)
            if dwellCalibration.update(point: rawPoint, pressed: latestSample.pressed, delta: delta) {
                calibration.set(corner, point: rawPoint)
                try? CalibrationPersistence.save(calibration)
                dwellCalibration.advance()
            }
            refreshState()
        }
    }

    private func refreshState() {
        let rawPoint = CGPoint(x: latestSample.x, y: latestSample.y)
        let validation = calibration.validationError()
        let mappedPoint = validation == nil ? calibration.mappedPoint(for: rawPoint, in: renderBounds) : nil
        state = TouchRuntimeState(
            rawSample: latestSample,
            mappedPoint: mappedPoint,
            hidStatus: hidStatus,
            calibrationStatus: dwellCalibration.statusText,
            calibrationValidation: validation ?? "Calibrated",
            calibrationSummary: calibration.summary,
            isCalibrated: validation == nil,
            isPressed: latestSample.pressed,
            sequence: eventSequence,
            pressSequence: pressSequence
        )
    }
}
