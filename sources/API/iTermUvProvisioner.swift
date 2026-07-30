//
//  iTermUvProvisioner.swift
//  iTerm2SharedARC
//
//  Phase 1 of the uv Python-runtime migration. Downloads, verifies, extracts, and
//  installs the uv binary. The network fetch is behind an injectable protocol
//  (iTermUvTarballFetcher) so later phases and tests can provision without hitting
//  the network; the default fetcher reuses the optional-component download window
//  controller for progress UI. Trust is a pinned SHA-256 for the development
//  source (Astral's unsigned tarball); RSA verification via iTermSignatureVerifier
//  is added when hosting moves to iterm2.com. No path ever skips verification.
//  See docs/uv-python-runtime-migration.md (Phase 1).
//

import Foundation

// The network fetch step, isolated so it can be faked in tests / later phases.
protocol iTermUvTarballFetcher: AnyObject {
    // Download the tarball at url, showing progress titled `title`. Completion may
    // run on any queue.
    func fetch(url: URL, title: String, completion: @escaping (Result<Data, Error>) -> Void)
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

    init(fetcher: iTermUvTarballFetcher) {
        self.fetcher = fetcher
        super.init()
    }

    @objc override convenience init() {
        self.init(fetcher: iTermUvWindowControllerFetcher())
    }

    // Development manifest: a single pinned, SHA-256-verified uv build. When
    // hosting moves to iterm2.com this is replaced by a manifest fetched over the
    // network whose entries carry RSA signatures. The macOS bracket is honored via
    // iTermUvManifest.select so a future uv that raises its floor never strands an
    // older-macOS user.
    static let devManifest: [iTermUvManifestEntry] = [
        iTermUvManifestEntry(
            uvVersion: "0.12.0",
            url: "https://releases.astral.sh/github/uv/releases/download/0.12.0/uv-aarch64-apple-darwin.tar.gz",
            signature: "2b9e582af54f84fa50c115427451a6c13e80f43b52f8282b8af5791077317bbf",
            size: 17387877,
            minimumMacOSVersion: "13.0",
            maximumMacOSVersion: nil),
    ]

    // The uv build to use for the given running macOS ("major.minor"), or nil if
    // none is compatible.
    static func selectedEntry(forMacOSVersion macOSVersion: String) -> iTermUvManifestEntry? {
        return iTermUvManifest.select(entries: devManifest, runningMacOSVersion: macOSVersion)
    }

    static func runningMacOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    // MARK: - On-disk layout

    private static var uvDirectory: String {
        let appSupport = FileManager.default.spacelessAppSupportCreatingLink() ?? NSTemporaryDirectory()
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
        if fm.fileExists(atPath: destinationBinaryPath) {
            try fm.removeItem(atPath: destinationBinaryPath)
        }
        try fm.copyItem(atPath: source, toPath: destinationBinaryPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationBinaryPath)
    }

