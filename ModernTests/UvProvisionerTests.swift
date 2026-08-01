//
//  UvProvisionerTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. The provisioner downloads (from the
//  iterm2.com manifest), RSA-verifies, extracts, and installs the uv binary. The
//  risk-bearing filesystem logic (locating the binary and placing it executable, and
//  extraction) is unit-tested hermetically here; RSA verification cannot be tested
//  for success without the private key, so the full manifest->download->verify->
//  install path is a skip-guarded live test against the real hosted build (Tier B).
//  See docs/uv-python-runtime-migration.md (Phase 1).
//

import XCTest
@testable import iTerm2SharedARC

final class UvProvisionerTests: XCTestCase {
    private func makeTempDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("uvtest-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func writeFile(_ path: String, _ contents: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - locateUvBinary

    func testLocateFindsBinaryInSubdirectory() throws {
        // The tarball extracts to uv-<arch>-apple-darwin/uv, so the binary is one
        // level down, not at the root.
        let dir = try makeTempDir()
        let nested = (dir as NSString).appendingPathComponent("uv-universal2-apple-darwin/uv")
        try writeFile(nested, "binary")
        XCTAssertEqual(iTermUvProvisioner.locateUvBinary(inDirectory: dir), nested)
    }

    func testLocateFindsBinaryAtTopLevel() throws {
        let dir = try makeTempDir()
        let direct = (dir as NSString).appendingPathComponent("uv")
        try writeFile(direct, "binary")
        XCTAssertEqual(iTermUvProvisioner.locateUvBinary(inDirectory: dir), direct)
    }

    func testLocateReturnsNilWhenAbsent() throws {
        let dir = try makeTempDir()
        XCTAssertNil(iTermUvProvisioner.locateUvBinary(inDirectory: dir))
    }

    // MARK: - install

    func testInstallPlacesBinaryExecutable() throws {
        let staging = try makeTempDir()
        let src = (staging as NSString).appendingPathComponent("uv-universal2-apple-darwin/uv")
        try writeFile(src, "#!/bin/sh\necho uv\n")
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")

        try iTermUvProvisioner.install(fromExtractedDirectory: staging, to: dest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest))
        let perms = try FileManager.default.attributesOfItem(atPath: dest)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "#!/bin/sh\necho uv\n")
    }

    func testInstallOverwritesExisting() throws {
        let staging = try makeTempDir()
        try writeFile((staging as NSString).appendingPathComponent("uv-x/uv"), "new")
        let destDir = try makeTempDir()
        let dest = (destDir as NSString).appendingPathComponent("uv/bin/uv")
        // Simulate the recovery scenario: a non-executable (0644) partial left by an
        // earlier interrupted attempt. The reinstall must end up executable, or
        // isInstalled would stay false forever and re-download every launch.
        try writeFile(dest, "old")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest)

        try iTermUvProvisioner.install(fromExtractedDirectory: staging, to: dest)
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest))
        let perms = try FileManager.default.attributesOfItem(atPath: dest)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
    }

    func testInstallThrowsWhenBinaryMissing() throws {
        let staging = try makeTempDir()  // empty
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        XCTAssertThrowsError(try iTermUvProvisioner.install(fromExtractedDirectory: staging, to: dest))
    }

    func testBinaryDestinationShape() {
        XCTAssertTrue(iTermUvProvisioner.uvBinaryPath.hasSuffix("/uv/bin/uv"),
                      "unexpected uv path: \(iTermUvProvisioner.uvBinaryPath)")
    }

    // MARK: - parseUvVersion

    func testParseUvVersion() {
        XCTAssertEqual(iTermUvProvisioner.parseUvVersion(fromVersionOutput: "uv 0.12.0 (abc 2026-01-01)"), "0.12.0")
        XCTAssertEqual(iTermUvProvisioner.parseUvVersion(fromVersionOutput: "uv 0.13.1\n"), "0.13.1")
        XCTAssertEqual(iTermUvProvisioner.parseUvVersion(fromVersionOutput: "garbage"), "unknown")
    }

    // MARK: - Manifest selection and upgrade decision (background upgrade, [7])

    private func manifestData(_ entries: [(uv: String, minMacOS: String, maxMacOS: String?)]) -> Data {
        let objects = entries.map { entry -> String in
            let maxField = entry.maxMacOS.map { "\"\($0)\"" } ?? "null"
            return """
            { "uv_version": "\(entry.uv)", "url": "https://x/uv-\(entry.uv).tar.gz",
              "signature": "sig", "size": 1,
              "minimum_macos_version": "\(entry.minMacOS)", "maximum_macos_version": \(maxField) }
            """
        }
        return "[\(objects.joined(separator: ","))]".data(using: .utf8)!
    }

    func testSelectedEntryPicksNewestCompatible() {
        let data = manifestData([("0.12.0", "13.0", nil), ("0.13.0", "13.0", nil)])
        switch iTermUvProvisioner.selectedEntry(fromManifestData: data, runningMacOSVersion: "14.1.0") {
        case .success(let entry): XCTAssertEqual(entry.uvVersion, "0.13.0")
        case .failure(let error): XCTFail("unexpected failure: \(error)")
        }
    }

    func testSelectedEntryRejectsVersionBelowFloor() {
        // 0.11.0 is below iTermUvProvisioner.minimumUvVersion (0.12.0): a rollback the
        // background upgrade / install must refuse even though it parses and matches OS.
        let data = manifestData([("0.11.0", "13.0", nil)])
        switch iTermUvProvisioner.selectedEntry(fromManifestData: data, runningMacOSVersion: "14.1.0") {
        case .success: XCTFail("must reject a version below the minimum floor")
        case .failure: break
        }
    }

    func testSelectedEntryRejectsIncompatibleMacOS() {
        let data = manifestData([("0.13.0", "26.0", nil)])
        switch iTermUvProvisioner.selectedEntry(fromManifestData: data, runningMacOSVersion: "13.4.0") {
        case .success: XCTFail("must reject when the running OS is below the entry minimum")
        case .failure: break
        }
    }

    func testSelectedEntryFailsOnGarbageManifest() {
        switch iTermUvProvisioner.selectedEntry(fromManifestData: Data("not json".utf8),
                                                runningMacOSVersion: "14.0.0") {
        case .success: XCTFail("must fail to parse")
        case .failure: break
        }
    }

    func testShouldUpgradeUvOnlyWhenStrictlyNewer() {
        XCTAssertTrue(iTermUvProvisioner.shouldUpgradeUv(installedVersion: "0.12.0", manifestVersion: "0.13.0"))
        XCTAssertTrue(iTermUvProvisioner.shouldUpgradeUv(installedVersion: "0.12.0", manifestVersion: "0.12.1"))
        XCTAssertFalse(iTermUvProvisioner.shouldUpgradeUv(installedVersion: "0.12.0", manifestVersion: "0.12.0"))
        XCTAssertFalse(iTermUvProvisioner.shouldUpgradeUv(installedVersion: "0.13.0", manifestVersion: "0.12.0"))
    }

    func testShouldUpgradeUvTreatsUnknownInstalledAsUpgradable() {
        // A failed `uv --version` yields "unknown"; a real manifest version must win so
        // a broken/unreadable binary self-heals on the next background check.
        XCTAssertTrue(iTermUvProvisioner.shouldUpgradeUv(installedVersion: "unknown", manifestVersion: "0.12.0"))
    }

    private func sizedManifest(uv: String, size: Int64) -> Data {
        return """
        [ { "uv_version": "\(uv)", "url": "https://x/uv.tar.gz", "signature": "s",
            "size": \(size), "minimum_macos_version": "13.0", "maximum_macos_version": null } ]
        """.data(using: .utf8)!
    }

    func testSelectedEntryRejectsZeroSize() {
        // size 0 previously disabled the download cap entirely.
        switch iTermUvProvisioner.selectedEntry(fromManifestData: sizedManifest(uv: "0.13.0", size: 0),
                                                runningMacOSVersion: "14.0.0") {
        case .success: XCTFail("must reject a zero size")
        case .failure: break
        }
    }

    func testSelectedEntryRejectsImplausiblyLargeSize() {
        switch iTermUvProvisioner.selectedEntry(fromManifestData: sizedManifest(uv: "0.13.0", size: 999_999_999_999),
                                                runningMacOSVersion: "14.0.0") {
        case .success: XCTFail("must reject an implausibly large size")
        case .failure: break
        }
    }

    func testSelectedEntryAcceptsVersionEqualToFloor() {
        // The minimum-version floor is inclusive: exactly minimumUvVersion is allowed.
        switch iTermUvProvisioner.selectedEntry(fromManifestData: sizedManifest(uv: "0.12.0", size: 1000),
                                                runningMacOSVersion: "14.0.0") {
        case .success(let entry): XCTAssertEqual(entry.uvVersion, "0.12.0")
        case .failure(let error): XCTFail("floor should be inclusive: \(error)")
        }
    }

    // MARK: - Offline shared-venv resolution (remapped shebang, item 2)

    private func provisionVenv(_ minor: String, inRoot root: String) throws -> String {
        let python = ((root as NSString).appendingPathComponent(minor) as NSString).appendingPathComponent("bin/python")
        try writeFile(python, "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python)
        try writeFile(((root as NSString).appendingPathComponent(minor) as NSString).appendingPathComponent(".provisioned"), "")
        return python
    }

    func testProvisionedSharedVenvInterpreterFollowsRemap() throws {
        let root = try makeTempDir()
        let py39 = try provisionVenv("3.9", inRoot: root)
        // Record that a requested 3.7 maps to the provisioned 3.9 venv.
        try writeFile(((root as NSString).appendingPathComponent(".remaps") as NSString).appendingPathComponent("3.7"), "3.9")

        // Offline (pure filesystem, no uv): requested 3.7 resolves to the 3.9 interpreter.
        XCTAssertEqual(iTermUvProvisioner.provisionedSharedVenvInterpreter(forRequestedVersion: "3.7", venvsRoot: root), py39)
        // A direct minor match still works, including with a patch component.
        XCTAssertEqual(iTermUvProvisioner.provisionedSharedVenvInterpreter(forRequestedVersion: "3.9.4", venvsRoot: root), py39)
        // A version with neither a venv nor a remap returns nil (falls through to uv).
        XCTAssertNil(iTermUvProvisioner.provisionedSharedVenvInterpreter(forRequestedVersion: "3.11", venvsRoot: root))
    }

    func testProvisionedSharedVenvInterpreterIgnoresRemapToUnprovisionedVenv() throws {
        let root = try makeTempDir()
        // Remap 3.7 -> 3.9 exists, but 3.9 was never provisioned (no interpreter/marker).
        try writeFile(((root as NSString).appendingPathComponent(".remaps") as NSString).appendingPathComponent("3.7"), "3.9")
        XCTAssertNil(iTermUvProvisioner.provisionedSharedVenvInterpreter(forRequestedVersion: "3.7", venvsRoot: root))
    }

    func testProvisionedSharedVenvInterpreterNeedsMarkerNotJustInterpreter() throws {
        let root = try makeTempDir()
        // Interpreter present but no .provisioned marker (a half-built venv) must not count.
        let python = ((root as NSString).appendingPathComponent("3.12") as NSString).appendingPathComponent("bin/python")
        try writeFile(python, "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python)
        XCTAssertNil(iTermUvProvisioner.provisionedSharedVenvInterpreter(forRequestedVersion: "3.12", venvsRoot: root))
    }

    // MARK: - Runtime menu decision (item 1)

    func testRuntimeMenuActionUnderGate() {
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: true, uvInstalled: false, legacyInstalled: false), .uvInstall)
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: true, uvInstalled: true, legacyInstalled: false), .uvCheckForUpdate)
        // Under the gate, a leftover legacy runtime must NOT change the decision (the bug
        // where the item retargeted the legacy updater with the gate on).
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: true, uvInstalled: false, legacyInstalled: true), .uvInstall)
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: true, uvInstalled: true, legacyInstalled: true), .uvCheckForUpdate)
    }

    func testRuntimeMenuActionGateOff() {
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: false, uvInstalled: false, legacyInstalled: false), .legacyInstall)
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: false, uvInstalled: false, legacyInstalled: true), .legacyCheckForUpdate)
        // uv present but gate off: still the legacy decision.
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuAction(uvGateEnabled: false, uvInstalled: true, legacyInstalled: false), .legacyInstall)
    }

    func testRuntimeMenuItemTitleAndCheckFlag() {
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuItemTitle(for: .uvInstall), "Install Python Runtime")
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuItemTitle(for: .uvCheckForUpdate), "Check for Updated Runtime")
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuItemTitle(for: .legacyInstall), "Install Python Runtime")
        XCTAssertEqual(iTermScriptRuntime.pythonRuntimeMenuItemTitle(for: .legacyCheckForUpdate), "Check for Updated Runtime")
        XCTAssertTrue(iTermScriptRuntime.isCheckForUpdate(.uvCheckForUpdate))
        XCTAssertTrue(iTermScriptRuntime.isCheckForUpdate(.legacyCheckForUpdate))
        XCTAssertFalse(iTermScriptRuntime.isCheckForUpdate(.uvInstall))
        XCTAssertFalse(iTermScriptRuntime.isCheckForUpdate(.legacyInstall))
    }

    // MARK: - installDownloadedTarball / extractAndInstall

    func testRejectsInvalidSignature() throws {
        // An RSA signature that does not validate (against the bundled public key)
        // must fail and install nothing. This is the central trust invariant.
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        let error = iTermUvProvisioner.installDownloadedTarball(
            data: Data("some bytes".utf8),
            encodedSignature: "bm90LWEtdmFsaWQtc2lnbmF0dXJl",  // base64 of "not-a-valid-signature"
            destinationBinaryPath: dest)
        XCTAssertNotNil(error, "an invalid signature must fail")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest), "nothing may be installed on failure")
    }

    func testExtractAndInstallExtractsRealTarball() throws {
        // Build a real gzipped tar containing uv-x/uv, hermetically (no network).
        let pkg = try makeTempDir()
        try writeFile((pkg as NSString).appendingPathComponent("uv-x/uv"), "#!/bin/sh\necho hi\n")
        let tgz = (try makeTempDir() as NSString).appendingPathComponent("uv.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", tgz, "-C", pkg, "uv-x"]
        try tar.run()
        tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0)

        let data = try Data(contentsOf: URL(fileURLWithPath: tgz))
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")

        XCTAssertNil(iTermUvProvisioner.extractAndInstall(data: data, destinationBinaryPath: dest))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest))
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "#!/bin/sh\necho hi\n")
    }

    func testExtractAndInstallFailsOnNonTar() throws {
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        let error = iTermUvProvisioner.extractAndInstall(data: Data("not a tarball".utf8),
                                                         destinationBinaryPath: dest)
        XCTAssertNotNil(error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest))
    }
}

