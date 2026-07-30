//
//  UvProvisionerTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. The provisioner downloads,
//  verifies, extracts, and installs the uv binary. The risk-bearing filesystem
//  logic (locating the binary in the extracted tree and placing it executable) is
//  unit-tested hermetically here; the full download+verify+extract+install against
//  the real Astral tarball is a skip-guarded live test (Tier B). The window-
//  controller download orchestration is the thin integration shell validated on
//  device / by review. See docs/uv-python-runtime-migration.md (Phase 1).
//

import XCTest
import CryptoKit
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
        // The Astral tarball extracts to uv-<arch>-apple-darwin/uv, so the binary
        // is one level down, not at the root.
        let dir = try makeTempDir()
        let nested = (dir as NSString).appendingPathComponent("uv-aarch64-apple-darwin/uv")
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
        let src = (staging as NSString).appendingPathComponent("uv-aarch64-apple-darwin/uv")
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
        try writeFile(dest, "old")

        try iTermUvProvisioner.install(fromExtractedDirectory: staging, to: dest)
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "new")
    }

    func testInstallThrowsWhenBinaryMissing() throws {
        let staging = try makeTempDir()  // empty
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        XCTAssertThrowsError(try iTermUvProvisioner.install(fromExtractedDirectory: staging, to: dest))
    }

    // MARK: - entry selection / destination

    func testSelectsDevEntryOnSupportedMacOS() {
        XCTAssertEqual(iTermUvProvisioner.selectedEntry(forMacOSVersion: "13.4")?.uvVersion, "0.12.0")
        XCTAssertEqual(iTermUvProvisioner.selectedEntry(forMacOSVersion: "26.0")?.uvVersion, "0.12.0")
    }

    func testSelectsNothingOnUnsupportedMacOS() {
        // The dev entry requires macOS 13; a 12.x user gets nothing (Phase 0 warned them).
        XCTAssertNil(iTermUvProvisioner.selectedEntry(forMacOSVersion: "12.6"))
    }

    func testBinaryDestinationShape() {
        XCTAssertTrue(iTermUvProvisioner.uvBinaryPath.hasSuffix("/uv/bin/uv"),
                      "unexpected uv path: \(iTermUvProvisioner.uvBinaryPath)")
    }

    // MARK: - installDownloadedTarball (the trust invariant, hermetically)

    private func entry(signature: String, size: Int) -> iTermUvManifestEntry {
        return iTermUvManifestEntry(uvVersion: "x", url: "u", signature: signature, size: size,
                                    minimumMacOSVersion: "13.0", maximumMacOSVersion: nil)
    }

    func testInstallDownloadedTarballRejectsHashMismatch() throws {
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        let data = Data("not the expected bytes".utf8)
        let wrongHash = String(repeating: "0", count: 64)
        let error = iTermUvProvisioner.installDownloadedTarball(
            data: data, entry: entry(signature: wrongHash, size: data.count), destinationBinaryPath: dest)
        XCTAssertNotNil(error, "a hash mismatch must fail")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest), "nothing may be installed on mismatch")
    }

    func testInstallDownloadedTarballExtractsAndInstallsVerifiedTarball() throws {
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
        // Independent SHA-256 (CryptoKit) so we are not testing the verifier against itself.
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")

        let error = iTermUvProvisioner.installDownloadedTarball(
            data: data, entry: entry(signature: sha, size: data.count), destinationBinaryPath: dest)
        XCTAssertNil(error)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest))
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "#!/bin/sh\necho hi\n")
    }

    func testInstallDownloadedTarballFailsOnVerifiedNonTarArchive() throws {
        // Bytes that pass the hash check but are not a valid tar.gz: extraction must
        // fail (tar nonzero) and nothing may be installed.
        let data = Data("this passes the hash but is not a tarball".utf8)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let dest = (try makeTempDir() as NSString).appendingPathComponent("uv/bin/uv")
        let error = iTermUvProvisioner.installDownloadedTarball(
            data: data, entry: entry(signature: sha, size: data.count), destinationBinaryPath: dest)
        XCTAssertNotNil(error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest))
    }
}

final class UvProvisionerLiveTests: XCTestCase {
    // Tier B: downloads the real Astral tarball, verifies its pinned SHA-256,
    // extracts and installs it, and runs `uv --version`. Skipped by default so the
    // suite stays hermetic; run with ITERM2_UV_LIVE=1.
    func testDownloadVerifyExtractInstallRealTarball() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ITERM2_UV_LIVE"] == "1",
                          "Set ITERM2_UV_LIVE=1 to run the live uv download test")
        let entry = try XCTUnwrap(iTermUvProvisioner.selectedEntry(forMacOSVersion: "13.0"))
        let data = try Data(contentsOf: try XCTUnwrap(URL(string: entry.url)))
        let dest = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("uvlive-\(UUID().uuidString)/bin/uv")
        addTeardownBlock {
            try? FileManager.default.removeItem(
                atPath: (dest as NSString).deletingLastPathComponent)
        }

        let error = iTermUvProvisioner.installDownloadedTarball(data: data,
                                                               entry: entry,
                                                               destinationBinaryPath: dest)
        XCTAssertNil(error)
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

    // Tier C flagship: install uv, then use it to provision a full-environment
    // script (uv venv + uv pip install iterm2), and confirm the resulting venv can
    // import iterm2. Skipped by default; run with ITERM2_UV_LIVE=1.
    func testProvisionFullEnvironmentEndToEnd() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ITERM2_UV_LIVE"] == "1",
                          "Set ITERM2_UV_LIVE=1 to run the live uv provisioning test")
        let entry = try XCTUnwrap(iTermUvProvisioner.selectedEntry(forMacOSVersion: "13.0"))
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("uvprov-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(atPath: root) }

        // Install uv into a temp location.
        let uvPath = (root as NSString).appendingPathComponent("bin/uv")
        let uvData = try Data(contentsOf: try XCTUnwrap(URL(string: entry.url)))
        XCTAssertNil(iTermUvProvisioner.installDownloadedTarball(
            data: uvData, entry: entry, destinationBinaryPath: uvPath))

        // Provision a full-environment script with it.
        let container = (root as NSString).appendingPathComponent("MyScript")
        try FileManager.default.createDirectory(atPath: container, withIntermediateDirectories: true)
        let result = iTermUvProvisioner.provisionFullEnvironment(
            uvPath: uvPath,
            uvVersion: entry.uvVersion,
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
        }

        // It is recognized as a uv environment and its interpreter can import iterm2.
        XCTAssertEqual(iTermScriptRuntime.backend(forScriptContainer: container), .uv)
        let venvPython = try XCTUnwrap(iTermScriptRuntime.uvInterpreterPath(forScriptContainer: container))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = ["-c", "import iterm2; import certifi; print('ok')"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "import failed: \(out)")
        XCTAssertTrue(out.contains("ok"))

        // The uv REPL runs `python -m asyncio`, which must support top-level await
        // (that is the whole reason apython/aioconsole can be dropped).
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
