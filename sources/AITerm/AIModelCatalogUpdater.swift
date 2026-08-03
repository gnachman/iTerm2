//
//  AIModelCatalogUpdater.swift
//  iTerm2
//
//  Periodically refreshes the AI model catalog (see AIModelCatalog) by
//  downloading a newer signed copy, so new models reach users without an app
//  update.
//
//  Pipeline (silent, no UI):
//    1. Download the manifest JSON (an array of candidate catalog versions)
//       from iTermAdvancedSettingsModel.aiModelCatalogURL.
//    2. Pick the highest `version` entry whose integer AI-compatibility range
//       admits this build (see AIModelCatalog.appCatalogCompatibilityVersion).
//    3. If it's newer than the loaded catalog, download its payload.
//    4. Verify the payload's RSA signature against the bundled rsa_pub.pem
//       (same key pair as the Python runtime), using iTermSignatureVerifier.
//    5. Sanity-check that it decodes to at least one usable model, then
//       atomically replace the cached catalog.
//
//  The refreshed catalog takes effect on the next launch (AIModelCatalog reads
//  the higher-versioned of {cached, bundled} at startup). On any failure the
//  previous cached/bundled catalog is left untouched.

import Foundation

@objc(iTermAIModelCatalogUpdater)
class AIModelCatalogUpdater: NSObject {
    @objc static let instance = AIModelCatalogUpdater()

    private let rateLimit: iTermPersistentRateLimitedUpdate
    // performPeriodicCheck runs on the main thread, but URLSession completion
    // handlers run on a background queue, so `checking` and `installedVersion`
    // are touched from two threads. Guard both with this lock to avoid a data
    // race. Contention is effectively nil (the daily rate limit means one check
    // per launch), so per-access locking is cheap.
    private let stateLock = NSLock()
    private var _checking = false
    // Highest catalog version we know about this session: what loaded at launch,
    // bumped after each successful install so we don't re-download it.
    private var _installedVersion: Int

