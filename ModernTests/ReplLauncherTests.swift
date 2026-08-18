//
//  ReplLauncherTests.swift
//  ModernTests
//
//  Phase 2 of the uv Python-runtime migration. The REPL launch is UI-bound, but
//  which arguments it runs (the branch the migration added) is a pure decision:
//  uv uses `python -m asyncio`; the legacy runtime uses apython with its banner
//  suppressed. See docs/uv-python-runtime-migration.md.
//

import XCTest
@testable import iTerm2SharedARC

final class ReplLauncherTests: XCTestCase {
    func testUvReplUsesAsyncioModule() {
        XCTAssertEqual(iTermReplLauncher.arguments(usesUV: true), ["-m", "asyncio"])
    }

    func testLegacyReplSuppressesApythonBanner() {
        // The legacy apython path is unchanged: it suppresses apython's own banner
        // (with an escaped empty string) so iTerm2's injected banner shows.
        XCTAssertEqual(iTermReplLauncher.arguments(usesUV: false), [#"--banner=\"\""#])
    }
}
