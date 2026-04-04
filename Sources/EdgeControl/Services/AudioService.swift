import CoreAudio
import Foundation

@MainActor
public final class AudioService: ObservableObject {
    @Published public var volume: Float = 0
    @Published public var isMuted: Bool = false
    @Published public var outputDeviceName: String = "Unknown"

    private var timer: Timer?
    private var defaultDeviceID: AudioObjectID = 0

    public init() {}

    public func start() {
        stop()
        refreshDevice()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshDevice() {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let result = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if result == noErr {
            defaultDeviceID = deviceID
        }
    }

    private func sample() {
        refreshDevice()
        guard defaultDeviceID != 0 else { return }

        // Try multiple approaches to read volume
        volume = readVolume() ?? 0
        isMuted = readMute()
        outputDeviceName = readDeviceName()
    }

    private func readVolume() -> Float? {
        // Approach 1: Main volume (channel 0)
        if let vol = getFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 0) {
            return vol
        }
        // Approach 2: Channel 1 (left)
        if let vol = getFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 1) {
            return vol
        }
        // Approach 3: Channel 2 (right)
        if let vol = getFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 2) {
            return vol
        }
        return nil
    }

    private func readMute() -> Bool {
        if let mute = getUInt32Property(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, channel: 0) {
            return mute != 0
        }
        return false
    }

    private func readDeviceName() -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &name) == noErr {
            return name as String
        }
        return "Unknown"
    }

    // MARK: - Volume Control

    public func setVolume(_ newVolume: Float) {
        let clamped = max(0, min(1, newVolume))
        guard defaultDeviceID != 0 else { return }

        // Try channel 0 first, then channel 1+2
        if !setFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 0, value: clamped) {
            setFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 1, value: clamped)
            setFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 2, value: clamped)
        }
        volume = clamped
    }

    public func toggleMute() {
        guard defaultDeviceID != 0 else { return }
        let newMute: UInt32 = isMuted ? 0 : 1
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = newMute
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &value)
        isMuted = newMute != 0
    }

    public func volumeUp() {
        setVolume(min(volume + 0.05, 1.0))
    }

    public func volumeDown() {
        setVolume(max(volume - 0.05, 0.0))
    }

    // MARK: - Helpers

    private func getFloat32Property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, channel: UInt32) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: channel)
        guard AudioObjectHasProperty(defaultDeviceID, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let result = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &value)
        return result == noErr ? value : nil
    }

    private func getUInt32Property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, channel: UInt32) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: channel)
        guard AudioObjectHasProperty(defaultDeviceID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let result = AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &value)
        return result == noErr ? value : nil
    }

    @discardableResult
    private func setFloat32Property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, channel: UInt32, value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: channel)
        guard AudioObjectHasProperty(defaultDeviceID, &address) else { return false }
        var val = value
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &val) == noErr
    }
}
