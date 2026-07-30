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
}
