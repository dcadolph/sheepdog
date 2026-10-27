import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

import SheepdogCore

// SoundPlayer plays chimes and the looping alarm on the devices the settings choose.
@MainActor
final class SoundPlayer {
    // engines are the running playback engines, one per output device.
    private var engines: [AVAudioEngine] = []
    // snapshots hold volumes to restore when the alarm stops.
    private var snapshots: [AudioDevices.VolumeSnapshot] = []
    // isAlarming reports whether the alarm loop is playing.
    private(set) var isAlarming = false

    // soundsDirectory is where macOS keeps its built-in alert sounds.
    static let soundsDirectory = URL(fileURLWithPath: "/System/Library/Sounds")

    // availableSounds lists the built-in alert sound names.
    static func availableSounds() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: soundsDirectory.path)) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }

    // startAlarm loops the holiday tune when one is given, else the alarm sound, until stopAlarm, boosting
    // volume when the settings ask for it.
    func startAlarm(settings: AlertSettings, melody: BarkMelody? = nil) {
        guard !isAlarming else {
            return
        }
        isAlarming = true
        let devices = targetDevices(settings.alarmOutput)
        if settings.boostVolume {
            snapshots = devices.map { AudioDevices.boost($0, to: Float32(settings.boostLevel)) }
        }
        for device in devices {
            let file = melody.flatMap(melodyFile) ?? soundFile(named: settings.alarmSound)
            if let engine = play(file: file, on: device, loop: true) {
                engines.append(engine)
            }
        }
    }

    // stopAlarm stops the loop and restores any boosted volume.
    func stopAlarm() {
        guard isAlarming else {
            return
        }
        isAlarming = false
        engines.forEach { $0.stop() }
        engines.removeAll()
        snapshots.forEach(AudioDevices.restore)
        snapshots.removeAll()
    }

    // chime plays the warning sound once on the chosen devices.
    func chime(settings: AlertSettings) {
        preview(sound: settings.chimeSound, settings: settings)
    }

    // preview plays any Tug or system sound once on the chosen devices, without a volume boost.
    func preview(sound: String, settings: AlertSettings) {
        for device in targetDevices(settings.alarmOutput) {
            guard let engine = play(sound: sound, on: device, loop: false) else {
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                engine.stop()
            }
        }
    }

    // previewMelody plays a holiday tune once to its end on the chosen devices, without a volume boost.
    func previewMelody(_ melody: BarkMelody, settings: AlertSettings) {
        for device in targetDevices(settings.alarmOutput) {
            guard let file = melodyFile(melody),
                  let engine = play(file: file, on: device, loop: false)
            else {
                continue
            }
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
                engine.stop()
            }
        }
    }

    // targetDevices resolves the output setting into distinct device ids.
    private func targetDevices(_ output: AlarmOutput) -> [AudioDeviceID] {
        let current = AudioDevices.defaultOutput()
        let builtIn = AudioDevices.builtInOutput()
        let picked: [AudioDeviceID?]
        switch output {
        case .systemDefault:
            picked = [current]
        case .builtInSpeakers:
            picked = [builtIn ?? current]
        case .both:
            picked = [current, builtIn]
        }
        var seen = Set<AudioDeviceID>()
        return picked.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    // play starts a sound by name on one device and returns the engine that owns it.
    private func play(sound: String, on device: AudioDeviceID, loop: Bool) -> AVAudioEngine? {
        play(file: soundFile(named: sound), on: device, loop: loop)
    }

    // play starts an opened sound file on one device and returns the engine that owns it.
    private func play(file: AVAudioFile?, on device: AudioDeviceID, loop: Bool) -> AVAudioEngine? {
        guard let file else {
            return nil
        }
        let engine = AVAudioEngine()
        guard let unit = engine.outputNode.audioUnit else {
            return nil
        }
        var target = device
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &target,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            return nil
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil
        else {
            return nil
        }
        do {
            try engine.start()
        } catch {
            return nil
        }
        player.scheduleBuffer(buffer, at: nil, options: loop ? .loops : [])
        player.play()
        return engine
    }

    // melodyFile opens a bundled holiday tune.
    private func melodyFile(_ melody: BarkMelody) -> AVAudioFile? {
        guard let url = Bundle.main.url(forResource: melody.resource, withExtension: "caf") else {
            return nil
        }
        return try? AVAudioFile(forReading: url)
    }

    // soundFile opens a bundled Tug sound or a built-in sound by name, falling back to Sosumi.
    private func soundFile(named name: String) -> AVAudioFile? {
        if let tug = TugSound(rawValue: name),
           let url = Bundle.main.url(forResource: tug.resource, withExtension: "caf"),
           let file = try? AVAudioFile(forReading: url) {
            return file
        }
        for candidate in [name, "Sosumi"] {
            for ext in ["aiff", "aif", "caf", "wav"] {
                let url = Self.soundsDirectory.appendingPathComponent("\(candidate).\(ext)")
                if let file = try? AVAudioFile(forReading: url) {
                    return file
                }
            }
        }
        return nil
    }
}