    private var checking: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _checking }
        set { stateLock.lock(); defer { stateLock.unlock() }; _checking = newValue }
    }

    private var installedVersion: Int {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _installedVersion }
        set { stateLock.lock(); defer { stateLock.unlock() }; _installedVersion = newValue }
    }

    // True while the consent modal is on screen. Main-thread only (both the modal
    // and every performPeriodicCheck entry point run on main), so it needs no
    // lock. Guards against stacking a second identical modal: iTermWarning.show
    // spins a modal run loop that can drain the main dispatch queue, so a queued
    // performPeriodicCheck (e.g. from an enableAI write during onboarding) can
    // re-enter while consent is still .unknown.
    private var askingConsent = false

    override init() {
        rateLimit = iTermPersistentRateLimitedUpdate(name: "CheckForUpdatedAIModelCatalog",
                                                     minimumInterval: 24 * 60 * 60)
        _installedVersion = AIModelCatalog.instance.version
        super.init()

        // React the moment AI is turned on, so a freshly-enabled user doesn't
        // wait until the next launch for the first update check (and consent
        // prompt) - that could be a long time. enableAI is the last gate in the
        // setup flow (its checkbox stays disabled until the plugin is
        // installed), and every enable path writes it as a secure default, so
        // its change notification is a reliable, central trigger. The
        // notification's object is the changed key; we filter to enableAI in the
        // handler.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(secureUserDefaultDidChange(_:)),
                                               name: iTermSecureUserDefaults.didChange,
                                               object: nil)
    }

    @objc private func secureUserDefaultDidChange(_ notification: Notification) {
        // Only the AI toggle is interesting; ignore other secure-default writes
        // so, e.g., a companion-pairing change doesn't kick off an AI check.
        // Compare by value: NotificationCenter's object-identity filtering is
        // unreliable for Swift strings bridged to Any.
        guard notification.object as? String == SecureUserDefaults.instance.enableAI.key else {
            return
        }
        // Unwind the current secure-default write before running the gated check
        // (which may present the consent modal), and guarantee we're on main.
        // performPeriodicCheck is self-gating, rate-limited, and remembers
        // consent, so running it here in addition to at launch is idempotent.
        DispatchQueue.main.async { [weak self] in
            self?.performPeriodicCheck()
        }
    }

    // Rate-limited entry point suitable for calling at every launch. Must run on
    // the main thread: it may present the one-time consent prompt.
    @objc func performPeriodicCheck() {
        // Gate 1: never contact the network for AI model updates unless AI is
        // fully enabled: allowed in advanced settings AND enabled in the secure
        // setting (iTermAITermGatekeeper.allowed covers both) AND the plugin is
        // installed. If AI isn't set up we must not download, and must not even
        // ask for consent.
        guard iTermAITermGatekeeper.allowed, iTermAITermGatekeeper.pluginInstalled() else {
            RLog("AI is not fully enabled; skipping AI model catalog update check")
            return
        }
        // Gate 2: a cleared or invalid URL disables checking entirely (as the
        // advanced-setting help promises). Check it BEFORE the consent gate so
        // opting out this way also suppresses the one-time consent prompt rather
        // than asking the user to permit a download that can never happen (and
        // then burning the rate-limit window on a no-op).
        let urlString = iTermAdvancedSettingsModel.aiModelCatalogURL() ?? ""
        guard !urlString.isEmpty, let manifestURL = URL(string: urlString) else {
            RLog("AI model catalog update disabled or URL invalid: \(urlString)")
            return
        }
        // Gate 3: downloading a refreshed catalog contacts the network, which is
        // a change to the privacy model, so it requires explicit one-time consent
        // before the first download.
        switch iTermUserDefaults.aiModelCatalogUpdateConsent {
        case .granted:
            break
        case .denied:
            RLog("User declined AI model catalog updates; skipping")
            return
        case .unknown:
            fallthrough
        @unknown default:
            // Don't stack a second consent modal if one is already up.
            guard !askingConsent else {
                return
            }
            guard requestConsent() else {
                return
            }
        }
        rateLimit.performRateLimitedBlock { [weak self] in
            self?.checkForUpdate(manifestURL: manifestURL)
        }
    }

    // Presents the one-time modal asking permission to fetch AI model updates,
    // records the answer, and returns whether consent was granted. Only an
    // explicit choice is remembered; a dismissal leaves consent unknown so we
    // ask again next launch rather than silently disabling updates forever.
    private func requestConsent() -> Bool {
        askingConsent = true
        defer { askingConsent = false }
        let selection = iTermWarning.show(
            withTitle: "iTerm2 can keep its built-in list of AI models current by periodically downloading a cryptographically signed list from iterm2.com. No terminal content or personal data is sent. Allow this?",
            actions: ["Allow", "Don’t Allow"],
            accessory: nil,
            identifier: nil,
            silenceable: .kiTermWarningTypePersistent,
            heading: "Check for AI Model Updates?",
            window: nil)
        switch selection {
        case .kiTermWarningSelection0:
            iTermUserDefaults.aiModelCatalogUpdateConsent = .granted
            RLog("AI model catalog update consent granted")
            return true
        case .kiTermWarningSelection1:
            iTermUserDefaults.aiModelCatalogUpdateConsent = .denied
            RLog("AI model catalog update consent denied")
            return false
        default:
            // Dismissed without choosing; leave consent unknown.
            return false
        }
    }

    private func checkForUpdate(manifestURL: URL) {
        guard !checking else {
            return
        }
        // Held for the WHOLE pipeline (manifest + payload download + install),
        // not just the manifest fetch, and released only via finishCheck() on
        // every terminal path. The manifest and payload run on separate URLSession
        // tasks, so clearing it in the manifest handler would leave the payload
        // window unserialized.
        checking = true
        RLog("Checking for AI model catalog update at \(manifestURL)")
        let task = URLSession.shared.dataTask(with: manifestURL) { [weak self] data, _, error in
            guard let self else {
                return
            }
            guard let data, error == nil else {
                RLog("AI catalog manifest download failed: \(error?.localizedDescription ?? "no data")")
                self.finishCheck()
                return
            }
            self.handleManifest(data)
        }
        task.resume()
    }

    // Releases the whole-pipeline lock. Every terminal path (success, failure,
    // nothing-to-do) routes here exactly once.
    private func finishCheck() {
        checking = false
    }

    private struct ManifestEntry: Decodable {
        var version: Int
        var url: String
        var signature: String
        // Compatibility is expressed as an integer range against the app's
        // monotonic AIModelCatalog.appCatalogCompatibilityVersion, NOT the
        // human-facing app version string (which doesn't order sanely across
        // nightly/beta/adhoc builds). Both bounds are optional and inclusive.
        var minimum_ai_version: Int?
        var maximum_ai_version: Int?
    }

    private func handleManifest(_ data: Data) {
        guard let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data) else {
            RLog("AI catalog manifest did not parse")
            finishCheck()
            return
        }
        // Every compatible entry newer than what we have, highest version first.
        let candidates = entries
            .filter { Self.appAIVersionInRange(minimum: $0.minimum_ai_version, maximum: $0.maximum_ai_version) }
            .filter { $0.version > installedVersion }
            .sorted { $0.version > $1.version }
        guard !candidates.isEmpty else {
            RLog("No compatible AI catalog manifest entries newer than \(installedVersion)")
            finishCheck()
            return
        }
        tryCandidates(candidates, index: 0)
    }

    // Try candidates highest-version-first, falling through to the next on any
    // download/verify/validate failure, so one broken top entry (dead URL, botched
    // signing) doesn't stall updates while an older-but-still-newer good entry
    // exists in the same manifest.
    private func tryCandidates(_ candidates: [ManifestEntry], index: Int) {
        guard index < candidates.count else {
            RLog("All compatible AI catalog candidates failed; keeping current catalog")
            finishCheck()
            return
        }
        let entry = candidates[index]
        guard let payloadURL = URL(string: entry.url) else {
            RLog("AI catalog payload URL invalid: \(entry.url)")
            tryCandidates(candidates, index: index + 1)
            return
        }
        downloadPayload(payloadURL, signature: entry.signature, version: entry.version) { [weak self] installed in
            guard let self else {
                return
            }
            if installed {
                self.finishCheck()
            } else {
                self.tryCandidates(candidates, index: index + 1)
            }
        }
    }

    // Downloads and installs one candidate. completion(true) iff it verified,
    // validated, and was written to the cache.
    private func downloadPayload(_ url: URL,
                                 signature: String,
                                 version: Int,
                                 completion: @escaping (Bool) -> Void) {
        RLog("Downloading AI catalog payload version \(version) from \(url)")
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            guard let self else {
                completion(false)
                return
            }
            guard let tempURL, error == nil else {
                RLog("AI catalog payload download failed: \(error?.localizedDescription ?? "no file")")
                completion(false)
                return
            }
            completion(self.installVerifiedPayload(at: tempURL, signature: signature, version: version))
        }
        task.resume()
    }

    private func installVerifiedPayload(at tempURL: URL, signature: String, version: Int) -> Bool {
        guard let pubkeyURL = Bundle.main.url(forResource: "rsa_pub", withExtension: "pem"),
              let pubkey = try? String(contentsOf: pubkeyURL, encoding: .utf8) else {
            RLog("Missing rsa_pub.pem; cannot verify AI catalog")
            return false
        }
        if let verifyError = iTermSignatureVerifier.validateFileURL(tempURL,
                                                                    withEncodedSignature: signature,
                                                                    publicKey: pubkey) {
            // RLog so a field debug log captures tampering/misconfiguration.
            RLog("AI catalog signature verification failed: \(verifyError.localizedDescription)")
            return false
        }
        guard let data = try? Data(contentsOf: tempURL) else {
            RLog("Could not read downloaded AI catalog")
            return false
        }
        // Defense in depth: only replace the cache with something that actually
        // decodes to a usable catalog, satisfies the catalog invariants, and whose
        // version matches the manifest.
        let decodedVersion = AIModelCatalog.validate(data: data)
        guard decodedVersion == version else {
            RLog("Downloaded AI catalog failed validation (decoded version \(String(describing: decodedVersion)), expected \(version))")
            return false
        }
        guard let dest = AIModelCatalog.cachedCatalogURL else {
            RLog("No cache location for AI catalog")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: dest, options: .atomic)
            installedVersion = version
            RLog("Installed AI model catalog version \(version); takes effect on next launch")
            return true
        } catch {
            RLog("Failed to install AI catalog: \(error.localizedDescription)")
            return false
        }
    }

    // Whether a manifest entry's inclusive [minimum, maximum] compatibility range
    // admits this build, compared against the monotonic integer
    // AIModelCatalog.appCatalogCompatibilityVersion. Using an integer the app
    // bumps when its AI-catalog capabilities change (rather than parsing the
    // CFBundleShortVersionString) is nightly/beta/adhoc-proof: those builds carry
    // version strings that don't order numerically. This is defense in depth
    // anyway: even if the gate admits an entry, AIModelCatalog skips models whose
    // api/vendor the running app doesn't understand, so an incompatible catalog
    // can't break it.
    private static func appAIVersionInRange(minimum: Int?, maximum: Int?) -> Bool {
        let appVersion = AIModelCatalog.appCatalogCompatibilityVersion
        if let minimum, appVersion < minimum {
            return false
        }
        if let maximum, appVersion > maximum {
            return false
        }
        return true
    }
}
