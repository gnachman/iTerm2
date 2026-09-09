//
//  iTermUvProvisioner.swift
//  iTerm2SharedARC
//
//  Phase 1 of the uv Python-runtime migration. Downloads, verifies, extracts, and
//  installs the uv binary. The network fetch is behind an injectable protocol
//  (iTermUvTarballFetcher) so later phases and tests can provision without hitting
//  the network; the default fetcher reuses the optional-component download window
//  controller for progress UI. The manifest is fetched from iterm2.com and the
//  downloaded binary is verified with an RSA signature (iTermSignatureVerifier)
//  against the app's bundled public key. No path ever skips verification.
//  See docs/uv-python-runtime-migration.md (Phase 1).
//

import AppKit

// The network fetch step, isolated so it can be faked in tests / later phases.
protocol iTermUvTarballFetcher: AnyObject {
    // Confirm with the user (byteCount is the download size), then download the
    // tarball at url showing progress titled `title`. Completion may run on any
    // queue; a user cancellation completes with a failure.
    func fetch(url: URL, title: String, byteCount: Int, completion: @escaping (Result<Data, Error>) -> Void)
}

@objc(iTermUvProvisioner)
class iTermUvProvisioner: NSObject {
    @objc static let shared = iTermUvProvisioner()

    private static let errorDomain = "com.googlecode.iterm2.uv"

    private let fetcher: iTermUvTarballFetcher

    // Serializes uv venv/pip work so concurrent launches (e.g. several autolaunch
    // scripts, or the REPL) never build into the same shared-venv directory at once.
    // Per-minor coalescing falls out of this plus the isExecutableFile re-check.
    private static let provisionQueue = DispatchQueue(label: "com.googlecode.iterm2.uv.provision")

    // Single-flights the uv binary download: concurrent callers share one download
    // rather than each spawning a window/download and racing on the install.
    private let downloadLock = NSLock()
    private var downloadInProgress = false
    private var pendingDownloadCompletions: [(Error?) -> Void] = []

    // Coalesces concurrent migrations of the same script so two launches never race
    // the backup/provide into one container.
    private let migrationLock = NSLock()
    private var migrationsInFlight: [String: [(NSError?) -> Void]] = [:]

    init(fetcher: iTermUvTarballFetcher) {
        self.fetcher = fetcher
        super.init()
    }

    @objc override convenience init() {
        self.init(fetcher: iTermUvWindowControllerFetcher())
    }

    // Download the uv manifest from iterm2.com and pick the entry whose macOS bracket
    // includes the running OS (the newest compatible uv version). Runs synchronously,
    // so call it off the main thread. The `signature` on the chosen entry is an RSA
    // signature verified against the app's bundled public key at install time.
    static func fetchSelectedEntry() -> Result<iTermUvManifestEntry, Error> {
        guard let urlString = iTermAdvancedSettingsModel.uvManifestDownloadURL(),
              let manifestURL = URL(string: urlString) else {
            return .failure(error("The uv manifest URL is not valid."))
        }
        guard let data = boundedDownload(from: manifestURL, maxBytes: maxManifestBytes) else {
            return .failure(error("Could not download the uv manifest from \(urlString)."))
        }
        return selectedEntry(fromManifestData: data, runningMacOSVersion: runningMacOSVersionString())
    }

    // The pure parse -> select -> floor step, split from the network fetch so it is
    // unit-testable with crafted manifest bytes (no network, no real uv).
    static func selectedEntry(fromManifestData data: Data,
                              runningMacOSVersion: String) -> Result<iTermUvManifestEntry, Error> {
        guard let entries = iTermUvManifest.parse(data) else {
            // parse() returns nil only when the top level is not a JSON array at all.
            return .failure(error("The uv manifest is not valid JSON (a hosting problem, not a macOS-version problem)."))
        }
        guard !entries.isEmpty else {
            // Parsed fine but every entry was filtered out (empty manifest, or all entries
            // had a shape this build could not decode). That is a manifest/hosting problem,
            // NOT "unavailable for this macOS", so do not misdiagnose it as such.
            return .failure(error("The uv manifest lists no usable entries (a hosting or manifest problem)."))
        }
        guard let entry = iTermUvManifest.select(entries: entries,
                                                 runningMacOSVersion: runningMacOSVersion) else {
            return .failure(error("uv is not available for macOS \(runningMacOSVersion)."))
        }
        // The manifest itself is not signed (only the tarball is), so a compromised
        // host could offer an older, still-validly-signed uv (a rollback). Refuse any
        // build older than the minimum the app requires.
        guard iTermDottedVersion.compare(entry.uvVersion, minimumUvVersion) != .orderedAscending else {
            return .failure(error("The offered uv version (\(entry.uvVersion)) is older than the minimum required (\(minimumUvVersion))."))
        }
        // The manifest is unsigned, so `size` is attacker-controlled if the host is
        // compromised. Require a sane positive size here, before any bytes are fetched,
        // so the download cap and the consent-dialog arithmetic can trust it: a huge
        // value would otherwise overflow (crash), and a zero would disable the cap.
        guard entry.size > 0 && entry.size <= maxTarballBytes else {
            return .failure(error("The uv manifest declares an implausible download size (\(entry.size) bytes)."))
        }
        return .success(entry)
    }

    // Absolute ceilings for what the (unsigned) manifest can make us download, so a
    // compromised host cannot exhaust memory regardless of what it claims. The uv
    // universal tarball is ~37 MB; the manifest itself is a few hundred bytes.
    static let maxTarballBytes = 200 * 1024 * 1024
    static let maxManifestBytes = 1 * 1024 * 1024

    // Whether a background check should replace the installed uv with the manifest's:
    // only when the manifest is strictly newer (never equal, never older).
    static func shouldUpgradeUv(installedVersion: String, manifestVersion: String) -> Bool {
        return iTermDottedVersion.compare(manifestVersion, installedVersion) == .orderedDescending
    }

    // The oldest uv the app will install. Bump when a newer uv becomes required.
    static let minimumUvVersion = "0.12.0"

    static func runningMacOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        // Include the patch component so manifest brackets can express patch bounds if
        // ever needed; iTermDottedVersion.compare handles the length mismatch against
        // two-part bounds like "13.0".
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - On-disk layout

    private static var uvDirectory: String {
        guard let appSupport = FileManager.default.spacelessAppSupportCreatingLink() else {
            // Falling back to a temp directory silently would install uv somewhere the
            // OS can clear out from under us, breaking every later launch with no clue
            // why. Log loudly (this shows up in a debug log) before the fallback.
            RLog("uv: could not create the spaceless Application Support link; falling back to a temporary directory. uv installs will not persist.")
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("uv")
        }
        return (appSupport as NSString).appendingPathComponent("uv")
    }

    @objc static var uvBinaryPath: String {
        return ((uvDirectory as NSString).appendingPathComponent("bin") as NSString)
            .appendingPathComponent("uv")
    }

    @objc static var isInstalled: Bool {
        return FileManager.default.isExecutableFile(atPath: uvBinaryPath)
    }

    @objc static var pythonInstallDirectory: String {
        return (uvDirectory as NSString).appendingPathComponent("python")
    }

    @objc static var cacheDirectory: String {
        return (uvDirectory as NSString).appendingPathComponent("cache")
    }

    // The full environment for running uv as a subprocess (process env + UV_*
    // overrides). Exposed for callers that run uv in a visible session.
    @objc static func provisionEnvironment() -> [String: String] {
        return mergedEnvironment(pythonInstallDir: pythonInstallDirectory, cacheDir: cacheDirectory)
    }

    // MARK: - Pure filesystem helpers (unit-tested)

