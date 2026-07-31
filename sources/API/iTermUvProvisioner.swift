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
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .failure(error("Could not download the uv manifest from \(urlString)."))
        }
        return selectedEntry(fromManifestData: data, runningMacOSVersion: runningMacOSVersionString())
    }

    // The pure parse -> select -> floor step, split from the network fetch so it is
    // unit-testable with crafted manifest bytes (no network, no real uv).
    static func selectedEntry(fromManifestData data: Data,
                              runningMacOSVersion: String) -> Result<iTermUvManifestEntry, Error> {
        guard let entries = iTermUvManifest.parse(data) else {
            return .failure(error("The uv manifest could not be parsed."))
        }
        guard let entry = iTermUvManifest.select(entries: entries,
                                                 runningMacOSVersion: runningMacOSVersion) else {
            return .failure(error("uv is not available for this version of macOS."))
        }
        // The manifest itself is not signed (only the tarball is), so a compromised
        // host could offer an older, still-validly-signed uv (a rollback). Refuse any
        // build older than the minimum the app requires.
        guard iTermDottedVersion.compare(entry.uvVersion, minimumUvVersion) != .orderedAscending else {
            return .failure(error("The offered uv version (\(entry.uvVersion)) is older than the minimum required (\(minimumUvVersion))."))
        }
        return .success(entry)
    }

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
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempPath)
            if fm.fileExists(atPath: destinationBinaryPath) {
                _ = try fm.replaceItemAt(URL(fileURLWithPath: destinationBinaryPath),
                                         withItemAt: URL(fileURLWithPath: tempPath))
            } else {
                try fm.moveItem(atPath: tempPath, toPath: destinationBinaryPath)
            }
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
        do {
            try data.write(to: URL(fileURLWithPath: tempFile))
            defer { try? FileManager.default.removeItem(atPath: tempFile) }
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
        _ = runner.blockingRun()
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

        let venvPath = (container as NSString).appendingPathComponent(iTermScriptRuntime.venvDirectoryName)
        if let error = run(uvPath,
                           iTermUvCommand.venvArgs(pythonVersion: resolved.version, venvPath: venvPath),
                           environment) {
            return .failure(error)
        }

        let venvPython = (venvPath as NSString).appendingPathComponent("bin/python")
        // The always-installed packages (iterm2, certifi, pyobjc) come in addition to
        // the script's declared dependencies.
        let packages = orderedUnique(dependencies + alwaysInstalledPackages)
        if let error = run(uvPath,
                           iTermUvCommand.pipInstallArgs(venvPythonPath: venvPython, packages: packages),
                           environment) {
            return .failure(error)
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
        _ = runner.blockingRun()
        guard let output = runner.output else {
            return []
        }
        return iTermUvPythonVersion.availableMinors(fromListJSON: output)
    }

    private static func mergedEnvironment(pythonInstallDir: String, cacheDir: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in iTermUvCommand.provisionEnvironment(pythonInstallDir: pythonInstallDir, cacheDir: cacheDir) {
            environment[key] = value
        }
        return environment
    }

    private static func run(_ path: String, _ arguments: [String], _ environment: [String: String]) -> NSError? {
        let runner = iTermBufferedCommandRunner(command: path, withArguments: arguments, path: NSTemporaryDirectory())
        runner.environment = environment
        let status = runner.blockingRun()
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
                    self.fetcher.fetch(url: url, title: "Downloading uv…", byteCount: entry.size) { result in
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

    // Download uv if needed, then provision a full-environment script's .venv. The
    // completion runs on the main queue with nil on success or an error. Callable
    // from the Obj-C create/import paths.
    @objc func downloadAndProvisionFullEnvironment(container: String,
                                                   requestedPythonVersion: String,
                                                   dependencies: [String],
                                                   createSetupCfg: Bool,
                                                   completion: @escaping (NSError?) -> Void) {
        // downloadIfNeeded fetches the manifest and reports "not available for this
        // macOS" if no compatible uv build exists, so no separate check is needed.
        downloadIfNeeded { error in
            if let error = error {
                completion(error as NSError)
                return
            }
            Self.provisionQueue.async {
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
                        iTermSetupCfgParser.writeSetupCfg(
                            toFile: (container as NSString).appendingPathComponent("setup.cfg"),
                            name: (container as NSString).lastPathComponent,
                            dependencies: dependencies,
                            ensureiTerm2Present: true,
                            pythonVersion: marker.python,
                            environmentVersion: Int(iTermMinimumPythonEnvironmentVersion))
                    }
                    // If uv could not provide the script's pinned Python version and had
                    // to bump it, tell the user (once, suppressibly). Every provisioning
                    // path (create, import, migrate) funnels through here.
                    if let from = marker.remappedFrom {
                        Self.reportForcedRemap(container: container, from: from, to: marker.python)
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
    // decision 7 / Phase 3. Called off the main thread.
    private static func reportForcedRemap(container: String, from: String, to: String) {
        let scriptName = (container as NSString).lastPathComponent
        let remap = iTermUvPythonRemap(scriptName: scriptName,
                                       fromVersion: iTermUvPythonVersion.twoPartVersion(from),
                                       toVersion: to)
        let text = iTermUvMigration.consolidatedWarningText(remaps: [remap])
        RLog("uv: \(text)")
        DispatchQueue.main.async {
            iTermScriptHistoryEntry.global().addOutput(text + "\n", completion: {})
            iTermWarning.show(withTitle: text,
                              actions: ["OK"],
                              accessory: nil,
                              identifier: "NoSyncUvForcedPythonRemap",
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Python Version Changed",
                              window: nil)
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
                                            createSetupCfg: false) { error in
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
            let status = runner.blockingRun()
            let output = runner.output ?? Data()
            DispatchQueue.main.async { completion(status == 0, output) }
        }
    }

    // MARK: - Shared basic-script venvs

    @objc static func sharedVenvDirectory(forMinor minor: String) -> String {
        return ((uvDirectory as NSString).appendingPathComponent("venvs") as NSString)
            .appendingPathComponent(minor)
    }

    @objc static func sharedVenvPython(forMinor minor: String) -> String {
        return (sharedVenvDirectory(forMinor: minor) as NSString).appendingPathComponent("bin/python")
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

    static func sharedVenvIsProvisioned(forMinor minor: String) -> Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: sharedVenvPython(forMinor: minor)) &&
               fm.fileExists(atPath: sharedVenvMarkerPath(forMinor: minor))
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
        // Fast path: if the requested version is already a bare minor whose venv is
        // fully provisioned, return its interpreter without downloading uv, running
        // `uv python list`, or touching the network. This is the common repeat-launch
        // case; only a first launch (or a remapped version) falls through to uv.
        if let minor = Self.normalizedMinor(requestedPythonVersion),
           Self.sharedVenvIsProvisioned(forMinor: minor) {
            completion(nil, Self.sharedVenvPython(forMinor: minor))
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

                // Re-check with the marker (not just the interpreter) in case a
                // concurrent launch finished, or a prior attempt left a half-built venv.
                if Self.sharedVenvIsProvisioned(forMinor: resolved.version) {
                    DispatchQueue.main.async { completion(nil, interpreter) }
                    return
                }
                let venvDirectory = Self.sharedVenvDirectory(forMinor: resolved.version)
                // Start from a clean directory so a previously interrupted build can't
                // leave stray files behind.
                try? FileManager.default.removeItem(atPath: venvDirectory)
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.venvArgs(pythonVersion: resolved.version, venvPath: venvDirectory),
                                        environment) {
                    try? FileManager.default.removeItem(atPath: venvDirectory)
                    DispatchQueue.main.async { completion(error, nil) }
                    return
                }
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.pipInstallArgs(venvPythonPath: interpreter, packages: Self.alwaysInstalledPackages),
                                        environment) {
                    // Do not leave a half-built venv: the interpreter exists but the
                    // packages do not, and every later launch would trust it.
                    try? FileManager.default.removeItem(atPath: venvDirectory)
                    DispatchQueue.main.async { completion(error, nil) }
                    return
                }
                Self.markSharedVenvProvisioned(forMinor: resolved.version)
                DispatchQueue.main.async { completion(nil, interpreter) }
            }
        }
    }

    private static func markSharedVenvProvisioned(forMinor minor: String) {
        try? Data().write(to: URL(fileURLWithPath: sharedVenvMarkerPath(forMinor: minor)))
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
        guard Self.isInstalled else {
            return
        }
        Self.upgradeRateLimit.performRateLimitedBlock {
            Self.provisionQueue.async {
                Self.upgradeUvBinaryIfNewerAvailable()
                Self.upgradeSharedVenvModules()
            }
        }
    }

    // Re-fetch the manifest and, if it offers a newer uv than installed, download and
    // install it (RSA-verified, atomic replace). Silent: the user already consented to
    // uv, so there is no confirmation window. Any failure (offline, older manifest) is
    // a no-op retried next time. The minimum-version floor still applies via
    // fetchSelectedEntry, so this never installs an older uv.
    private static func upgradeUvBinaryIfNewerAvailable() {
        guard case .success(let entry) = fetchSelectedEntry() else {
            return
        }
        let installed = installedUvVersion(uvPath: uvBinaryPath)
        guard shouldUpgradeUv(installedVersion: installed, manifestVersion: entry.uvVersion) else {
            return
        }
        guard let url = URL(string: entry.url), let data = try? Data(contentsOf: url) else {
            return
        }
        if let error = installDownloadedTarball(data: data,
                                                encodedSignature: entry.signature,
                                                destinationBinaryPath: uvBinaryPath) {
            RLog("uv: background upgrade to \(entry.uvVersion) failed: \(error.localizedDescription)")
        } else {
            RLog("uv: upgraded uv from \(installed) to \(entry.uvVersion)")
        }
    }

    // Upgrade the always-installed packages to the latest in every provisioned shared
    // basic-script venv. Full-environment scripts manage their own dependencies
    // (setup.cfg / Dependency Editor) and are intentionally left untouched.
    private static func upgradeSharedVenvModules() {
        let venvsRoot = (uvDirectory as NSString).appendingPathComponent("venvs")
        guard let minors = try? FileManager.default.contentsOfDirectory(atPath: venvsRoot) else {
            return
        }
        let environment = mergedEnvironment(pythonInstallDir: pythonInstallDirectory, cacheDir: cacheDirectory)
        for minor in minors where sharedVenvIsProvisioned(forMinor: minor) {
            let interpreter = sharedVenvPython(forMinor: minor)
            if let error = run(uvBinaryPath,
                               iTermUvCommand.pipInstallArgs(venvPythonPath: interpreter,
                                                             packages: alwaysInstalledPackages,
                                                             upgrade: true),
                               environment) {
                RLog("uv: background module upgrade for the \(minor) venv failed: \(error.localizedDescription)")
            }
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
}

// Default fetcher: reuses the optional-component download window controller for the
// network download and its progress UI. Not unit-tested (thin UI integration);
// exercised on device / by review and by the live install test.
final class iTermUvWindowControllerFetcher: iTermUvTarballFetcher {
    private var controller: iTermOptionalComponentDownloadWindowController?

    func fetch(url: URL, title: String, byteCount: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        // Ask before downloading, like the legacy runtime download did.
        let megabytes = max(1, (byteCount + 512 * 1024) / (1024 * 1024))
        let alert = NSAlert()
        alert.messageText = "Download Python Support?"
        alert.informativeText = "To run Python scripts, iTerm2 needs to download uv "
            + "(about \(megabytes) MB) and a Python interpreter. Additional Python "
            + "versions are downloaded automatically later if a script needs them. "
            + "OK to download it now?"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(.failure(iTermUvProvisioner.cancelError()))
            return
        }

        let controller = iTermOptionalComponentDownloadWindowController(
            windowNibName: "iTermOptionalComponentDownloadWindowController")
        self.controller = controller

        var downloadedData: Data?
        var overflowed = false
        // Cap the in-memory accumulation at the manifest-declared size plus generous
        // slack, so a manipulated size or a runaway response cannot exhaust memory.
        let maxBytes = byteCount > 0 ? byteCount + 16 * 1024 * 1024 : Int.max
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
            if let phaseError = finalPhase?.error {
                completion(.failure(phaseError))
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
