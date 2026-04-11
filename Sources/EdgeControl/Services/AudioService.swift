import CoreAudio
import Foundation

@MainActor
public final class AudioService: ObservableObject {
    @Published public var volume: Float = 0
    @Published public var isMuted: Bool = false
    @Published public var outputDeviceName: String = "Unknown"

    private var defaultDeviceID: AudioObjectID = 0
    /// The device ID that currently has volume/mute listeners installed.
    /// Zero means no listeners are installed.
    private var listenedDeviceID: AudioObjectID = 0
    private var deviceListenerInstalled = false

    /// Stored listener blocks for proper removal via AudioObjectRemovePropertyListenerBlock.
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceChangeListenerBlock: AudioObjectPropertyListenerBlock?

    public init() {}

    public func start() {
        stop()
        refreshDevice()
        sample()
        installListeners()
    }

    public func stop() {
        removeDeviceListeners()
        removeSystemListener()
    }

    /// Remove the system-level default device change listener.
    private func removeSystemListener() {
        guard deviceListenerInstalled, let block = deviceChangeListenerBlock else { return }
        var dAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &dAddr, DispatchQueue.main, block)
        deviceChangeListenerBlock = nil
        deviceListenerInstalled = false
    }

    // MARK: - CoreAudio Property Listeners

    private func installListeners() {
        guard defaultDeviceID != 0 else { return }

        // If already listening on this device, skip
        if listenedDeviceID == defaultDeviceID { return }

        // Remove old device listeners first
        removeDeviceListeners()

        // Create and store listener blocks so we can remove them later
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.sample() }
        }
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.sample() }
        }
        volumeListenerBlock = volBlock
        muteListenerBlock = muteBlock

        var vAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &vAddr, DispatchQueue.main, volBlock)

        var mAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(defaultDeviceID, &mAddr, DispatchQueue.main, muteBlock)

        listenedDeviceID = defaultDeviceID

        // Default device change listener (system-level, only install once per start cycle)
        if !deviceListenerInstalled {
            let devBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    self?.refreshDevice()
                    self?.sample()
                    self?.installListeners()
                }
            }
            deviceChangeListenerBlock = devBlock
            var dAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &dAddr, DispatchQueue.main, devBlock)
            deviceListenerInstalled = true
        }
    }

    /// Remove volume and mute listeners from the currently listened device.
    private func removeDeviceListeners() {
        guard listenedDeviceID != 0 else { return }

        if let block = volumeListenerBlock {
            var vAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &vAddr, DispatchQueue.main, block)
            volumeListenerBlock = nil
        }

        if let block = muteListenerBlock {
            var mAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &mAddr, DispatchQueue.main, block)
            muteListenerBlock = nil
        }

        listenedDeviceID = 0
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
        volume = readVolume() ?? 0
        isMuted = readMute()
        outputDeviceName = readDeviceName()
    }

    private func readVolume() -> Float? {
        if let vol = getFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 0) {
            return vol
        }
        if let vol = getFloat32Property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, channel: 1) {
            return vol
        }
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