    // Verify the pinned SHA-256, then extract the tarball and install the binary.
    // Returns nil on success or an error describing the first failure. Verification
    // happens on the in-memory bytes before anything is written, and the same bytes
    // are extracted, so there is no time-of-check/time-of-use gap.
    static func installDownloadedTarball(data: Data,
                                         entry: iTermUvManifestEntry,
                                         destinationBinaryPath: String) -> Error? {
        guard iTermUvDownload.matchesSHA256(data: data, expectedHex: entry.signature) else {
            return error("The downloaded uv binary failed its integrity check.")
        }
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

    // MARK: - Full-environment provisioning (runs uv; integration-tested live)

    // The full environment uv builds under a script container: a .venv plus the
    // python-runtime.json marker. iterm2 and certifi are always installed. Returns
    // the marker on success (its remappedFrom tells the caller whether to warn the
    // user that the Python version changed), or an error.
    static func provisionFullEnvironment(uvPath: String,
                                         uvVersion: String,
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
        // iterm2 (the API module) and certifi (TLS roots for user scripts) are always
        // present, in addition to the script's declared dependencies.
        let packages = orderedUnique(dependencies + ["iterm2", "certifi"])
        if let error = run(uvPath,
                           iTermUvCommand.pipInstallArgs(venvPythonPath: venvPython, packages: packages),
                           environment) {
            return .failure(error)
        }

        let marker = iTermPythonRuntimeMarker(uvVersion: uvVersion,
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
        guard let entry = Self.selectedEntry(forMacOSVersion: Self.runningMacOSVersionString()),
              let url = URL(string: entry.url) else {
            finish(Self.error("uv is not available for this version of macOS."))
            return
        }

        // Coalesce concurrent downloads: only the first caller starts the fetch; the
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
        fetcher.fetch(url: url, title: "Downloading uv…") { result in
            switch result {
            case .failure(let error):
                deliver(error)
            case .success(let data):
                Self.provisionQueue.async {
                    deliver(Self.installDownloadedTarball(data: data,
                                                          entry: entry,
                                                          destinationBinaryPath: Self.uvBinaryPath))
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
        guard let entry = Self.selectedEntry(forMacOSVersion: Self.runningMacOSVersionString()) else {
            completion(Self.error("uv is not available for this version of macOS."))
            return
        }
        downloadIfNeeded { error in
            if let error = error {
                completion(error as NSError)
                return
            }
            Self.provisionQueue.async {
                let result = Self.provisionFullEnvironment(uvPath: Self.uvBinaryPath,
                                                           uvVersion: entry.uvVersion,
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
                    resultError = nil
                case .failure(let error):
                    resultError = error as NSError
                }
                DispatchQueue.main.async { completion(resultError) }
            }
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

    // Ensure a shared venv (with iterm2 + certifi) exists for the resolved minor of
    // requestedPythonVersion, downloading uv and provisioning it if needed, and
    // return that venv's interpreter. Basic scripts share this per-minor, so once it
    // exists a launch is a bare exec with no uv and no network. Completion runs on
    // the main queue.
    @objc func downloadAndProvisionSharedVenv(requestedPythonVersion: String,
                                              completion: @escaping (NSError?, String?) -> Void) {
        guard Self.selectedEntry(forMacOSVersion: Self.runningMacOSVersionString()) != nil else {
            completion(Self.error("uv is not available for this version of macOS."), nil)
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

                if FileManager.default.isExecutableFile(atPath: interpreter) {
                    DispatchQueue.main.async { completion(nil, interpreter) }
                    return
                }
                let venvDirectory = Self.sharedVenvDirectory(forMinor: resolved.version)
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.venvArgs(pythonVersion: resolved.version, venvPath: venvDirectory),
                                        environment) {
                    DispatchQueue.main.async { completion(error, nil) }
                    return
                }
                if let error = Self.run(Self.uvBinaryPath,
                                        iTermUvCommand.pipInstallArgs(venvPythonPath: interpreter, packages: ["iterm2", "certifi"]),
                                        environment) {
                    DispatchQueue.main.async { completion(error, nil) }
                    return
                }
                DispatchQueue.main.async { completion(nil, interpreter) }
            }
        }
    }

    static func error(_ message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: -1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// Default fetcher: reuses the optional-component download window controller for the
// network download and its progress UI. Not unit-tested (thin UI integration);
// exercised on device / by review and by the live install test.
final class iTermUvWindowControllerFetcher: iTermUvTarballFetcher {
    private var controller: iTermOptionalComponentDownloadWindowController?

    func fetch(url: URL, title: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let controller = iTermOptionalComponentDownloadWindowController(
            windowNibName: "iTermOptionalComponentDownloadWindowController")
        self.controller = controller

        var downloadedData: Data?
        let phase = iTermOptionalComponentDownloadPhase(
            url: url,
            title: title,
            nextPhaseFactory: { completedPhase in
                if let stream = completedPhase?.stream {
                    downloadedData = Self.readStream(stream)
                }
                return nil  // end the chain; the controller's completion reports the result
            })

        controller.completion = { [weak self] finalPhase in
            self?.controller?.window?.close()
            self?.controller = nil
            if let phaseError = finalPhase?.error {
                completion(.failure(phaseError))
            } else if let data = downloadedData {
                completion(.success(data))
            } else {
                completion(.failure(iTermUvProvisioner.error("The uv download produced no data.")))
            }
        }
        controller.window?.makeKeyAndOrderFront(nil)
        controller.begin(phase)
    }

    private static func readStream(_ stream: InputStream) -> Data {
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
        }
        return data
    }
}
