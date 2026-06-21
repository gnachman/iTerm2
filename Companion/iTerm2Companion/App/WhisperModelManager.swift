//
//  WhisperModelManager.swift
//  iTerm2 Companion
//
//  Owns the on-device speech-to-text model: which variant is selected, whether
//  it has been downloaded, and the loaded WhisperKit instance that
//  VoiceCaptureController transcribes with. Models are fetched from Hugging
//  Face at runtime (never bundled in the app) and cached on disk, so the first
//  use pays a download and later launches load from the cache. The default is
//  small.en, and large-v3 / turbo models are excluded entirely: on iOS 26 they
//  are not viable (the ANE compile is broken and the GPU runs out of memory), so
//  only the memory-safe small/base/tiny class is offered. The user can pick
//  among those in Settings.
//

import CoreML
import Foundation
import Observation
import WhisperKit

@MainActor
@Observable
final class WhisperModelManager {
    /// Lifecycle of the selected model. `.preparing` covers both the load and
    /// the first-run ANE compile, which can take a while and must not look hung.
    enum Status: Equatable {
        case idle
        case downloading(Double)   // 0...1 fraction
        case preparing             // loading + first-run ANE compile
        case ready
        case failed(String)
    }

    // Local-only prefs: NoSync prefix per project convention (not real config
    // that should follow a user's synced settings).
    private static let enabledKey = "NoSyncWhisperEnabled"
    private static let modelKey = "NoSyncWhisperModel"
    private static let folderKey = "NoSyncWhisperModelFolder"

    private(set) var status: Status = .idle
    /// Device-appropriate variants offered in the Settings picker.
    private(set) var availableModels: [String]