    // Find the uv executable inside an extracted tarball. The Astral tarball places
    // it at uv-<arch>-apple-darwin/uv, so check the root and then one level down.
    // A directory named "uv" does not count.
    static func locateUvBinary(inDirectory directory: String) -> String? {
        let fm = FileManager.default
        func isRegularFile(_ path: String) -> Bool {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        let direct = (directory as NSString).appendingPathComponent("uv")
        if isRegularFile(direct) {
            return direct
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        for entry in entries {
            let candidate = ((directory as NSString).appendingPathComponent(entry) as NSString)
                .appendingPathComponent("uv")
            if isRegularFile(candidate) {
                return candidate
            }
        }
        return nil
    }

    // Remove orphaned uv-binary install temps (.uv-install-<uuid>, each ~90 MB) left in
    // uv/bin/ by a crash between the copy and the rename. install() uses a fresh UUID each
    // time and never cleans old ones, so without this they accumulate. Safe to call at
    // launch; a no-op if none exist. Runs off the main thread.
    @objc func sweepOrphanedInstallTemps() {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let binDir = (Self.uvBinaryPath as NSString).deletingLastPathComponent
            guard let entries = try? fm.contentsOfDirectory(atPath: binDir) else {
                return
            }
            for entry in entries where entry.hasPrefix(".uv-install-") {
                let path = (binDir as NSString).appendingPathComponent(entry)
                try? fm.removeItem(atPath: path)
                RLog("uv: removed orphaned install temp \(path)")
            }
        }
    }

    // Copy the located uv binary to destinationBinaryPath, creating the containing
    // directory and marking it executable. Throws if no binary is found.
    static func install(fromExtractedDirectory directory: String,
                        to destinationBinaryPath: String) throws {
        guard let source = locateUvBinary(inDirectory: directory) else {
            throw error("The uv download did not contain a uv binary.")
        }
        let fm = FileManager.default
        let destinationDirectory = (destinationBinaryPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)
        // Copy to a temp file in the same directory, mark it executable, then rename it
        // over the destination. Rename within a directory is atomic, so a crash mid-copy
        // leaves only the temp file, never a partial uv/bin/uv that isExecutableFile
        // would trust forever.
        let tempPath = (destinationDirectory as NSString)
            .appendingPathComponent(".uv-install-" + UUID().uuidString)
        try? fm.removeItem(atPath: tempPath)
        do {
            try fm.copyItem(atPath: source, toPath: tempPath)
            if fm.fileExists(atPath: destinationBinaryPath) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: destinationBinaryPath),
                                         withItemAt: URL(fileURLWithPath: tempPath))
            } else {
                try fm.moveItem(atPath: tempPath, toPath: destinationBinaryPath)
            }
            // Set the mode on the destination AFTER the swap: replaceItemAt preserves
            // the ORIGINAL file's permissions, so a non-executable partial left by an
            // interrupted earlier attempt would otherwise stay non-executable, and
            // isInstalled would never become true (an endless re-download loop).
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationBinaryPath)
        } catch {
            try? fm.removeItem(atPath: tempPath)
            throw error
        }
    }

    // Verify the RSA signature of the downloaded bytes against the app's bundled
    // public key (rsa_pub.pem), then extract the tarball and install the binary.
    // Verification happens before anything is extracted; the same bytes are then
    // extracted, so there is no time-of-check/time-of-use gap.
    static func installDownloadedTarball(data: Data,
                                         encodedSignature: String,
                                         destinationBinaryPath: String) -> Error? {
        if let verifyError = verifyDownloadedTarball(data: data, encodedSignature: encodedSignature) {
            return verifyError
        }
        return extractAndInstall(data: data, destinationBinaryPath: destinationBinaryPath)
    }

    // RSA-SHA256 signature check against the bundled public key. iTermSignatureVerifier
    // takes a file URL, so the bytes are written to a temp file first.
    static func verifyDownloadedTarball(data: Data, encodedSignature: String) -> Error? {
        guard let keyURL = Bundle.main.url(forResource: "rsa_pub", withExtension: "pem"),
              let publicKey = try? String(contentsOf: keyURL, encoding: .utf8) else {
            return error("Could not load the uv signature public key.")
        }
        let tempFile = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("uv-verify-" + UUID().uuidString)
        // Register cleanup BEFORE the write, so a failure mid-write (which can leave a
        // partial ~37 MB file) is still cleaned up rather than leaked.
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        do {
            try data.write(to: URL(fileURLWithPath: tempFile))
            if let verifyError = iTermSignatureVerifier.validateFileURL(URL(fileURLWithPath: tempFile),
                                                                        withEncodedSignature: encodedSignature,
                                                                        publicKey: publicKey) {
                return verifyError
            }
            return nil
        } catch {
            return error
        }
    }

    // Extract the tarball and install the uv binary (no verification). Split out so
    // the risk-bearing filesystem logic is unit-testable without a signature.
    static func extractAndInstall(data: Data, destinationBinaryPath: String) -> Error? {
        let fm = FileManager.default
        let staging = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("uv-install-" + UUID().uuidString)
        do {
            try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(atPath: staging) }
            let tarball = (staging as NSString).appendingPathComponent("uv.tar.gz")
            try data.write(to: URL(fileURLWithPath: tarball))
            let extracted = (staging as NSString).appendingPathComponent("extracted")
            try fm.createDirectory(atPath: extracted, withIntermediateDirectories: true)
            let status = iTermCommandRunner(command: "/usr/bin/tar",
                                            withArguments: ["-xzf", tarball, "-C", extracted],
                                            path: extracted).blockingRun()
            guard status == 0 else {
                return error("Failed to extract uv (tar exited with status \(status)).")
            }
            try install(fromExtractedDirectory: extracted, to: destinationBinaryPath)
            return nil
        } catch {
            return error
        }
    }

    // Parse `uv --version` output ("uv 0.12.0 (hash date)") into the version. The
    // output has a trailing newline and may lack the parenthesized suffix, so trim
    // before splitting.
    static func parseUvVersion(fromVersionOutput output: String) -> String {
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return parts.count >= 2 ? String(parts[1]) : "unknown"
    }

    // The version of the installed uv binary, for recording in the marker.
    static func installedUvVersion(uvPath: String) -> String {
        let runner = iTermBufferedCommandRunner(command: uvPath,
                                                withArguments: ["--version"],
                                                path: NSTemporaryDirectory())
        // Same UV_* environment (incl. UV_NO_CONFIG) as the other invocations, and
        // stderr kept out of the parsed output.
        runner.environment = provisionEnvironment()
        runner.discardStandardError = true
        _ = runner.blockingRun(withTimeout: uvQueryTimeout)
        let output = runner.output.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return parseUvVersion(fromVersionOutput: output)
    }

    // Packages every uv environment gets in addition to a script’s declared
    // dependencies. iterm2 is the API module; certifi supplies TLS roots (there is
    // no baked-in openssl cert directory as in the legacy runtime); pyobjc restores
    // the objc/AppKit/Foundation bindings that the legacy bundled runtime always
    // shipped, so scripts that `import objc` keep working. All are wheels-only
    // (--only-binary :all:), and pyobjc publishes universal2 wheels.
    static let alwaysInstalledPackages = ["iterm2", "certifi", "pyobjc"]

    // MARK: - Full-environment provisioning (runs uv; integration-tested live)

    // The full environment uv builds under a script container: a .venv plus the
    // python-runtime.json marker. iterm2 and certifi are always installed. Returns
    // the marker on success (its remappedFrom tells the caller whether to warn the
    // user that the Python version changed), or an error.
    static func provisionFullEnvironment(uvPath: String,
                                         pythonInstallDir: String,
                                         cacheDir: String,
                                         container: String,
                                         requestedPythonVersion: String,
                                         dependencies: [String]) -> Result<iTermPythonRuntimeMarker, Error> {
        let environment = mergedEnvironment(pythonInstallDir: pythonInstallDir, cacheDir: cacheDir)
        let available = availableMinors(uvPath: uvPath, environment: environment)
        let resolved = iTermUvPythonVersion.resolve(requested: requestedPythonVersion, available: available)

        let fileManager = FileManager.default
        let venvPath = (container as NSString).appendingPathComponent(iTermScriptRuntime.venvDirectoryName)
        // Build the new venv aside and swap it into place only after it is fully
        // populated, so a failed re-provision (e.g. the Dependency Editor changing to a
        // Python version where a pinned dependency has no wheel) leaves the existing
        // working .venv intact instead of destroying it. The venv is created
        // --relocatable, so moving it after the build keeps its shebangs valid. A fresh
        // container (create/import/migrate) has no existing .venv, so the swap at the end
        // is just a rename into place.
        let buildPath = (container as NSString).appendingPathComponent(iTermScriptRuntime.venvDirectoryName + ".building")
        try? fileManager.removeItem(atPath: buildPath)
        if let error = run(uvPath,
                           iTermUvCommand.venvArgs(pythonVersion: resolved.version, venvPath: buildPath),
                           environment) {
            try? fileManager.removeItem(atPath: buildPath)
            return .failure(error)
        }

        let venvPython = (buildPath as NSString).appendingPathComponent("bin/python")
        // The always-installed packages (iterm2, certifi, pyobjc) come in addition to
        // the script's declared dependencies.
        let packages = orderedUnique(dependencies + alwaysInstalledPackages)
        if let error = run(uvPath,
                           iTermUvCommand.pipInstallArgs(venvPythonPath: venvPython, packages: packages),
                           environment) {
            try? fileManager.removeItem(atPath: buildPath)
            return .failure(error)
        }

        // Everything the new venv needs is present; put it in place. When an old .venv
        // exists, swap the two directory inodes in a single atomic syscall
        // (renamex_np/RENAME_SWAP) rather than a multi-step replace, so a concurrent
        // reader (e.g. the Dependency Editor's `pip show`) can never observe a partial
        // or missing .venv, then discard the old one (now at buildPath). A fresh
        // container has no .venv, so a plain rename into place suffices.
        if fileManager.fileExists(atPath: venvPath) {
            let swapped = buildPath.withCString { newC in
                venvPath.withCString { oldC in
                    renamex_np(newC, oldC, UInt32(RENAME_SWAP))
                }
            }
            if swapped != 0 {
                let code = errno
                // RENAME_SWAP is APFS/HFS+ only. A custom scripts folder on SMB/NFS/exFAT
                // returns ENOTSUP (45) / EINVAL (22); fall back to a non-atomic
                // move-old-aside, rename-new-into-place, delete-old. The brief window where
                // .venv is a fresh build name is acceptable on such volumes (a concurrent
                // pip show is the only reader and it re-runs), and beats failing every
                // rebuild forever with an unactionable errno.
                if code == ENOTSUP || code == EINVAL {
                    let oldAside = venvPath + ".old"
                    try? fileManager.removeItem(atPath: oldAside)
                    do {
                        try fileManager.moveItem(atPath: venvPath, toPath: oldAside)
                        try fileManager.moveItem(atPath: buildPath, toPath: venvPath)
                        try? fileManager.removeItem(atPath: oldAside)
                    } catch {
                        // Best effort to restore the old venv if the new one didn't land.
                        if !fileManager.fileExists(atPath: venvPath) {
                            try? fileManager.moveItem(atPath: oldAside, toPath: venvPath)
                        }
                        try? fileManager.removeItem(atPath: buildPath)
                        return .failure(error as NSError)
                    }
                } else {
                    try? fileManager.removeItem(atPath: buildPath)
                    return .failure(NSError(domain: NSPOSIXErrorDomain,
                                            code: Int(code),
                                            userInfo: [NSLocalizedDescriptionKey:
                                                        "Could not install the rebuilt Python environment at \(venvPath) (errno \(code))."]))
                }
            } else {
                try? fileManager.removeItem(atPath: buildPath)
            }
        } else {
            do {
                try fileManager.moveItem(atPath: buildPath, toPath: venvPath)
            } catch {
                try? fileManager.removeItem(atPath: buildPath)
                return .failure(error)
            }
        }

        let marker = iTermPythonRuntimeMarker(uvVersion: installedUvVersion(uvPath: uvPath),
                                              python: resolved.version,
                                              remappedFrom: resolved.remappedFrom)
        do {
            let markerPath = (container as NSString).appendingPathComponent(iTermScriptRuntime.markerFileName)
            try marker.jsonData().write(to: URL(fileURLWithPath: markerPath))
        } catch {
            return .failure(error)
        }
        return .success(marker)
    }

    // The Python minors the INSTALLED uv can actually provide (from `uv python list`),
    // delivered on the main queue. Empty if uv is not installed or the query fails.
    // Spawns uv, so it runs off the main thread. Use this to populate version pickers so
    // they reflect the installed uv's real capabilities rather than a hardcoded guess
    // (which could offer versions an older installed uv cannot provide).
    @objc func availableMinors(completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.isInstalled else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let environment = Self.mergedEnvironment(pythonInstallDir: Self.pythonInstallDirectory,
                                                     cacheDir: Self.cacheDirectory)
            let minors = Self.availableMinors(uvPath: Self.uvBinaryPath, environment: environment)
            DispatchQueue.main.async { completion(minors) }
        }
    }

    // The available stable CPython minors uv can provide, or [] if the query fails.
    static func availableMinors(uvPath: String, environment: [String: String]) -> [String] {
        let runner = iTermBufferedCommandRunner(command: uvPath,
                                                withArguments: iTermUvCommand.pythonListArgs(),
                                                path: NSTemporaryDirectory())
        runner.environment = environment
        // `uv python list --output-format json` prints JSON on stdout; any warning on
        // stderr would otherwise be merged in and break the JSON parse, silently
        // disabling version remapping.
        runner.discardStandardError = true
        _ = runner.blockingRun(withTimeout: uvQueryTimeout)
        guard let output = runner.output else {
            return []
        }
        return iTermUvPythonVersion.availableMinors(fromListJSON: output)
    }

    private static func mergedEnvironment(pythonInstallDir: String, cacheDir: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let overrides = iTermUvCommand.provisionEnvironment(pythonInstallDir: pythonInstallDir, cacheDir: cacheDir)
        // We override only the known UV_* keys (install dir, cache dir, UV_NO_CONFIG, etc.),
        // but the inherited process environment can carry OTHER UV_* variables (UV_OFFLINE,
        // UV_INDEX_URL, UV_HTTP_TIMEOUT, UV_PYTHON, ...) that a user exported via launchctl
        // setenv or by launching iTerm2 from a shell. UV_NO_CONFIG neutralizes config files,
        // not env vars, so those still silently alter provisioning. Log any we did not set
        // ourselves so field debugging can see them (we keep them: a user who exported an
        // internal index URL likely needs it).
        let inheritedUvKeys = environment.keys.filter { $0.hasPrefix("UV_") && overrides[$0] == nil }.sorted()
        if !inheritedUvKeys.isEmpty {
            RLog("uv: inherited UV_* environment variables affect provisioning: \(inheritedUvKeys.joined(separator: ", "))")
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    // A generous safety-net timeout for uv build operations (venv creation, pip install)
    // that download from the network. It is NOT a "slow link" cap (uv has its own HTTP
    // timeouts and legitimate first provisioning on a slow link finishes well under this);
    // it only bounds a pathologically hung subprocess so it cannot wedge provisionQueue,
    // and every provision/launch queued behind it, forever.
    private static let uvBuildTimeout: TimeInterval = 3600
    // A short timeout for quick metadata queries (`uv --version`, `uv python list`), which
    // never legitimately take long, so a hang there does not stall the queue for an hour.
    private static let uvQueryTimeout: TimeInterval = 60

    private static func run(_ path: String, _ arguments: [String], _ environment: [String: String]) -> NSError? {
        let runner = iTermBufferedCommandRunner(command: path, withArguments: arguments, path: NSTemporaryDirectory())
        runner.environment = environment
        let status = runner.blockingRun(withTimeout: uvBuildTimeout)
        guard status == 0 else {
            // Include uv's own output (the real reason: an unresolved dependency, a
            // missing wheel under --only-binary, etc.) so a failure is diagnosable
            // from a normal (non-debug-log) build.
            let output = runner.output.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let detail = output.isEmpty ? "" : "\n\(output.suffix(2000))"
            return error("uv \(arguments.first ?? "command") failed with status \(status).\(detail)")
        }
        return nil
    }

    private static func orderedUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: - Download orchestration

    // Download and install uv if it is not already present. The completion always
    // runs on the main queue with nil on success or an error on failure. The heavy
    // verify/extract/install runs off the main thread.
    @objc func downloadIfNeeded(completion: @escaping (Error?) -> Void) {
        let finish: (Error?) -> Void = { error in
            if Thread.isMainThread {
                completion(error)
            } else {
                DispatchQueue.main.async { completion(error) }
            }
        }
        if Self.isInstalled {
            finish(nil)
            return
        }
        // Coalesce concurrent downloads: only the first caller does the work; the
        // rest wait and share its result.
        downloadLock.lock()
        if Self.isInstalled {
            // A concurrent download finished while we waited on the lock.
            downloadLock.unlock()
            finish(nil)
            return
        }
        pendingDownloadCompletions.append(finish)
        if downloadInProgress {
            downloadLock.unlock()
            return
        }
        downloadInProgress = true
        downloadLock.unlock()

        let deliver: (Error?) -> Void = { [weak self] resultError in
            guard let self = self else { return }
            self.downloadLock.lock()
            let completions = self.pendingDownloadCompletions
            self.pendingDownloadCompletions = []
            self.downloadInProgress = false
            self.downloadLock.unlock()
            for completion in completions {
                completion(resultError)
            }
        }

        // Fetch the manifest off-main (it is a blocking network read), then confirm
        // and download the chosen build on main.
        Self.provisionQueue.async {
            switch Self.fetchSelectedEntry() {
            case .failure(let error):
                deliver(error)
            case .success(let entry):
                guard let url = URL(string: entry.url) else {
                    deliver(Self.error("The uv download URL is not valid."))
                    return
                }
                DispatchQueue.main.async {
                    self.fetcher.fetch(url: url, title: String(localized: "UvProvisioner.DownloadingUv", defaultValue: "Downloading uv…", comment: "Progress title shown while downloading the uv tool"), byteCount: entry.size) { result in
                        switch result {
                        case .failure(let error):
                            deliver(error)
                        case .success(let data):
                            Self.provisionQueue.async {
                                deliver(Self.installDownloadedTarball(data: data,
                                                                      encodedSignature: entry.signature,
                                                                      destinationBinaryPath: Self.uvBinaryPath))
                            }
                        }
                    }
                }
            }
        }
    }

    // True while a full-environment .venv is being built under the Scripts folder. The
    // scripts-folder watcher checks this to suppress the storm of menu rebuilds that the
    // thousands of file events from `uv venv` + `uv pip install` would otherwise cause.
    // Shared basic-script venvs live outside Scripts and do not need this.
    private static let provisioningLock = NSLock()
    private static var provisioningCount = 0

    @objc static var isProvisioningFullEnvironment: Bool {
        provisioningLock.lock()
        defer { provisioningLock.unlock() }
        return provisioningCount > 0
    }

    private static func beginProvisioning() {
        provisioningLock.lock()
        provisioningCount += 1
        provisioningLock.unlock()
    }

    private static func endProvisioning() {
        provisioningLock.lock()
        provisioningCount -= 1
        provisioningLock.unlock()
    }

    // Download uv if needed, then provision a full-environment script's .venv. The
    // completion runs on the main queue with nil on success or an error. provisioningDidBegin
    // (if given) runs on the main queue once the download phase is done and the venv build
    // is starting, so a caller can show progress only after the download window closes.
    // Callable from the Obj-C create/import paths.
    @objc func downloadAndProvisionFullEnvironment(container: String,
                                                   requestedPythonVersion: String,
                                                   dependencies: [String],
                                                   createSetupCfg: Bool,
                                                   provisioningDidBegin: (() -> Void)? = nil,
                                                   completion: @escaping (NSError?) -> Void) {
        // downloadIfNeeded fetches the manifest and reports "not available for this
        // macOS" if no compatible uv build exists, so no separate check is needed.
        downloadIfNeeded { error in
            if let error = error {
                completion(error as NSError)
                return
            }
            Self.provisionQueue.async {
                Self.beginProvisioning()
                defer { Self.endProvisioning() }
                if let provisioningDidBegin = provisioningDidBegin {
                    DispatchQueue.main.async { provisioningDidBegin() }
                }
                let result = Self.provisionFullEnvironment(uvPath: Self.uvBinaryPath,
                                                           pythonInstallDir: Self.pythonInstallDirectory,
                                                           cacheDir: Self.cacheDirectory,
                                                           container: container,
                                                           requestedPythonVersion: requestedPythonVersion,
                                                           dependencies: dependencies)
                let resultError: NSError?
                switch result {
                case .success(let marker):
                    // The create path has no setup.cfg yet; the import path already
                    // ships one and must not have it overwritten.
                    if createSetupCfg {
                        let setupCfgPath = (container as NSString).appendingPathComponent("setup.cfg")
                        // Preserve existing metadata when rewriting an existing setup.cfg
                        // (e.g. the Dependency Editor changing the Python version): a script
                        // whose [metadata] name differs from its folder, or that pins a
                        // specific environment version, must not be silently renamed or
                        // reset. Only fall back to defaults for a brand-new setup.cfg (the
                        // create path, where none exists yet).
                        let existing = iTermSetupCfgParser(path: setupCfgPath)
                        iTermSetupCfgParser.writeSetupCfg(
                            toFile: setupCfgPath,
                            name: existing?.name ?? (container as NSString).lastPathComponent,
                            dependencies: dependencies,
                            ensureiTerm2Present: true,
                            pythonVersion: marker.python,
                            environmentVersion: existing?.minimumEnvironmentVersion ?? Int(iTermMinimumPythonEnvironmentVersion))
                    }
                    // If uv could not provide the script's pinned Python version and had
                    // to bump it, tell the user (once, suppressibly). Every provisioning
                    // path (create, import, migrate) funnels through here.
                    if let from = marker.remappedFrom {
                        Self.reportForcedRemap(scriptName: (container as NSString).lastPathComponent,
                                               from: from, to: marker.python)
                    }
                    resultError = nil
                case .failure(let error):
                    resultError = error as NSError
                }
                DispatchQueue.main.async { completion(resultError) }
            }
        }
    }

    // Surface a forced Python-version bump: a Script Console line for the record and a
    // suppressible modal so the user knows their script may need small changes. Design
    // decision 7 / Phase 3. Called off the main thread. scriptName is nil for a shared
    // basic-script venv (which is not tied to one script), giving a generic message.
    private static func reportForcedRemap(scriptName: String?, from: String, to: String) {
        let fromMinor = iTermUvPythonVersion.twoPartVersion(from)
        let caveat = "Python versions are not always compatible across releases, so a bumped script may need small changes."
        let text: String
        if let scriptName = scriptName {
            text = iTermUvMigration.consolidatedWarningText(
                remaps: [iTermUvPythonRemap(scriptName: scriptName, fromVersion: fromMinor, toVersion: to)])
        } else {
            text = "A script was written for Python \(fromMinor), which is no longer available, "
                + "so it now uses Python \(to). " + caveat
        }
        RLog("uv: \(text)")
        // Console-only, per the design: the ONE user-facing modal is the consolidated
        // predictive warning shown at startup (iTermScriptsMenuController). Showing a
        // per-script modal here too meant a user with N affected scripts saw N+1 modals,
        // and (because a uv upgrade invalidates remap records and forces re-resolution) the
        // same modal recurred every upgrade cycle. A Script Console line each migration is
        // the intended per-script record.
        DispatchQueue.main.async {
            iTermScriptHistoryEntry.global().addOutput(text + "\n", completion: {})
        }
    }

    // MARK: - Migrating a legacy script to uv

    // Rebuild an existing legacy full-environment script as a uv .venv, with
    // rollback: the legacy iterm2env is moved aside first and restored if the uv
    // provision fails, so a failure leaves the script runnable on its old runtime.
    // Completion runs on the main queue with nil on success.
    @objc func migrateLegacyScriptToUv(container: String,
                                       requestedPythonVersion: String,
                                       dependencies: [String],
                                       provisioningDidBegin: (() -> Void)? = nil,
                                       completion: @escaping (NSError?) -> Void) {
        migrationLock.lock()
        if migrationsInFlight[container] != nil {
            migrationsInFlight[container]?.append(completion)
            migrationLock.unlock()
            return
        }
        migrationsInFlight[container] = [completion]
        migrationLock.unlock()

        let finishAll: (NSError?) -> Void = { [weak self] error in
            guard let self = self else { return }
            self.migrationLock.lock()
            let waiters = self.migrationsInFlight.removeValue(forKey: container) ?? []
            self.migrationLock.unlock()
            for waiter in waiters {
                waiter(error)
            }
        }

        do {
            try iTermUvMigration.backUpLegacyEnvironment(container: container)
        } catch {
            finishAll(error as NSError)
            return
        }
        downloadAndProvisionFullEnvironment(container: container,
                                            requestedPythonVersion: requestedPythonVersion,
                                            dependencies: dependencies,
                                            createSetupCfg: false,
                                            provisioningDidBegin: provisioningDidBegin) { error in
            if let error = error {
                try? iTermUvMigration.restoreLegacyEnvironment(container: container)
                finishAll(error)
            } else {
                iTermUvMigration.discardLegacyBackup(container: container)
                finishAll(nil)
            }
        }
    }

    // MARK: - Dependency editing (uv pip against a script's .venv)

    // Obj-C-visible bridge to the pip passthrough arg builder (iTermUvCommand is a
    // Swift enum). `<uvBinaryPath> <these args>` runs a pip subcommand against a venv.
    @objc static func uvPipArguments(pipArguments: [String], venvPython: String) -> [String] {
        return iTermUvCommand.pipPassthroughArgs(pipArguments: pipArguments, venvPythonPath: venvPython)
    }

    // Run a pip subcommand through uv against a venv and capture the combined
    // stdout+stderr. completion runs on the main queue with (success, output),
    // mirroring the legacy runPip3InContainer signature.
    @objc func runUvPip(pipArguments: [String],
                        venvPython: String,
                        completion: @escaping (Bool, Data) -> Void) {
        Self.provisionQueue.async {
            let runner = iTermBufferedCommandRunner(
                command: Self.uvBinaryPath,
                withArguments: iTermUvCommand.pipPassthroughArgs(pipArguments: pipArguments, venvPythonPath: venvPython),
                path: NSTemporaryDirectory())
            runner.environment = Self.mergedEnvironment(pythonInstallDir: Self.pythonInstallDirectory,
                                                        cacheDir: Self.cacheDirectory)
            let status = runner.blockingRun(withTimeout: Self.uvBuildTimeout)
            let output = runner.output ?? Data()
            DispatchQueue.main.async { completion(status == 0, output) }
        }
    }

    // MARK: - Shared basic-script venvs

    static var sharedVenvsRoot: String {
        return (uvDirectory as NSString).appendingPathComponent("venvs")
    }

    @objc static func sharedVenvDirectory(forMinor minor: String) -> String {
        return (sharedVenvsRoot as NSString).appendingPathComponent(minor)
    }

    @objc static func sharedVenvPython(forMinor minor: String) -> String {
        return (sharedVenvDirectory(forMinor: minor) as NSString).appendingPathComponent("bin/python")
    }

    // A remapped shebang (e.g. python3.7 when 3.7 is unavailable) provisions a venv for
    // the resolved minor (3.9). Record requested->resolved under venvs/.remaps/<requested>
    // so a later OFFLINE launch can find the working venv without asking uv to resolve
    // again (which needs the network / a uv spawn and, offline, fails).
    private static let sharedVenvRemapsDirectoryName = ".remaps"

    private static func sharedVenvRemapPath(forRequestedMinor minor: String, venvsRoot: String) -> String {
        return ((venvsRoot as NSString).appendingPathComponent(sharedVenvRemapsDirectoryName) as NSString)
            .appendingPathComponent(minor)
    }

    // The interpreter for an already-provisioned shared venv for requestedVersion, using
    // only the filesystem (no uv, no network), or nil if none is provisioned yet. Handles
    // a direct minor match and a recorded requested->resolved remap. venvsRoot is injected
    // so the decision is hermetically testable; the production overload uses the real root.
    static func provisionedSharedVenvInterpreter(forRequestedVersion requestedVersion: String,
                                                 venvsRoot: String) -> String? {
        guard let requestedMinor = normalizedMinor(requestedVersion) else {
            return nil
        }
        let fm = FileManager.default
        if sharedVenvIsProvisioned(forMinor: requestedMinor, venvsRoot: venvsRoot) {
            return sharedVenvInterpreterPath(forMinor: requestedMinor, venvsRoot: venvsRoot)
        }
        if let data = fm.contents(atPath: sharedVenvRemapPath(forRequestedMinor: requestedMinor, venvsRoot: venvsRoot)),
           let resolvedMinor = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolvedMinor.isEmpty,
           sharedVenvIsProvisioned(forMinor: resolvedMinor, venvsRoot: venvsRoot) {
            return sharedVenvInterpreterPath(forMinor: resolvedMinor, venvsRoot: venvsRoot)
        }
        return nil
    }

    static func provisionedSharedVenvInterpreter(forRequestedVersion requestedVersion: String) -> String? {
        return provisionedSharedVenvInterpreter(forRequestedVersion: requestedVersion, venvsRoot: sharedVenvsRoot)
    }

    private static func recordSharedVenvRemap(fromRequestedMinor requestedMinor: String, toResolvedMinor resolvedMinor: String) {
        let path = sharedVenvRemapPath(forRequestedMinor: requestedMinor, venvsRoot: sharedVenvsRoot)
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try Data(resolvedMinor.utf8).write(to: URL(fileURLWithPath: path))
        } catch {
            RLog("uv: could not record shared-venv remap \(requestedMinor)->\(resolvedMinor): \(error.localizedDescription)")
        }
    }

    // A sentinel written only after the packages finish installing. `uv venv` creates
    // bin/python before pip runs, so the interpreter existing does not mean the venv
    // is usable; a healthy venv has both the interpreter and this marker. Without it,
    // a pip failure (or a kill mid-install) would leave a half-built venv that every
    // later launch treats as done, yielding “ModuleNotFoundError: iterm2” forever.
    private static let sharedVenvMarkerName = ".provisioned"

    private static func sharedVenvMarkerPath(forMinor minor: String) -> String {
        return (sharedVenvDirectory(forMinor: minor) as NSString).appendingPathComponent(sharedVenvMarkerName)
    }

    // The interpreter path for a shared venv minor under an arbitrary venvsRoot.
    static func sharedVenvInterpreterPath(forMinor minor: String, venvsRoot: String) -> String {
        return ((venvsRoot as NSString).appendingPathComponent(minor) as NSString)
            .appendingPathComponent("bin/python")
    }

    // The single "a shared venv is fully provisioned" predicate: an executable interpreter
    // AND the .provisioned marker (written only after packages install, so a half-built
    // venv does not count). venvsRoot is injected for hermetic testing; the production
    // overload uses the real root. All callers go through here so the fast path, the
    // stale-remap fallback, and the module-refresh scan cannot disagree about what counts.
    static func sharedVenvIsProvisioned(forMinor minor: String, venvsRoot: String) -> Bool {
        let fm = FileManager.default
        let markerPath = ((venvsRoot as NSString).appendingPathComponent(minor) as NSString)
            .appendingPathComponent(sharedVenvMarkerName)
        return fm.isExecutableFile(atPath: sharedVenvInterpreterPath(forMinor: minor, venvsRoot: venvsRoot)) &&
               fm.fileExists(atPath: markerPath)
    }

    static func sharedVenvIsProvisioned(forMinor minor: String) -> Bool {
        return sharedVenvIsProvisioned(forMinor: minor, venvsRoot: sharedVenvsRoot)
    }

    // "3.12" / "3.12.3" -> "3.12"; nil if not of the form X.Y[.Z] with numeric parts.
    // Used to check for an already-provisioned venv without asking uv to resolve.
    static func normalizedMinor(_ version: String) -> String? {
        let parts = version.split(separator: ".")
        guard parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return "\(parts[0]).\(parts[1])"
    }

    // Ensure a shared venv (with iterm2 + certifi) exists for the resolved minor of
    // requestedPythonVersion, downloading uv and provisioning it if needed, and
    // return that venv's interpreter. Basic scripts share this per-minor, so once it
    // exists a launch is a bare exec with no uv and no network. Completion runs on
    // the main queue.
    @objc func downloadAndProvisionSharedVenv(requestedPythonVersion: String,
                                              completion: @escaping (NSError?, String?) -> Void) {
        // Fast path: if a shared venv for the requested version is already provisioned,
        // return its interpreter without downloading uv, running `uv python list`, or
        // touching the network. This covers a direct minor match and a recorded
        // requested->resolved remap (so an offline relaunch of a python3.7 shebang that
        // was bumped to 3.9 still works). Only a genuine first launch falls through to uv.
        if let interpreter = Self.provisionedSharedVenvInterpreter(forRequestedVersion: requestedPythonVersion) {
            completion(nil, interpreter)
            return
        }
        downloadIfNeeded { error in
            if let error = error {
                completion(error as NSError, nil)
                return
            }
            Self.provisionQueue.async {
                let environment = Self.mergedEnvironment(pythonInstallDir: Self.pythonInstallDirectory,
                                                         cacheDir: Self.cacheDirectory)
                let available = Self.availableMinors(uvPath: Self.uvBinaryPath, environment: environment)
                let resolved = iTermUvPythonVersion.resolve(requested: requestedPythonVersion, available: available)
                let interpreter = Self.sharedVenvPython(forMinor: resolved.version)

                // Record the requested->resolved remap and tell the user once. Only valid
                // once the resolved venv actually exists, so it is invoked either in the
                // already-provisioned branch or after a successful build, never before the
                // build: a failed build must not tell the user the version changed nor leave
                // a record pointing at a venv that does not exist.
                func recordAndReportRemapIfNeeded() {
                    guard let from = resolved.remappedFrom else {
                        return
                    }
                    if let requestedMinor = Self.normalizedMinor(requestedPythonVersion) {
                        Self.recordSharedVenvRemap(fromRequestedMinor: requestedMinor, toResolvedMinor: resolved.version)
                    }
                    Self.reportForcedRemap(scriptName: nil, from: from, to: resolved.version)
                }

                // Re-check with the marker (not just the interpreter) in case a
                // concurrent launch finished, or a prior attempt left a half-built venv.
                // The resolved venv already exists (a direct match, or one built for
                // another script): record+report here so a remap is not lost by skipping the
                // build. This is the case the F9 fix targets.
                if Self.sharedVenvIsProvisioned(forMinor: resolved.version) {
                    recordAndReportRemapIfNeeded()
                    DispatchQueue.main.async { completion(nil, interpreter) }
                    return
                }
                let venvDirectory = Self.sharedVenvDirectory(forMinor: resolved.version)
                // Building the resolved minor failed. Commonly this is offline: either the
                // minor's CPython is not downloaded (uv venv fails) or its packages are not
                // cached (uv pip install fails). Both are "could not build the resolved
                // venv"; if a uv upgrade invalidated an earlier resolution for this request
                // but that resolution's venv is still provisioned, fall back to it so an
                // offline launch of a previously-working remapped script keeps working. A
                // later online launch re-resolves and builds the now-available minor.
                func completeWithBuildFailure(_ error: NSError) {
                    if let fallback = Self.provisionedStaleRemapInterpreter(forRequestedVersion: requestedPythonVersion) {
                        // The fallback engages for ANY build failure (offline, disk full,
                        // a yanked wheel, a broken uv), not only offline, and it silently
                        // runs an older Python. Log it and surface a Script Console line so a
                        // genuinely broken environment is diagnosable rather than presenting
                        // as a script mysteriously on the wrong version with nothing said.
                        RLog("uv: could not build \(resolved.version) for requested \(requestedPythonVersion) (\(error.localizedDescription)); falling back to \(fallback)")
                        DispatchQueue.main.async {
                            iTermScriptHistoryEntry.global().addOutput(
                                "Could not build the Python \(resolved.version) environment (\(error.localizedDescription)). Using a previously provisioned environment instead.\n",
                                completion: {})
                            completion(nil, fallback)
                        }
                        return
                    }
                    DispatchQueue.main.async { completion(error, nil) }
                }
                // Start from a clean directory so a previously interrupted build can't
                // leave stray files behind.
                try? FileManager.default.removeItem(atPath: venvDirectory)
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.venvArgs(pythonVersion: resolved.version, venvPath: venvDirectory),
                                        environment) {
                    try? FileManager.default.removeItem(atPath: venvDirectory)
                    completeWithBuildFailure(error)
                    return
                }
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.pipInstallArgs(venvPythonPath: interpreter, packages: Self.alwaysInstalledPackages),
                                        environment) {
                    // Do not leave a half-built venv: the interpreter exists but the
                    // packages do not, and every later launch would trust it.
                    try? FileManager.default.removeItem(atPath: venvDirectory)
                    completeWithBuildFailure(error)
                    return
                }
                Self.markSharedVenvProvisioned(forMinor: resolved.version)
                // The venv is really built now, so it is safe to record/report the remap.
                recordAndReportRemapIfNeeded()
                DispatchQueue.main.async { completion(nil, interpreter) }
            }
        }
    }

    private static func markSharedVenvProvisioned(forMinor minor: String) {
        do {
            try Data().write(to: URL(fileURLWithPath: sharedVenvMarkerPath(forMinor: minor)))
        } catch {
            // If this fails (e.g. disk full), sharedVenvIsProvisioned stays false and the
            // venv is rebuilt on every launch. Log so that is diagnosable rather than a
            // silent perpetual re-provision.
            RLog("uv: could not write the shared-venv marker for \(minor): \(error.localizedDescription)")
        }
    }

    // MARK: - Periodic background upgrades

    // Throttled across launches (persisted) so the check runs about once a day.
    private static let upgradeRateLimit =
        iTermPersistentRateLimitedUpdate(name: "CheckForUpdatedUv", minimumInterval: 24 * 60 * 60)

    // Once a day at most: if the manifest offers a newer uv, silently replace the
    // installed binary, and upgrade iterm2/certifi/pyobjc to the latest in every
    // provisioned shared basic-script venv. A no-op until uv has been installed, so it
    // is safe (and intended) to call at every launch. Without this, a first-installed
    // uv is never re-checked, so a broken uv could never be replaced and basic scripts'
    // iterm2 module would never update.
    @objc func performPeriodicUpgradeCheck() {
        Self.upgradeRateLimit.performRateLimitedBlock {
            // Run on a background queue, NOT provisionQueue: the network fetch has
            // unbounded latency and must never block a user-visible provision or launch
            // queued behind it. The install swap and pip upgrades hop onto provisionQueue
            // themselves so they stay serialized with provisioning. This runs even with
            // the gate off (guarded only by isInstalled): a script provisioned under uv
            // keeps using it regardless of the gate, so keeping uv and the shared modules
            // current is intended.
            DispatchQueue.global(qos: .utility).async {
                // Re-check installed state now: the persistent rate limit can defer this
                // block up to ~a day, during which the user may have removed uv.
                guard Self.isInstalled else {
                    return
                }
                switch Self.upgradeUvBinaryIfNewerAvailable() {
                case .upgraded(let from, let to):
                    RLog("uv: upgraded uv from \(from) to \(to)")
                case .failed(let message):
                    RLog("uv: background upgrade check failed: \(message)")
                case .upToDate:
                    break
                }
                Self.enqueuePeriodicSharedVenvModuleUpgrades()
            }
        }
    }

    // User-invoked "Check for Updated Runtime": bypasses the daily rate limit, runs the
    // same upgrade pair, and reports a result instead of being fire-and-forget. Because
    // installedUvVersion returns "unknown" for a corrupt or unreadable binary (which
    // loses to any manifest version), this also repairs such a binary. completion runs
    // on the main queue with (success, user-facing message).
    @objc func userRequestedUpgradeCheck(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard Self.isInstalled else {
                DispatchQueue.main.async { completion(false, String(localized: "UvProvisioner.NotInstalled", defaultValue: "uv is not installed.", comment: "Status shown after a user-invoked runtime update check when the uv tool is not installed")) }
                return
            }
            let outcome = Self.upgradeUvBinaryIfNewerAvailable()
            // Refresh the shared-venv modules regardless, so a check also picks up newer
            // iterm2/certifi/pyobjc even when uv itself is already current.
            Self.provisionQueue.sync { Self.upgradeSharedVenvModules() }
            let ok: Bool
            let message: String
            switch outcome {
            case .upToDate(let version):
                ok = true
                message = String(localized: "UvProvisioner.UpToDate", defaultValue: "uv \(version) is up to date.", comment: "Status shown after a user-invoked runtime update check when uv is already current; \\(version) is the installed uv version")
            case .upgraded(let from, let to):
                ok = true
                message = String(localized: "UvProvisioner.Upgraded", defaultValue: "Upgraded uv \(from) to \(to). Updated the Python modules in shared environments.", comment: "Status shown after a user-invoked runtime update check upgrades uv; \\(from) is the old version and \\(to) is the new version")
            case .failed(let failureMessage):
                ok = false
                message = failureMessage
            }
            DispatchQueue.main.async { completion(ok, message) }
        }
    }

    // The result of a uv-binary upgrade check, so a user-invoked check can report it.
    private enum UvBinaryUpgradeOutcome {
        case upToDate(version: String)
        case upgraded(from: String, to: String)
        case failed(message: String)
    }

    // Re-fetch the manifest and, if it offers a newer uv than installed, download and
    // install it (RSA-verified, atomic replace). The minimum-version floor still applies
    // via fetchSelectedEntry, so this never installs an older uv. Returns the outcome so
    // the caller can log (background) or report it (user-invoked). MUST be called off
    // both the main thread and provisionQueue (it does the swap via provisionQueue.sync,
    // which would deadlock if already on that queue).
    private static func upgradeUvBinaryIfNewerAvailable() -> UvBinaryUpgradeOutcome {
        let selected = fetchSelectedEntry()
        guard case .success(let entry) = selected else {
            // Surface the specific reason (bad JSON / empty manifest / floor or size
            // rejection / download failure) rather than always blaming "offline", so a
            // hosting problem is not misreported as a network problem.
            var reason = "unknown error"
            if case .failure(let err) = selected {
                reason = err.localizedDescription
            }
            return .failed(message: String(localized: "UvProvisioner.UpdateCheckFailed", defaultValue: "Could not check for a uv update: \(reason)", comment: "Error shown when checking for a uv runtime update fails; \\(reason) is the underlying failure description"))
        }
        let installed = installedUvVersion(uvPath: uvBinaryPath)
        guard shouldUpgradeUv(installedVersion: installed, manifestVersion: entry.uvVersion) else {
            return .upToDate(version: installed)
        }
        // Cap the download at the manifest-declared size plus slack (size is validated at
        // selection, so this cannot overflow), so a compromised host cannot exhaust memory.
        guard let url = URL(string: entry.url),
              // Generous total cap (1 hour): the ~37 MB tarball must complete on slow
              // links. The 60 s idle timeout still fails a genuinely stalled transfer.
              let data = boundedDownload(from: url,
                                         maxBytes: entry.size + 16 * 1024 * 1024,
                                         resourceTimeout: 3600) else {
            return .failed(message: String(localized: "UvProvisioner.UpdateDownloadFailed", defaultValue: "Could not download the uv update.", comment: "Error shown when downloading a uv runtime update fails"))
        }
        var outcome: UvBinaryUpgradeOutcome = .upToDate(version: installed)
        // Do the swap on provisionQueue so it is serialized with any concurrent provisioning.
        provisionQueue.sync {
            // Re-check under the queue: a concurrent provision or a prior iteration may
            // have already updated the binary.
            let current = installedUvVersion(uvPath: uvBinaryPath)
            guard shouldUpgradeUv(installedVersion: current, manifestVersion: entry.uvVersion) else {
                outcome = .upToDate(version: current)
                return
            }
            if let error = installDownloadedTarball(data: data,
                                                    encodedSignature: entry.signature,
                                                    destinationBinaryPath: uvBinaryPath) {
                outcome = .failed(message: error.localizedDescription)
            } else {
                // A newer uv embeds newer python-build-standalone metadata, so a minor
                // that was unavailable (and got remapped, e.g. 3.13->3.12) may now be
                // available. The .remaps records are a cache of resolutions made against
                // the OLD uv and are consulted unconditionally by the launch fast path, so
                // without this a remapped script would stay on the bumped minor forever.
                // Drop them so the next launch re-resolves against the new uv.
                invalidateSharedVenvRemaps()
                outcome = .upgraded(from: current, to: entry.uvVersion)
            }
        }
        return outcome
    }

    // Records invalidated by a uv upgrade are moved here rather than deleted, so an
    // OFFLINE launch whose re-resolution cannot build the newly-available minor can still
    // fall back to the venv the request previously resolved to. Consulted only on a build
    // failure (see provisionedStaleRemapInterpreter); the live fast path reads .remaps.
    private static let sharedVenvStaleRemapsDirectoryName = ".remaps-stale"

    // Invalidate recorded requested->resolved shared-venv remaps after a uv binary upgrade,
    // so stale resolutions do not pin scripts to a bumped Python minor the newer uv may now
    // provide directly. Move (not delete) them aside to .remaps-stale so an offline launch
    // that cannot build the now-available minor can still fall back. MERGE per file rather
    // than replacing the whole .remaps-stale directory: a second upgrade must not discard
    // records left by the first for scripts that were never relaunched in between (a rarely
    // used script plausibly skips a whole upgrade cycle). Missing dir is a no-op.
    private static func invalidateSharedVenvRemaps() {
        invalidateSharedVenvRemaps(venvsRoot: sharedVenvsRoot)
    }

    // venvsRoot is injected so the merge (which regressed twice) is hermetically testable.
    static func invalidateSharedVenvRemaps(venvsRoot: String) {
        let fm = FileManager.default
        let remapsDir = (venvsRoot as NSString).appendingPathComponent(sharedVenvRemapsDirectoryName)
        guard let entries = try? fm.contentsOfDirectory(atPath: remapsDir), !entries.isEmpty else {
            // Missing or empty: nothing fresh to invalidate. Drop an empty dir if present.
            try? fm.removeItem(atPath: remapsDir)
            return
        }
        let staleDir = (venvsRoot as NSString).appendingPathComponent(sharedVenvStaleRemapsDirectoryName)
        try? fm.createDirectory(atPath: staleDir, withIntermediateDirectories: true)
        for entry in entries {
            let source = (remapsDir as NSString).appendingPathComponent(entry)
            let destination = (staleDir as NSString).appendingPathComponent(entry)
            // The newer resolution wins for a same-named entry; other stale entries persist.
            try? fm.removeItem(atPath: destination)
            do {
                try fm.moveItem(atPath: source, toPath: destination)
            } catch {
                RLog("uv: could not stale remap record \(entry): \(error.localizedDescription)")
            }
        }
        // Drop the fresh dir so the live fast path stops consulting it, but ONLY if every
        // record moved: a record that failed to move is still here, and removing the dir
        // outright would delete it from both caches. Leaving it live is harmless (it keeps
        // its old pin until the next upgrade retries the merge).
        if let remaining = try? fm.contentsOfDirectory(atPath: remapsDir), remaining.isEmpty {
            try? fm.removeItem(atPath: remapsDir)
        }
        RLog("uv: merged \(entries.count) remap record(s) into the stale cache after a uv upgrade")
    }

    // A provisioned venv that a now-invalidated (stale) remap resolved this request to, or
    // nil. Consulted only when a fresh build fails (e.g. offline) so a previously-working
    // remapped script still launches; the resolved venv must still be fully provisioned.
    // venvsRoot is injected so this is hermetically testable, mirroring
    // provisionedSharedVenvInterpreter.
    static func provisionedStaleRemapInterpreter(forRequestedVersion requestedVersion: String,
                                                 venvsRoot: String) -> String? {
        guard let requestedMinor = normalizedMinor(requestedVersion) else {
            return nil
        }
        let fm = FileManager.default
        let stalePath = ((venvsRoot as NSString).appendingPathComponent(sharedVenvStaleRemapsDirectoryName) as NSString)
            .appendingPathComponent(requestedMinor)
        guard let data = fm.contents(atPath: stalePath),
              let resolvedMinor = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedMinor.isEmpty,
              sharedVenvIsProvisioned(forMinor: resolvedMinor, venvsRoot: venvsRoot) else {
            return nil
        }
        return sharedVenvInterpreterPath(forMinor: resolvedMinor, venvsRoot: venvsRoot)
    }

    static func provisionedStaleRemapInterpreter(forRequestedVersion requestedVersion: String) -> String? {
        return provisionedStaleRemapInterpreter(forRequestedVersion: requestedVersion, venvsRoot: sharedVenvsRoot)
    }

    // Upgrade the always-installed packages to the latest in every provisioned shared
    // basic-script venv. Full-environment scripts manage their own dependencies
    // (setup.cfg / Dependency Editor) and are intentionally left untouched. Runs on
    // provisionQueue so it never races a concurrent shared-venv build. Note: `uv pip
    // install --upgrade` is not transactional across the package set, so a mid-run
    // failure can leave one package upgraded and others not (retried next day), and it
    // can rewrite site-packages while a basic script is running from that venv; that is
    // accepted as low risk for a once-a-day background refresh.
    // Upgrade the always-installed modules in ONE shared venv. The caller decides how it
    // is scheduled on provisionQueue.
    private static func upgradeModulesInSharedVenv(minor: String, environment: [String: String]) {
        guard sharedVenvIsProvisioned(forMinor: minor) else {
            return
        }
        let interpreter = sharedVenvPython(forMinor: minor)
        if let error = run(uvBinaryPath,
                           iTermUvCommand.pipInstallArgs(venvPythonPath: interpreter,
                                                         packages: alwaysInstalledPackages,
                                                         upgrade: true),
                           environment) {
            RLog("uv: background module upgrade for the \(minor) venv failed: \(error.localizedDescription)")
        }
    }

    // The interpreter of the newest provisioned shared venv, or nil if none exists. An
    // offline fallback (e.g. the REPL) for when a specific requested version cannot be
    // provisioned but some iterm2-equipped venv is already on disk: legacy apython used
    // whatever runtime was installed rather than demanding one exact version.
    @objc func newestProvisionedSharedVenvInterpreter() -> String? {
        guard let newest = Self.provisionedSharedVenvMinors().max(by: {
            iTermDottedVersion.compare($0, $1) == .orderedAscending
        }) else {
            return nil
        }
        return Self.sharedVenvPython(forMinor: newest)
    }

    private static func provisionedSharedVenvMinors() -> [String] {
        let venvsRoot = (uvDirectory as NSString).appendingPathComponent("venvs")
        guard let minors = try? FileManager.default.contentsOfDirectory(atPath: venvsRoot) else {
            return []
        }
        return minors.filter { sharedVenvIsProvisioned(forMinor: $0) }
    }

    // Synchronous, one pass over every provisioned shared venv. Used by the user-invoked
    // check (the user is waiting, so occupying provisionQueue for the whole pass is fine).
    private static func upgradeSharedVenvModules() {
        let environment = mergedEnvironment(pythonInstallDir: pythonInstallDirectory, cacheDir: cacheDirectory)
        for minor in provisionedSharedVenvMinors() {
            upgradeModulesInSharedVenv(minor: minor, environment: environment)
        }
    }

    // Background daily refresh: upgrade one venv per provisionQueue item, and enqueue the
    // NEXT venv only after the current one finishes (self-scheduling), NOT all N up front.
    // provisionQueue is a serial FIFO queue that also serves user-visible work (script
    // launches, full-env provisioning, the Dependency Editor's pip calls). Bulk-enqueueing
    // would place a user request that arrives mid-refresh behind every remaining
    // network-bound `uv pip install --upgrade`. Chaining means such a request, submitted
    // while one venv is upgrading, is already ahead of the successor in FIFO order and runs
    // between venvs instead of after the whole refresh.
    private static func enqueuePeriodicSharedVenvModuleUpgrades() {
        let environment = mergedEnvironment(pythonInstallDir: pythonInstallDirectory, cacheDir: cacheDirectory)
        scheduleSharedVenvModuleUpgrade(minors: provisionedSharedVenvMinors(), index: 0, environment: environment)
    }

    private static func scheduleSharedVenvModuleUpgrade(minors: [String], index: Int, environment: [String: String]) {
        guard index < minors.count else {
            return
        }
        provisionQueue.async {
            upgradeModulesInSharedVenv(minor: minors[index], environment: environment)
            scheduleSharedVenvModuleUpgrade(minors: minors, index: index + 1, environment: environment)
        }
    }

    // The code used by user-cancellation errors, so callers can distinguish “the
    // user clicked Cancel” (stay silent) from a real failure (show an alert). Any
    // other code in this domain is a genuine failure.
    @objc static let cancelErrorCode = -2

    static func error(_ message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: -1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    // A failure that represents the user declining/canceling the download. Callers
    // treat this as a silent no-op rather than reporting an installation failure.
    static func cancelError() -> NSError {
        return NSError(domain: errorDomain,
                       code: cancelErrorCode,
                       userInfo: [NSLocalizedDescriptionKey: "The download was canceled."])
    }

    // Whether an error is the user-cancellation sentinel (so ObjC callers can stay
    // silent instead of showing “Installation Failed / file a bug report”).
    @objc static func isCancelationError(_ error: NSError) -> Bool {
        return error.domain == errorDomain && error.code == cancelErrorCode
    }

    // Synchronously download up to maxBytes from url, or nil on error / oversize. The
    // transfer is canceled as soon as the accumulated bytes exceed the cap, so a host
    // that serves far more than it declared cannot exhaust memory. Blocks, so call it
    // off the main thread. The byte cap does not bound time, so also set a resource
    // timeout: on the user-visible path this call runs on provisionQueue (via
    // fetchSelectedEntry in downloadIfNeeded), and a host trickling bytes slower than
    // the idle timeout would otherwise wedge every launch/provision indefinitely.
    // resourceTimeout caps the ENTIRE transfer. That is right for the tiny manifest on
    // the user-visible provisionQueue (a host trickling bytes must not wedge every
    // launch), but wrong for the ~37 MB uv tarball: a total cap of 120 s means any link
    // below ~2.5 Mbps fails every upgrade forever, so a broken installed uv could never
    // self-heal. For the tarball, pass a generous resourceTimeout and rely on the idle
    // (per-request) timeout to catch a truly stalled connection instead.
    static func boundedDownload(from url: URL, maxBytes: Int, resourceTimeout: TimeInterval = 120) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false
        let delegate = iTermBoundedDownloadDelegate(maxBytes: maxBytes) { ok in
            succeeded = ok
            semaphore.signal()
        }
        let configuration = URLSessionConfiguration.ephemeral
        // Idle timeout: fail if no bytes arrive for this long. Bounds a stalled transfer
        // without penalizing a slow-but-progressing one.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = resourceTimeout
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        session.dataTask(with: url).resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()
        return succeeded ? delegate.data : nil
    }
}

