import CoreAudio
import Foundation

actor AudioMuteService {
    private var previousMuteState: UInt32 = 0
    private var isMutedByUs = false

    func muteOutput() {
        guard let deviceID = getDefaultOutputDevice() else { return }
        previousMuteState = getMuteState(deviceID: deviceID)
        setMuteState(deviceID: deviceID, muted: 1)
        isMutedByUs = true
    }

    func restoreOutput() {
        guard isMutedByUs, let deviceID = getDefaultOutputDevice() else { return }
        setMuteState(deviceID: deviceID, muted: previousMuteState)
        isMutedByUs = false
    }

    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private func getMuteState(deviceID: AudioDeviceID) -> UInt32 {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &muted)
        return muted
    }

    private func setMuteState(deviceID: AudioDeviceID, muted: UInt32) {
        var value = muted
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
    }
}
