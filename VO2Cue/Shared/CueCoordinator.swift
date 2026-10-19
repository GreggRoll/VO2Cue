import AVFoundation
import Foundation
#if os(watchOS)
import WatchKit
#endif

@MainActor
final class CueCoordinator {
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isAudioReady = false
    private var lastIntervalCue = Date.distantPast

    func handle(_ event: WorkoutRuntimeEvent, profile: WorkoutProfile) {
        lastIntervalCue = Date()
        speechSynthesizer.stopSpeaking(at: .immediate)
        switch event {
        case .countdown(let value):
            playHaptic(.countdown, enabled: profile.cues.hapticsEnabled)
            playTone(frequency: 660, duration: 0.09, enabled: profile.cues.tonesEnabled)
            speak(String(value), enabled: profile.cues.voiceEnabled)
        case .phaseChanged(let phase):
            playHaptic(phase.kind == .work ? .work : .transition, enabled: profile.cues.hapticsEnabled)
            playTone(
                frequency: phase.kind == .work ? 1_000 : 440,
                duration: phase.kind == .work ? 0.24 : 0.17,
                enabled: profile.cues.tonesEnabled
            )
            speak(phase.displayTitle, enabled: profile.cues.voiceEnabled)
        case .halfway:
            playHaptic(.halfway, enabled: profile.cues.hapticsEnabled)
            playTone(frequency: 780, duration: 0.12, enabled: profile.cues.tonesEnabled)
            speak("Halfway", enabled: profile.cues.voiceEnabled)
        case .finished:
            playHaptic(.finish, enabled: profile.cues.hapticsEnabled)
            playTone(frequency: 880, duration: 0.4, enabled: profile.cues.tonesEnabled)
            speak("Workout complete", enabled: profile.cues.voiceEnabled)
        }
    }

    func handleHalfwayHeartRate(_ cue: HeartRateHalfwayCue, profile: WorkoutProfile) {
        lastIntervalCue = Date()
        speechSynthesizer.stopSpeaking(at: .immediate)
        playHaptic(.halfway, enabled: profile.cues.hapticsEnabled)
        playTone(frequency: 780, duration: 0.12, enabled: profile.cues.tonesEnabled)
        speak(cue.rawValue, enabled: profile.cues.voiceEnabled)
    }

    func handleHeartRate(_ status: HeartRateStatus, profile: WorkoutProfile) {
        guard profile.heartRateGuidance?.cuesEnabled == true,
              Date().timeIntervalSince(lastIntervalCue) > 5,
              status == .above || status == .below else { return }
        #if os(watchOS)
        if profile.cues.hapticsEnabled {
            WKInterfaceDevice.current().play(status == .above ? .directionDown : .directionUp)
        }
        #endif
        speak(status == .above ? HeartRateHalfwayCue.down.rawValue : HeartRateHalfwayCue.up.rawValue, enabled: profile.cues.voiceEnabled)
    }

    private func speak(_ phrase: String, enabled: Bool) {
        guard enabled else { return }
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = 0.48
        speechSynthesizer.speak(utterance)
    }

    private func prepareAudioIfNeeded() throws {
        guard !isAudioReady else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        #endif
        audioEngine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        try audioEngine.start()
        isAudioReady = true
    }

    private func playTone(frequency: Double, duration: Double, enabled: Bool) {
        guard enabled else { return }
        do {
            try prepareAudioIfNeeded()
            let sampleRate = 44_100.0
            let frameCount = AVAudioFrameCount(sampleRate * duration)
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let samples = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = frameCount
            for frame in 0..<Int(frameCount) {
                let progress = Double(frame) / Double(frameCount)
                let envelope = Float(min(progress * 12, (1 - progress) * 12, 1))
                samples[frame] = sin(Float(frame) * 2 * .pi * Float(frequency / sampleRate)) * 0.25 * envelope
            }
            playerNode.scheduleBuffer(buffer)
            if !playerNode.isPlaying { playerNode.play() }
        } catch {
            // Audio cues are optional; the workout continues when audio is unavailable.
        }
    }

    private enum HapticKind {
        case countdown, work, transition, halfway, finish
    }

    private func playHaptic(_ kind: HapticKind, enabled: Bool) {
        guard enabled else { return }
        #if os(watchOS)
        let type: WKHapticType = switch kind {
        case .countdown: .click
        case .work: .start
        case .transition: .directionDown
        case .halfway: .notification
        case .finish: .success
        }
        WKInterfaceDevice.current().play(type)
        #endif
    }
}
