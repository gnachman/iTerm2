//
//  VoiceCaptureController.swift
//  iTerm2 Companion
//
//  Live, on-device dictation for the chat composer. Captures the microphone
//  through WhisperKit's AudioProcessor and, while the user speaks, re-transcribes
//  the whole recording so far and publishes the running text. This whole-buffer
//  approach is deliberately simple and robust: every pass yields the complete
//  transcript, so nothing is ever lost. Voice-activity detection skips silent
//  windows so Whisper does not hallucinate subtitle junk ("[heartbeat]",
//  "The End") on pauses, and a flush pass after speech captures the final words.
//
//  We keep our own copy of the captured samples and energy (fed by the audio-tap
//  callback on the audio thread, guarded by a lock) rather than reading
//  WhisperKit's AudioProcessor.audioSamples / relativeEnergy, which are unguarded
//  arrays mutated on the audio thread - reading them from the main actor is a
//  data race. Transcription passes are serialized through a single Task so two
//  transcribe() calls never run concurrently on one WhisperKit instance.
//

import AVFoundation
import Foundation
import Observation
import WhisperKit

@MainActor
@Observable
final class VoiceCaptureController {
    enum State: Equatable {
        case idle
        case listening
        case transcribing   // finalizing after the user stopped
    }

    private(set) var state: State = .idle
    /// The running transcript. The view mirrors this into the composer.
    private(set) var liveText: String = ""
    /// 0...1 microphone level, for the button animation and VU meter.
    private(set) var audioLevel: Float = 0

    private let modelManager: WhisperModelManager
    private var audioProcessor: AudioProcessor?
    private var language = "en"

    private static let sampleRate = 16_000
    private static let delayIntervalSeconds = 1.0   // new audio before a routine pass

    // Captured audio and energy live in a lock-guarded box so the audio thread
    // (which appends) and the main actor (which reads) never race. It is a `let`
    // of a Sendable type, so the audio-thread callback can reach it directly.
    private let captureBuffer = AudioCaptureBuffer()

    private var lastConsumedCount = 0
    // True once voiced audio has arrived that a pass has not yet covered, so a
    // following silence flushes the phrase tail instead of discarding it.
    private var pendingSpeech = false
    // True once any voice was detected this session. If the user records without
    // speaking, we skip the final pass so Whisper does not emit "[BLANK_AUDIO]".
    private var sawSpeech = false
    // The single in-flight routine pass, and the single in-flight finalize, so
    // passes never overlap and a second stop()/send() coalesces onto the first.
    private var passTask: Task<Void, Never>?
    private var finalizeTask: Task<String, Never>?
    private var interruptionObserver: NSObjectProtocol?

    init(modelManager: WhisperModelManager) {
        self.modelManager = modelManager
    }

    /// Begin recording and live transcription.
    func start() async throws {
        guard state == .idle else { return }
        await modelManager.prepare()
        guard modelManager.whisperKit != nil else {
            throw VoiceCaptureError.modelNotReady
        }
        guard await AudioProcessor.requestRecordPermission() else {
            throw VoiceCaptureError.microphonePermissionDenied
        }
        // From here on the audio session is active and/or a processor exists, so
        // any failure must release them before rethrowing - otherwise the session
        // stays active (other apps stay ducked) and a retry stacks a second
        // processor on the live session.
        do {
            try configureSession()
            language = Self.resolveLanguage(modelName: modelManager.selectedModelName)
            resetState()

            let processor = AudioProcessor()
            audioProcessor = processor
            try processor.startRecordingLive { [weak self] delta in
                // Audio thread: accumulate and analyze under the lock, then hand
                // primitives to the main actor.
                self?.ingest(delta)
            }
        } catch {
            audioProcessor?.stopRecording()
            teardown()
            throw error
        }
        state = .listening
        observeInterruptions()
    }

    /// Stop recording, run one final pass so trailing audio is captured, and
    /// return the final transcript. Coalesces: a concurrent call (e.g. send while
    /// the mic-stop is finalizing) awaits the same finalize instead of starting a
    /// second one or no-oping.
    func stop() async -> String {
        if let finalizeTask {
            return await finalizeTask.value
        }
        guard state == .listening else { return liveText }
        let task = Task { @MainActor () -> String in
            state = .transcribing
            audioProcessor?.stopRecording()
            stopObservingInterruptions()
            await passTask?.value      // let any in-flight routine pass finish
            // If cancel() ran while we were suspended (e.g. the user left the
            // chat mid-finalize), bail without finalizing or returning a
            // transcript the caller would commit/send for an abandoned message.
            if Task.isCancelled { teardown(); return "" }
            if sawSpeech {
                await performPass()    // final pass on the full buffer
            }
            if Task.isCancelled { teardown(); return "" }
            let result = liveText
            teardown()
            return result
        }
        finalizeTask = task
        let result = await task.value
        finalizeTask = nil
        return result
    }

    /// Abandon recording without using the transcript (e.g. an interruption).
    func cancel() {
        audioProcessor?.stopRecording()
        stopObservingInterruptions()
        passTask?.cancel(); passTask = nil
        finalizeTask?.cancel(); finalizeTask = nil
        teardown()
        liveText = ""
    }

    // MARK: - Capture (audio thread)

