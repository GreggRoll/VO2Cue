import AVFoundation
import Foundation

/// A scheduled guided-audio program. Its gaps are part of the program, so playback
/// does not rely on a suspended UI timer to enqueue the next cue.
@MainActor
final class WorkoutAudioProgram {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
    private var clips: [(time: TimeInterval, buffer: AVAudioPCMBuffer)] = []
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()
    private var isPlaybackActive = false
    var onInterruption: (() -> Void)?
    var onPlaybackFinished: (() -> Void)?

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: value) == .began else { return }
            Task { @MainActor in self?.handleInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: value) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.handleInterruption() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.engine.isRunning else { return }
                self.handleInterruption()
            }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func prepare(profile: WorkoutProfile, timeline: WorkoutTimeline) async throws {
        stop()
        clips = []
        guard profile.cues.voiceEnabled || profile.cues.tonesEnabled else { return }
        let schedule = WorkoutCueSchedule(profile: profile, timeline: timeline).cues
        var voices: [String: [Float]] = [:]
        if profile.cues.voiceEnabled {
            for phrase in Set(schedule.map(\.phrase)).sorted() {
                voices[phrase] = try await renderSpeech(phrase)
            }
        }
        for cue in schedule {
            let voice = voices[cue.phrase] ?? []
            let toneFrames = profile.cues.tonesEnabled ? Int(cue.toneDuration * format.sampleRate) : 0
            let count = max(1, toneFrames, voice.count)
            let buffer = makeBuffer(frames: count)
            let samples = buffer.floatChannelData![0]
            for frame in 0..<count {
                var sample: Float = frame < voice.count ? voice[frame] : 0
                if frame < toneFrames {
                    let progress = Double(frame) / Double(toneFrames)
                    let envelope = Float(min(progress * 12, (1 - progress) * 12, 1))
                    sample += sin(Float(Double(frame) * 2 * .pi * cue.frequency / format.sampleRate)) * 0.2 * envelope
                }
                samples[frame] = max(-1, min(1, sample))
            }
            clips.append((cue.time, buffer))
        }
    }

    func play(from elapsed: TimeInterval) throws {
        guard !clips.isEmpty else { return }
        generation = UUID()
        let token = generation
        player.stop()
        let session = AVAudioSession.sharedInstance()
        // Mix with the user's music without ducking it for the entire workout.
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        var cursor = elapsed
        let pending = clips.filter { $0.time >= elapsed - 0.05 }
        let silence = makeBuffer(frames: Int(format.sampleRate * 5))
        for (index, clip) in pending.enumerated() {
            var gap = max(0, Int(((clip.time - cursor) * format.sampleRate).rounded()))
            while gap > 0 {
                let count = min(gap, Int(silence.frameLength))
                player.scheduleBuffer(count == Int(silence.frameLength) ? silence : makeBuffer(frames: count))
                gap -= count
            }
            let nextTime = index + 1 < pending.count ? pending[index + 1].time : .infinity
            let count = min(Int(clip.buffer.frameLength), Int(min(Double(Int32.max), max(1, (nextTime - clip.time) * format.sampleRate))))
            let buffer: AVAudioPCMBuffer
            if count < Int(clip.buffer.frameLength) {
                buffer = makeBuffer(frames: count)
                buffer.floatChannelData![0].update(from: clip.buffer.floatChannelData![0], count: count)
            } else { buffer = clip.buffer }
            if index == pending.count - 1 {
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stop()
                        self.onPlaybackFinished?()
                    }
                }
            } else { player.scheduleBuffer(buffer) }
            cursor = clip.time + Double(count) / format.sampleRate
        }
        isPlaybackActive = true
        player.play()
    }

    func stop() {
        isPlaybackActive = false
        generation = UUID()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption() {
        guard isPlaybackActive else { return }
        onInterruption?()
    }

    private func makeBuffer(frames: Int) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        buffer.floatChannelData![0].initialize(repeating: 0, count: frames)
        return buffer
    }

    private func renderSpeech(_ phrase: String) async throws -> [Float] {
        let collector = SpeechSamples()
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = 0.48
        return try await withCheckedThrowingContinuation { continuation in
            collector.continuation = continuation
            synthesizer.write(utterance) { buffer in collector.append(buffer) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                if collector.timeOut() { self?.synthesizer.stopSpeaking(at: .immediate) }
            }
        }
    }
}

private final class SpeechSamples: @unchecked Sendable {
    private let lock = NSLock()
    var continuation: CheckedContinuation<[Float], Error>?
    private var samples: [Float] = []

    func append(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation, let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            self.continuation = nil
            if samples.isEmpty {
                continuation.resume(throwing: NSError(domain: "WorkoutAudio", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The selected voice is unavailable. Please try again or disable voice cues."]))
            } else {
                continuation.resume(returning: samples)
            }
            return
        }
        guard let source = pcm.floatChannelData?[0] else { return }
        let ratio = pcm.format.sampleRate / 22_050
        for index in 0..<Int(Double(pcm.frameLength) / ratio) {
            samples.append(source[min(Int(pcm.frameLength) - 1, Int(Double(index) * ratio))])
        }
    }

    func timeOut() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return false }
        self.continuation = nil
        continuation.resume(throwing: NSError(domain: "WorkoutAudio", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "Voice cues could not be prepared. Please try again."]))
        return true
    }
}