// URLSession delegate for boundedDownload: accumulates the body and cancels the moment
// it exceeds maxBytes. All delegate callbacks arrive on one serial queue, and the
// completion is signaled from didComplete, so the caller reads `data` only after the
// transfer has ended.
private final class iTermBoundedDownloadDelegate: NSObject, URLSessionDataDelegate {
    private let maxBytes: Int
    private let completion: (Bool) -> Void
    fileprivate private(set) var data = Data()
    private var overflowed = false
    private var finished = false

    init(maxBytes: Int, completion: @escaping (Bool) -> Void) {
        self.maxBytes = maxBytes
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !overflowed else {
            return
        }
        data.append(chunk)
        if data.count > maxBytes {
            overflowed = true
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else {
            return
        }
        finished = true
        completion(error == nil && !overflowed)
    }
}

// Default fetcher: reuses the optional-component download window controller for the
// network download and its progress UI. Not unit-tested (thin UI integration);
// exercised on device / by review and by the live install test.
final class iTermUvWindowControllerFetcher: iTermUvTarballFetcher {
    private var controller: iTermOptionalComponentDownloadWindowController?

    func fetch(url: URL, title: String, byteCount: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        // Clamp the declared size to a sane range before any arithmetic. The one real
        // caller passes a manifest size already validated to (0, maxTarballBytes], but
        // this protocol method must not overflow (crash) or under/over-cap on a bogus
        // value from any future caller.
        let declaredSize = min(max(byteCount, 0), iTermUvProvisioner.maxTarballBytes)
        // Ask before downloading, like the legacy runtime download did.
        let megabytes = max(1, (declaredSize + 512 * 1024) / (1024 * 1024))
        let alert = NSAlert()
        alert.messageText = String(localized: "UvProvisioner.DownloadTitle", defaultValue: "Download Python Support?", comment: "Title of the dialog asking permission to download the Python runtime")
        alert.informativeText = String(localized: "UvProvisioner.DownloadBody", defaultValue: "To run Python scripts, iTerm2 needs to download uv (about \(megabytes) MB) and a Python interpreter. Additional Python versions are downloaded automatically later if a script needs them. OK to download it now?", comment: "Body of the dialog asking permission to download the Python runtime")
        alert.addButton(withTitle: iTermLocalizedOK())
        alert.addButton(withTitle: iTermLocalizedCancel())
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(.failure(iTermUvProvisioner.cancelError()))
            return
        }

