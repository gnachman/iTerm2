//
//  APIScriptLauncherFullEnvRedirectTests.swift
//  ModernTests
//
//  Regression: a full-environment script launched by its inner main.py path (e.g. from a
//  stale Open Quickly index) ran on the shared standard runtime and failed with
//  ModuleNotFoundError. fullEnvironmentContainerForMainPyPath: resolves such a path back
//  to the script container so the full environment (and its dependencies) is used.
//

import XCTest
@testable import iTerm2SharedARC

final class APIScriptLauncherFullEnvRedirectTests: XCTestCase {
    private func makeDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("launchredir-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: dir) }
        return dir
    }

    private func write(_ path: String, _ contents: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // Build a legacy full-environment script at <root>/<name>: setup.cfg, the inner
    // <name>/<name>.py, and an iterm2env whose versions/<patch> dir exists (which is what
    // environmentForScript checks). Returns (container, mainPy).
    private func makeFullEnvScript(name: String, patch: String) throws -> (container: String, mainPy: String) {
        let root = try makeDir()
        let container = (root as NSString).appendingPathComponent(name)
        try write((container as NSString).appendingPathComponent("setup.cfg"),
                  "[metadata]\nname=\(name)\n[options]\nscripts=\(name)/\(name).py\ninstall_requires=aiohttp; iterm2\npython_requires = =3.10\n")
        let mainPy = ((container as NSString).appendingPathComponent(name) as NSString).appendingPathComponent("\(name).py")
        try write(mainPy, "print('hi')\n")
        // environmentForScript requires the interpreter file itself to exist at
        // iterm2env/versions/<patch>/bin/python3.
        let python3 = ((container as NSString).appendingPathComponent("iterm2env/versions/\(patch)/bin") as NSString)
            .appendingPathComponent("python3")
        try write(python3, "#!/bin/sh\n")
        return (container, mainPy)
    }

    func testMainPyRedirectsToFullEnvContainer() throws {
        let (container, mainPy) = try makeFullEnvScript(name: "perappnotes", patch: "3.10.4")
        // Localize: the redirect requires environmentForScript(container) to resolve.
        let env = iTermAPIScriptLauncher.environment(forScript: container, checkForMain: true, checkForSaved: true)
        XCTAssertNotNil(env, "environmentForScript(container) was nil; fixture incomplete")
        XCTAssertEqual(iTermAPIScriptLauncher.fullEnvironmentContainer(forMainPyPath: mainPy), container)
    }

    func testPlainBasicScriptDoesNotRedirect() throws {
        let root = try makeDir()
        let py = (root as NSString).appendingPathComponent("hello.py")
        try write(py, "print('hi')\n")
        XCTAssertNil(iTermAPIScriptLauncher.fullEnvironmentContainer(forMainPyPath: py))
    }

    func testNonMainPyInContainerDoesNotRedirect() throws {
        // A .py that is not the container's <name>/<name>.py must not redirect.
        let (container, _) = try makeFullEnvScript(name: "perappnotes", patch: "3.10.4")
        let other = ((container as NSString).appendingPathComponent("perappnotes") as NSString).appendingPathComponent("helper.py")
        try write(other, "x = 1\n")
        XCTAssertNil(iTermAPIScriptLauncher.fullEnvironmentContainer(forMainPyPath: other))
    }

    func testMainPyWithoutEnvironmentDoesNotRedirect() throws {
        // Correct shape but no iterm2env (not actually a full-env script): stays basic.
        let root = try makeDir()
        let container = (root as NSString).appendingPathComponent("plainfolder")
        let mainPy = ((container as NSString).appendingPathComponent("plainfolder") as NSString).appendingPathComponent("plainfolder.py")
        try write(mainPy, "print('hi')\n")
        XCTAssertNil(iTermAPIScriptLauncher.fullEnvironmentContainer(forMainPyPath: mainPy))
    }
}
