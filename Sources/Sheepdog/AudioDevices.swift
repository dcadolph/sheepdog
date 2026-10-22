import CoreAudio
import Foundation

// AudioDevices wraps the CoreAudio calls Sheepdog needs for device lookup and volume.
enum AudioDevices {
    // defaultOutput returns the system's current default output device.
    static func defaultOutput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    // defaultInput returns the system's current default input device.
    static func defaultInput() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    // builtInOutput returns the Mac's built-in speakers, or nil when the Mac has none.
    static func builtInOutput() -> AudioDeviceID? {
        allDevices().first { device in
            transportType(device) == kAudioDeviceTransportTypeBuiltIn && hasStreams(device, scope: kAudioObjectPropertyScopeOutput)
        }
    }

    // isRunningSomewhere reports whether any process is using the device.
    static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    // VolumeSnapshot records a device's output volume and mute state so it can be restored.
    struct VolumeSnapshot {
        // Device is the device the snapshot belongs to.
        let device: AudioDeviceID
        // Volumes maps each settable element to its scalar volume.
        let volumes: [UInt32: Float32]
        // Muted is the mute state, or nil when the device has no mute control.
        let muted: UInt32?
    }

    // boost unmutes the device and raises each channel to at least level, returning what to restore.
    static func boost(_ device: AudioDeviceID, to level: Float32) -> VolumeSnapshot {
        var volumes: [UInt32: Float32] = [:]
        for element in volumeElements(device) {
            guard let current = volume(device, element: element) else {
                continue
            }
            volumes[element] = current
            if current < level {
                setVolume(device, element: element, value: level)
            }
        }
        let muted = mute(device)
        if muted == 1 {
            setMute(device, value: 0)
        }
        return VolumeSnapshot(device: device, volumes: volumes, muted: muted)
    }

    // restore puts a device's volume and mute state back to a snapshot.
    static func restore(_ snapshot: VolumeSnapshot) {
        for (element, value) in snapshot.volumes {
            setVolume(snapshot.device, element: element, value: value)
        }
        if let muted = snapshot.muted {
            setMute(snapshot.device, value: muted)
        }
    }

    // systemDevice reads a device id from a system object property.
    private static func systemDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    // allDevices lists every audio device on the system.
    private static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }
        return devices
    }

    // transportType returns how the device is connected.
    private static func transportType(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    // hasStreams reports whether the device has any streams in the given scope.
    private static func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    // volumeElements returns the elements whose output volume can be set: main, or else the first two channels.
    private static func volumeElements(_ device: AudioDeviceID) -> [UInt32] {
        if isSettable(device, selector: kAudioDevicePropertyVolumeScalar, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return [1, 2].filter { isSettable(device, selector: kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    // isSettable reports whether an output property can be written on an element.
    private static func isSettable(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else {
            return false
        }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    // volume reads an element's output volume.
    private static func volume(_ device: AudioDeviceID, element: UInt32) -> Float32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    // setVolume writes an element's output volume.
    private static func setVolume(_ device: AudioDeviceID, element: UInt32, value: Float32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: element
        )
        var newValue = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue)
    }

    // mute reads the device's output mute state, or nil when it has none.
    private static func mute(_ device: AudioDeviceID) -> UInt32? {
        guard isSettable(device, selector: kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain) else {
            return nil
        }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    // setMute writes the device's output mute state.
    private static func setMute(_ device: AudioDeviceID, value: UInt32) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var newValue = value
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &newValue)
    }
}
