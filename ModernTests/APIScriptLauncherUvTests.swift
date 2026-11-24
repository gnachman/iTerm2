//
//  APIScriptLauncherUvTests.swift
//  ModernTests
//
//  Phase 2 of the uv Python-runtime migration. environmentForScript: is the single
//  choke point that resolves the interpreter a full-environment script launches
//  with. For a uv-provisioned container it must return the flat .venv interpreter;
//  for anything else it must fall through to the unchanged legacy resolution.
//  See docs/uv-python-runtime-migration.md (Phase 2).
//

import XCTest
@testable import iTerm2SharedARC

final class APIScriptLauncherUvTests: XCTestCase {
    private func makeContainer() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("launchuv-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ path: String, _ contents: String = "x") throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func testResolvesUvInterpreterForUvContainer() throws {
        let c = try makeContainer()
        let venvPython = (c as NSString).appendingPathComponent(".venv/bin/python")
        try write(venvPython)
        try write((c as NSString).appendingPathComponent("python-runtime.json"), "{}")
        XCTAssertEqual(
            iTermAPIScriptLauncher.environment(forScript: c, checkForMain: false, checkForSaved: true),
            venvPython)
    }

    func testReturnsNilForContainerWithNoRuntime() throws {
        // Not a uv container and no iterm2env: the legacy resolution returns nil,
        // unchanged by the uv branch.
        let c = try makeContainer()
        XCTAssertNil(iTermAPIScriptLauncher.environment(forScript: c, checkForMain: false, checkForSaved: true))
    }

    // An environment whose versions directory holds no Python version: the
    // best version is nil, and appending a nil path component leaves a path
    // as it is, so the versions directory itself passes the existence check
    // and the result names bin/python3 directly under versions, a file that
    // does not exist. Unit nullability-baseline-guards appends "" instead of
    // nil (the same result) and pins this.
    func testPyenvWithNoVersionNamesBinUnderTheVersionsDirectory() throws {
        let c = try makeContainer()
        let env = (c as NSString).appendingPathComponent("iterm2env")
        try FileManager.default.createDirectory(atPath: (env as NSString).appendingPathComponent("versions"),
                                                withIntermediateDirectories: true)
        let expected = (env as NSString).appendingPathComponent("versions/bin/python3")
        let downloader = iTermPythonRuntimeDownloader.sharedInstance()
        XCTAssertEqual(downloader.pyenv(at: env, pythonVersion: nil), expected)
        XCTAssertEqual(downloader.pyenv(at: env, pythonVersion: "3.99"), expected)
        // The launcher then finds no such file.
        XCTAssertNil(iTermAPIScriptLauncher.environment(forScript: c, checkForMain: false, checkForSaved: true))
    }

    // With no versions directory at all the result is nil.
    func testPyenvWithNoVersionsDirectoryIsNil() throws {
        let c = try makeContainer()
        let env = (c as NSString).appendingPathComponent("iterm2env")
        try FileManager.default.createDirectory(atPath: env, withIntermediateDirectories: true)
        XCTAssertNil(iTermPythonRuntimeDownloader.sharedInstance().pyenv(at: env, pythonVersion: nil))
    }
}
