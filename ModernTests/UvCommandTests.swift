//
//  UvCommandTests.swift
//  ModernTests
//
//  Phase 1 of the uv Python-runtime migration. Pure builders for the uv command
//  lines and the provision-time environment. These are the deterministic core of
//  the provisioner; the actual subprocess execution and download are exercised by
//  the e2e harness (Tiers B/C). See docs/uv-python-runtime-migration.md (Phase 1).
//

import XCTest
@testable import iTerm2SharedARC

final class UvCommandTests: XCTestCase {
    func testVenvArgs() {
        XCTAssertEqual(iTermUvCommand.venvArgs(pythonVersion: "3.9", venvPath: "/scripts/A/.venv"),
                       ["venv", "--relocatable", "--python", "3.9", "/scripts/A/.venv"])
    }

    func testPipInstallArgsAreWheelsOnly() {
        // --only-binary :all: is what proves no compiler is required; it must always
        // be present so a source-only dependency fails loudly rather than compiling.
        XCTAssertEqual(
            iTermUvCommand.pipInstallArgs(venvPythonPath: "/scripts/A/.venv/bin/python",
                                          packages: ["iterm2", "pyobjc", "certifi"]),
            ["pip", "install", "--python", "/scripts/A/.venv/bin/python",
             "--only-binary", ":all:", "iterm2", "pyobjc", "certifi"])
    }

    func testPipInstallArgsWithNoPackages() {
        XCTAssertEqual(
            iTermUvCommand.pipInstallArgs(venvPythonPath: "/p/bin/python", packages: []),
            ["pip", "install", "--python", "/p/bin/python", "--only-binary", ":all:"])
    }

    func testPythonListArgsRequestJSONAndAllVersions() {
        // --only-downloads keeps `uv python list` from probing (and executing) every
        // interpreter on the search path, which would exec an Intel Homebrew python under
        // Rosetta on affected machines. It must remain present.
        XCTAssertEqual(iTermUvCommand.pythonListArgs(),
                       ["python", "list", "--all-versions", "--only-downloads", "--output-format", "json"])
    }

    func testPipPassthroughShow() {
        XCTAssertEqual(
            iTermUvCommand.pipPassthroughArgs(pipArguments: ["show", "requests"], venvPythonPath: "/v/bin/python"),
            ["pip", "show", "requests", "--python", "/v/bin/python"])
    }

    func testPipPassthroughInstallIsWheelsOnly() {
        XCTAssertEqual(
            iTermUvCommand.pipPassthroughArgs(pipArguments: ["install", "requests", "--upgrade"],
                                              venvPythonPath: "/v/bin/python"),
            ["pip", "install", "requests", "--upgrade", "--only-binary", ":all:", "--python", "/v/bin/python"])
    }

    func testPipPassthroughUninstallHasNoOnlyBinary() {
        XCTAssertEqual(
            iTermUvCommand.pipPassthroughArgs(pipArguments: ["uninstall", "requests"], venvPythonPath: "/v/bin/python"),
            ["pip", "uninstall", "requests", "--python", "/v/bin/python"])
    }

    func testProvisionEnvironmentPinsManagedOfflineSafeSettings() {
        let env = iTermUvCommand.provisionEnvironment(pythonInstallDir: "/support/uv/python",
                                                      cacheDir: "/support/uv/cache")
        XCTAssertEqual(env["UV_PYTHON_INSTALL_DIR"], "/support/uv/python")
        XCTAssertEqual(env["UV_CACHE_DIR"], "/support/uv/cache")
        // only-managed forces python-build-standalone and never a system/Homebrew
        // Python; no-config ignores the user's uv.toml; clone gives APFS reflink dedup.
        XCTAssertEqual(env["UV_PYTHON_PREFERENCE"], "only-managed")
        XCTAssertEqual(env["UV_NO_CONFIG"], "1")
        XCTAssertEqual(env["UV_PYTHON_DOWNLOADS"], "automatic")
        XCTAssertEqual(env["UV_LINK_MODE"], "clone")
    }
}