    /// Accumulate the new buffer and compute its relative energy / voice activity
    /// (in the lock-guarded box), then hand the results to the main actor. Runs on
    /// the audio thread.
    private nonisolated func ingest(_ delta: [Float]) {
        let result = captureBuffer.append(delta)
        Task { @MainActor [weak self] in
            self?.bufferDidArrive(totalCount: result.totalCount,
                                  level: result.level,
                                  voiceDetected: result.voiceDetected)
        }
    }

    // MARK: - Trigger (main actor)

    private func bufferDidArrive(totalCount: Int, level: Float, voiceDetected: Bool) {
        guard state == .listening else { return }
        audioLevel = min(1, max(0, level))
        if voiceDetected {
            pendingSpeech = true
            sawSpeech = true
        }

        guard passTask == nil else { return } // a pass is in flight; it will catch up

        let newSeconds = Double(totalCount - lastConsumedCount) / Double(Self.sampleRate)
        if voiceDetected {
            if newSeconds > Self.delayIntervalSeconds {
                triggerPass()
            }
        } else if pendingSpeech {
            triggerPass() // flush the phrase tail after speech
        } else {
            lastConsumedCount = totalCount // sustained silence: nothing pending
        }
    }

    /// Schedule one routine pass. Single-flight: the synchronous passTask check
    /// on the main actor means a second buffer callback cannot start a second
    /// pass before this one is recorded.
    private func triggerPass() {
        guard passTask == nil else { return }
        passTask = Task { @MainActor in
            await performPass()
            passTask = nil
        }
    }

    /// Transcribe the entire recording so far and publish the full text.
    private func performPass() async {
        guard let kit = modelManager.whisperKit else { return }
        let samples = captureBuffer.snapshot()
        guard !samples.isEmpty else { return }
        lastConsumedCount = samples.count
        pendingSpeech = false

        let options = DecodingOptions(task: .transcribe,
                                      language: language,
                                      skipSpecialTokens: true,
                                      withoutTimestamps: true)
        do {
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            // Abandoned while transcribing (cancel() cancels this task): don't
            // overwrite liveText, which cancel() blanked.
            if Task.isCancelled { return }
            let text = Self.sanitized(results.map { $0.text }.joined(separator: " "))
            if !text.isEmpty { // keep prior text rather than blanking on an empty window
                liveText = text
            }
        } catch {
            companionLog("Whisper: transcription failed: \(String(describing: error))")
        }
    }

    // MARK: - Level

    /// The current input level (0...1), read by the VU meter.
    func currentInputLevel() -> Float {
        state == .listening ? audioLevel : 0
    }

    // MARK: - Session

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: type) == .began else { return }
            Task { @MainActor in self?.cancel() }
        }
    }

    private func stopObservingInterruptions() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
    }

    private func resetState() {
        captureBuffer.reset()
        liveText = ""
        audioLevel = 0
        lastConsumedCount = 0
        pendingSpeech = false
        sawSpeech = false
    }

    /// Trim, and drop whole-result non-speech annotations Whisper emits for
    /// silence ("[BLANK_AUDIO]", "[ Silence ]", "(buzzing)"). Only a result that
    /// is entirely one bracketed/parenthesized annotation is dropped, so real
    /// dictation containing parentheses is left intact.
    private static func sanitized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"^[\[(][^\])]*[\])]$"#, options: .regularExpression),
           range == trimmed.startIndex..<trimmed.endIndex {
            return ""
        }
        return trimmed
    }

    private func teardown() {
        audioProcessor = nil
        audioLevel = 0
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Pin the decode language so multilingual models skip per-window language
    /// detection (a real latency cost) and never guess wrong. English-only (.en)
    /// models are always English; otherwise use the device language, defaulting
    /// to English.
    private static func resolveLanguage(modelName: String) -> String {
        if modelName.lowercased().hasSuffix(".en") { return "en" }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }
}

enum VoiceCaptureError: Error {
    case modelNotReady
    case microphonePermissionDenied
}

/// Lock-guarded store for the captured audio and its per-buffer energy. The
/// audio-tap thread appends; the main actor snapshots for transcription. All
/// access is serialized by the lock, so it is safely @unchecked Sendable.
private final class AudioCaptureBuffer: @unchecked Sendable {
    struct Ingested {
        let totalCount: Int
        let level: Float
        let voiceDetected: Bool
    }

    private let lock = NSLock()
    private var samples: [Float] = []
    private var energyAverages: [Float] = []
    private var relativeEnergies: [Float] = []

    private static let energyWindow = 20            // ~2s noise-floor reference
    private static let silenceThreshold: Float = 0.3
    private static let voiceWindowSeconds: Float = 0.4

    /// Append a new buffer and return the running count plus its relative level
    /// and whether voice is present. Energy is computed relative to the quietest
    /// of the recent buffers (the noise floor), as WhisperKit does, so speech
    /// reads near 1 and silence near 0.
    func append(_ delta: [Float]) -> Ingested {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: delta)
        let reference = energyAverages.suffix(Self.energyWindow).min()
        let relative = AudioProcessor.calculateRelativeEnergy(of: delta, relativeTo: reference)
        energyAverages.append(AudioProcessor.calculateAverageEnergy(of: delta))
        relativeEnergies.append(relative)
        let voiceDetected = AudioProcessor.isVoiceDetected(
            in: relativeEnergies,
            nextBufferInSeconds: Self.voiceWindowSeconds,
            silenceThreshold: Self.silenceThreshold)
        return Ingested(totalCount: samples.count, level: relative, voiceDetected: voiceDetected)
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll()
        energyAverages.removeAll()
        relativeEnergies.removeAll()
    }
}