        let controller = iTermOptionalComponentDownloadWindowController(
            windowNibName: "iTermOptionalComponentDownloadWindowController")
        self.controller = controller

        var downloadedData: Data?
        var overflowed = false
        // Cap the in-memory accumulation at the (clamped) declared size plus generous
        // slack, so a manipulated size or a runaway response cannot exhaust memory. A
        // zero/absent declared size falls back to the absolute ceiling rather than an
        // unbounded Int.max so the cap is never disabled.
        let maxBytes = declaredSize > 0
            ? declaredSize + 16 * 1024 * 1024
            : iTermUvProvisioner.maxTarballBytes + 16 * 1024 * 1024
        let phase = iTermOptionalComponentDownloadPhase(
            url: url,
            title: title,
            nextPhaseFactory: { completedPhase in
                if let stream = completedPhase?.stream {
                    if let data = Self.readStream(stream, maxBytes: maxBytes) {
                        downloadedData = data
                    } else {
                        overflowed = true
                    }
                }
                return nil  // end the chain; the controller's completion reports the result
            })

        controller.completion = { [weak self] finalPhase in
            self?.controller?.window?.close()
            self?.controller = nil
            if let phaseError = finalPhase?.error as NSError? {
                // Canceling the in-progress download window reports com.iterm2 -999.
                // Translate it to the cancel sentinel so callers stay silent instead of
                // showing "Installation Failed ... error -999".
                if phaseError.domain == "com.iterm2" && phaseError.code == -999 {
                    completion(.failure(iTermUvProvisioner.cancelError()))
                } else {
                    completion(.failure(phaseError))
                }
            } else if overflowed {
                completion(.failure(iTermUvProvisioner.error("The uv download was larger than expected and was rejected.")))
            } else if let data = downloadedData {
                completion(.success(data))
            } else {
                completion(.failure(iTermUvProvisioner.error("The uv download produced no data.")))
            }
        }
        controller.window?.makeKeyAndOrderFront(nil)
        controller.begin(phase)
    }

    // Read the whole stream into memory, or nil if it exceeds maxBytes (refusing to
    // buffer an unexpectedly large download).
    private static func readStream(_ stream: InputStream, maxBytes: Int) -> Data? {
        if stream.streamStatus == .notOpen {
            stream.open()
        }
        defer { stream.close() }
        var data = Data()
        let capacity = 1 << 16
        var buffer = [UInt8](repeating: 0, count: capacity)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: capacity)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
            if data.count > maxBytes {
                return nil
            }
        }
        return data
    }
}