final class UvProvisionerLiveTests: XCTestCase {
    // Tier B: fetch the real iterm2.com manifest, download the chosen build,
    // RSA-verify it against the bundled public key, install, and run `uv --version`.
    // Skipped by default; run with ITERM2_UV_LIVE=1.
    func testFetchManifestDownloadVerifyInstall() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ITERM2_UV_LIVE"] == "1",
                          "Set ITERM2_UV_LIVE=1 to run the live uv download test")
        let entry: iTermUvManifestEntry
        switch iTermUvProvisioner.fetchSelectedEntry() {
        case .failure(let error):
            throw error
        case .success(let selected):
            entry = selected
        }
        let data = try Data(contentsOf: try XCTUnwrap(URL(string: entry.url)))
        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("uvlive-\(UUID().uuidString)/bin/uv")
        addTeardownBlock {
            try? FileManager.default.removeItem(atPath: (dest as NSString).deletingLastPathComponent)
        }

        XCTAssertNil(iTermUvProvisioner.installDownloadedTarball(data: data,
                                                                encodedSignature: entry.signature,
                                                                destinationBinaryPath: dest))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: dest)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("uv "), "unexpected uv --version output: \(out)")
    }

    // Tier C flagship: install uv (from the hosted manifest), then use it to
    // provision a full-environment script and confirm the venv can import iterm2 and
    // that its asyncio REPL supports top-level await. Skipped by default.
    func testProvisionFullEnvironmentEndToEnd() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ITERM2_UV_LIVE"] == "1",
                          "Set ITERM2_UV_LIVE=1 to run the live uv provisioning test")
        let entry: iTermUvManifestEntry
        switch iTermUvProvisioner.fetchSelectedEntry() {
        case .failure(let error): throw error
        case .success(let selected): entry = selected
        }
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("uvprov-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }

        // Install uv into a temp location (with RSA verification).
        let uvPath = (root as NSString).appendingPathComponent("bin/uv")
        let uvData = try Data(contentsOf: try XCTUnwrap(URL(string: entry.url)))
        XCTAssertNil(iTermUvProvisioner.installDownloadedTarball(
            data: uvData, encodedSignature: entry.signature, destinationBinaryPath: uvPath))

        // Provision a full-environment script with it.
        let container = (root as NSString).appendingPathComponent("MyScript")
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let result = iTermUvProvisioner.provisionFullEnvironment(
            uvPath: uvPath,
            pythonInstallDir: (root as NSString).appendingPathComponent("python"),
            cacheDir: (root as NSString).appendingPathComponent("cache"),
            container: container,
            requestedPythonVersion: "3.9",
            dependencies: [])
        switch result {
        case .failure(let error):
            XCTFail("provisioning failed: \(error)")
            return
        case .success(let marker):
            XCTAssertEqual(marker.python, "3.9")
            XCTAssertNil(marker.remappedFrom)
            XCTAssertFalse(marker.uvVersion.isEmpty)
        }

        // It is recognized as a uv environment and its interpreter can import the
        // always-installed modules: iterm2 (the API), certifi (TLS roots, resolvable via
        // certifi.where()), and objc/AppKit (pyobjc, so scripts that import objc work).
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: container), .uv)
        let venvPython = try XCTUnwrap(iTermScriptRuntime.uvInterpreterPath(forScriptContainer: container))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = ["-c",
                             "import iterm2, certifi, objc, AppKit; assert certifi.where(); print('ok')"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "import failed: \(out)")
        XCTAssertTrue(out.contains("ok"))

        // The uv REPL runs `python -m asyncio`, which must support top-level await.
        let repl = Process()
        repl.executableURL = URL(fileURLWithPath: venvPython)
        repl.arguments = iTermReplLauncher.arguments(usesUV: true)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        repl.standardInput = stdinPipe
        repl.standardOutput = stdoutPipe
        repl.standardError = stdoutPipe
        try repl.run()
        stdinPipe.fileHandleForWriting.write(Data("import iterm2\nawait asyncio.sleep(0)\nprint('REPL_OK')\n".utf8))
        stdinPipe.fileHandleForWriting.closeFile()
        repl.waitUntilExit()
        let replOut = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(replOut.contains("REPL_OK"),
                      "asyncio REPL did not evaluate top-level await: \(replOut)")
    }
}
