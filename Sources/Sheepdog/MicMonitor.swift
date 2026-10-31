import CoreAudio
import Foundation

// MicMonitor reports when the default input device starts being used by any app.
@MainActor
final class MicMonitor {
    // onStart is called each time the microphone goes from idle to in use.
    var onStart: (() -> Void)?
    // startedAt is when the microphone last went from idle to in use, nil while it is idle.
    private(set) var startedAt: Date?
    // device is the input device being watched.
    private var device: AudioDeviceID?
    // wasRunning is the last observed in-use state.
    private var wasRunning = false
    // runningListener is the registered in-use listener block.
    private var runningListener: AudioObjectPropertyListenerBlock?

    // runningAddress is the property that reports whether a device is in use.
    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // defaultInputAddress is the property that names the default input device.
    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    // isRunning reports whether the watched microphone is in use right now.
    var isRunning: Bool {
        device.map(AudioDevices.isRunningSomewhere) ?? false
    }

    // start begins watching the default input and follows it when the default changes.
    func start() {
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultInputAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.watchDefaultInput()
            }
        }
        watchDefaultInput()
    }

    // watchDefaultInput moves the in-use listener to the current default input device.
    private func watchDefaultInput() {
        if let device, let runningListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.runningAddress, DispatchQueue.main, runningListener)
        }
        let wasLive = wasRunning
        device = AudioDevices.defaultInput()
        wasRunning = isRunning
        // A switch of default input while a call runs is the same call, so it keeps its start. A device
        // that is already running when it becomes the default, or at launch, is dated from now, the
        // earliest moment Sheepdog knows of it.
        if !wasRunning {
            startedAt = nil
        } else if !wasLive || startedAt == nil {
            startedAt = Date()
        }
        guard let device else {
            return
        }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.check()
            }
        }
        runningListener = listener
        AudioObjectAddPropertyListenerBlock(device, &Self.runningAddress, DispatchQueue.main, listener)
    }

    // check records the start and fires onStart on an idle-to-in-use transition, and clears the start
    // when the microphone goes idle.
    private func check() {
        let running = isRunning
        defer { wasRunning = running }
        if !running {
            startedAt = nil
        } else if !wasRunning {
            startedAt = Date()
            onStart?()
        }
    }
}