    // Stored (not computed) so @Observable tracks them and the UI reacts;
    // didSet mirrors the value to UserDefaults. NoSync prefix per convention.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                // Leave the cached weights on disk; just drop the loaded
                // instance so we stop holding model memory.
                whisperKit = nil
                status = .idle
            }
        }
    }

    /// The selected variant, defaulting to WhisperKit's recommendation for this
    /// device. Changing it drops the loaded model so the next prepare() reloads.
    var selectedModelName: String {
        didSet {
            guard selectedModelName != oldValue else { return }
            UserDefaults.standard.set(selectedModelName, forKey: Self.modelKey)
            // The cached-folder record is per model (see folderDefaultsKey), so
            // switching models does not forget another model's download.
            whisperKit = nil
            status = .idle
        }
    }

    /// The loaded model, if ready. VoiceCaptureController transcribes with this.
    private(set) var whisperKit: WhisperKit?

    init() {
        // The synchronous recommendation is offline and (on the Simulator, where
        // hardware can't be detected) conservative. It is only the immediate
        // fallback; refreshRecommendation() upgrades it once Settings appears.
        let support = WhisperKit.recommendedModels()
        let preferred = Self.preferredDefault(support)
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? false

        let stored = UserDefaults.standard.string(forKey: Self.modelKey)
        let chosen: String
        if let stored, Self.isUsableModel(stored) {
            // Keep any saved pick that can run on this device, even if the offline
            // list omits it.
            chosen = stored
        } else {
            // No saved pick, or one we no longer offer (e.g. a large model that
            // crashes on this OS). Fall back to the safe default and discard the
            // stale pick so we never try to load an unusable model.
            chosen = preferred
            UserDefaults.standard.set(preferred, forKey: Self.modelKey)
        }
        selectedModelName = chosen
        availableModels = Self.curatedModels(support, ensuring: chosen)
    }

    /// The list for the picker: only models that actually run on this OS, with
    /// `preferred` guaranteed present. large-v3 / turbo are hidden because they
    /// are not viable on iOS 26 (ANE compile broken, GPU execution runs out of
    /// memory and is jetsammed); offering them only invites a crash.
    private static func curatedModels(_ support: ModelSupport, ensuring preferred: String) -> [String] {
        var models = support.supported.filter { isUsableModel($0) }
        if !models.contains(preferred) {
            models.insert(preferred, at: 0)
        }
        return models
    }

    /// Whether a model can actually run on this OS. large-v3 / turbo cannot on
    /// iOS 26 (ANE compile broken, GPU out of memory), so they are hidden and a
    /// stored pick of one self-heals to the default.
    private static func isUsableModel(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return !lowered.contains("large") && !lowered.contains("turbo")
    }

    /// Our default model: small.en. It is the sweet spot on iOS 26 - accurate,
    /// fast enough to keep up on the CPU, and small enough to load quickly and
    /// fit in memory. (large-v3 / turbo are not viable here: the ANE compile is
    /// broken and the GPU runs out of memory; see the compute options in
    /// prepare().) Prefer the device's exact spelling of small.en, then fall back
    /// through other memory-safe models, and finally the literal name so it is
    /// always offered even if the support list omits it.
    private static let defaultModelName = "openai_whisper-small.en"
    private static func preferredDefault(_ support: ModelSupport) -> String {
        // Force small.en even if the device's recommended list omits it (it still
        // downloads and runs fine), preferring the list's exact spelling if present.
        support.supported.first { $0.lowercased().contains("small.en") } ?? defaultModelName
    }

    /// The user's pick from the Settings picker.
    func selectModel(_ name: String) {
        selectedModelName = name
    }

    /// Turn on dictation and select the default model. Used by the mic button's
    /// first-run prompt when the user agrees to set dictation up.
    func enableWithDefaultModel() {
        isEnabled = true
        selectModel(Self.defaultModelName)
    }

    /// Fetch WhisperKit's current per-device support list and adopt the best
    /// quality model it allows, unless the user already chose one. Falls back
    /// silently to the offline list when there is no network. Call when Settings
    /// appears.
    func refreshRecommendation() async {
        let support = await WhisperKit.recommendedRemoteModels()
        // Only replace the current selection when it genuinely cannot run on this
        // device. A usable pick is kept as-is - we never reassign it just because
        // the remote list spells it differently or the user never made an explicit
        // choice, which would needlessly unload a ready model and forget its cache.
        if Self.isUsableModel(selectedModelName) {
            availableModels = Self.curatedModels(support, ensuring: selectedModelName)
        } else {
            let preferred = Self.preferredDefault(support)
            availableModels = Self.curatedModels(support, ensuring: preferred)
            selectedModelName = preferred
        }
    }

    /// Per-model defaults key for the cached folder, so each variant remembers its
    /// own download. A single global key would forget model A's cache the moment
    /// the user switched the picker to B, forcing a re-download of A.
    private func folderDefaultsKey(for model: String) -> String {
        "\(Self.folderKey).\(model)"
    }

    /// The cached folder for the selected model, if its files are still present.
    /// Resolved against the current container root so it survives the container
    /// UUID changing across reinstalls/updates (we never persist an absolute path).
    private var cachedModelFolder: URL? {
        guard let stored = UserDefaults.standard.string(forKey: folderDefaultsKey(for: selectedModelName)) else {
            return nil
        }
        // New format: a path relative to the container root. Legacy builds stored
        // an absolute path; try that as a fallback so it self-heals on next save.
        let candidates = [NSHomeDirectory() + stored, stored]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Persist a model's folder relative to the container root, dropping the
    /// install-specific UUID prefix so the path stays valid across reinstalls.
    /// Takes the model explicitly because the selection may have changed while the
    /// download was in flight.
    private func rememberModelFolder(_ url: URL, for model: String) {
        let home = NSHomeDirectory()
        let path = url.path
        let relative = path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path
        UserDefaults.standard.set(relative, forKey: folderDefaultsKey(for: model))
    }

    /// True if the selected variant's weights are already on disk, so enabling
    /// voice input will not trigger a fresh download.
    var isDownloaded: Bool {
        cachedModelFolder != nil
    }

    /// Load and prewarm the selected model, downloading first only if it is not
    /// already cached. Idempotent: returns immediately when already ready. Safe
    /// to call from a mic tap or the Settings download button.
    func prepare() async {
        if case .ready = status, whisperKit != nil { return }
        if case .downloading = status { return }
        if case .preparing = status { return }

        let model = selectedModelName
        do {
            let folder: URL
            if let cached = cachedModelFolder {
                // Already on disk: skip the network entirely (works offline).
                folder = cached
            } else {
                status = .downloading(0)
                companionLog("Whisper: downloading model \(model)")
                folder = try await WhisperKit.download(variant: model) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.selectedModelName == model else { return }
                        self.status = .downloading(progress.fractionCompleted)
                    }
                }
                rememberModelFolder(folder, for: model)
            }

            // The user may have switched models during the download; abandon this
            // load so a different model is never marked ready than the one selected.
            guard model == selectedModelName else { return }
            status = .preparing
            companionLog("Whisper: loading \(model)")
            let started = Date()
            // Run entirely on the CPU. On iOS 26 the other two backends are both
            // unusable for us: the Neural Engine's on-device AOT compiler
            // force-respecializes on every launch (the ANECompilerService ->
            // Espresso compile stall, seconds for the encoder and over a minute
            // for a large decoder), and the GPU is too slow for real-time
            // streaming on these models. The CPU has no AOT-compile stall and,
            // for the small models we offer, keeps up. Transcription quality is
            // identical across backends. Revisit ANE once the OS respecialization
            // bug is fixed.
            let compute = ModelComputeOptions(melCompute: .cpuOnly,
                                              audioEncoderCompute: .cpuOnly,
                                              textDecoderCompute: .cpuOnly)
            let kit = try await WhisperKit(model: model,
                                           modelFolder: folder.path,
                                           computeOptions: compute,
                                           verbose: false,
                                           logLevel: .error,
                                           prewarm: true,
                                           load: true,
                                           download: false)
            let elapsed = Date().timeIntervalSince(started)
            // Switched away during the load: discard this kit rather than mark the
            // wrong model ready (which would transcribe with a mismatched model).
            guard model == selectedModelName else { return }
            whisperKit = kit
            status = .ready
            companionLog("Whisper: \(model) ready in \(String(format: "%.1f", elapsed))s")
        } catch {
            guard model == selectedModelName else { return }
            whisperKit = nil
            status = .failed(String(describing: error))
            companionLog("Whisper: prepare failed: \(String(describing: error))")
        }
    }

    /// Remove the cached weights for the selected variant and reset to idle, so
    /// the user can reclaim the disk space (the Settings "remove model" action).
    func deleteModel() {
        whisperKit = nil
        status = .idle
        if let folder = cachedModelFolder {
            try? FileManager.default.removeItem(at: folder)
        }
        UserDefaults.standard.removeObject(forKey: folderDefaultsKey(for: selectedModelName))
        companionLog("Whisper: deleted cached model")
    }
}
