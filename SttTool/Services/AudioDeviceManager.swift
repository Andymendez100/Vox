import CoreAudio
import Foundation
import os.log

private let deviceLogger = Logger(subsystem: "com.voxapp.app", category: "AudioDevice")

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    static let systemDefaultUID = "__system_default__"

    @Published var inputDevices: [AudioInputDevice] = []

    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultInputListenerBlock: AudioObjectPropertyListenerBlock?

    /// UID of the mic the user selected in Vox settings. Set externally.
    var preferredInputUID: String = systemDefaultUID

    init() {
        refreshDevices()
        installDeviceChangeListener()
        installDefaultInputListener()
    }

    deinit {
        // deinit is nonisolated, so inline the cleanup directly
        if let block = deviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
        if let block = defaultInputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }

    func refreshDevices() {
        inputDevices = enumerateInputDevices()
    }

    /// Maps a persisted UID string to an AudioDeviceID.
    /// Returns nil for system default (meaning "use whatever AVAudioEngine picks").
    func resolveDeviceID(forUID uid: String) -> AudioDeviceID? {
        guard uid != Self.systemDefaultUID else { return nil }
        return inputDevices.first(where: { $0.uid == uid })?.id
    }

    /// Ensure the macOS system default input matches the user's preference.
    /// Called at startup and whenever the default input changes (e.g. Bluetooth
    /// reconnects overnight and hijacks the input). This triggers a real
    /// Bluetooth HFP → A2DP profile switch, unlike AudioUnitSetProperty which
    /// changes the value but doesn't notify the Bluetooth stack.
    func enforcePreferredInput() {
        guard preferredInputUID != Self.systemDefaultUID else { return }
        guard let preferred = inputDevices.first(where: { $0.uid == preferredInputUID }) else { return }

        let current = Self.getSystemDefaultInputDevice()
        guard current != preferred.id else { return }

        // The current system default isn't our preferred mic — Bluetooth or
        // something else hijacked it. Switch it back.
        let currentName = inputDevices.first(where: { $0.id == current })?.name ?? "unknown"
        deviceLogger.notice("System input was \(currentName) (\(current)), enforcing \(preferred.name) (\(preferred.id))")
        Self.setSystemDefaultInputDevice(preferred.id)
    }

    // MARK: - System Default Input Device

    static func getSystemDefaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    @discardableResult
    static func setSystemDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &id
        )
        return status == noErr
    }

    // MARK: - CoreAudio Enumeration

    private func enumerateInputDevices() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let uid = getDeviceUID(deviceID: deviceID) else { return nil }
            let name = getDeviceName(deviceID: deviceID) ?? "Unknown Device"
            return AudioInputDevice(id: deviceID, uid: uid, name: name)
        }
    }

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(
            capacity: Int(dataSize) / MemoryLayout<AudioBufferList>.size + 1
        )
        defer { bufferListPointer.deallocate() }

        var size = dataSize
        let getStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferListPointer)
        guard getStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return nil }

        var name: Unmanaged<CFString>?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr, let cfName = name?.takeUnretainedValue() else { return nil }
        return cfName as String
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard status == noErr else { return nil }

        var uid: Unmanaged<CFString>?
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &uid)
        guard status == noErr, let cfUID = uid?.takeUnretainedValue() else { return nil }
        return cfUID as String
    }

    // MARK: - Device Change Listeners

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshDevices()
                self?.enforcePreferredInput()
            }
        }
        deviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    /// Listen for changes to the system default input device. When Bluetooth
    /// reconnects after sleep, macOS silently switches the input to the headset.
    /// This listener catches that and switches it back immediately.
    private func installDefaultInputListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.enforcePreferredInput()
            }
        }
        defaultInputListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

}
