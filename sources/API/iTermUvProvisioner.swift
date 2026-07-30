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
        fetcher.fetch(url: url, title: "Downloading uv…") { result in
            switch result {
            case .failure(let error):
                finish(error)
            case .success(let data):
                DispatchQueue.global(qos: .userInitiated).async {
                    finish(Self.installDownloadedTarball(data: data,
                                                         entry: entry,
                                                         destinationBinaryPath: Self.uvBinaryPath))
                }
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
