//
//  ConductorTTYStateTests.swift
//  iTerm2 ModernTests
//
//  framer reports the login shell's terminal modes as `%notif tty` lines like
//  "-echo -icanon fgpgid=4242". fgpgid is the pty's foreground process group, which, compared with
//  a program's group, tells a shell's raw prompt from the program in raw mode.
//

import XCTest
@testable import iTerm2SharedARC

final class ConductorTTYStateTests: XCTestCase {
    private func state(after reports: String...) -> Conductor.TTYState {
        var state = Conductor.TTYState()
        for report in reports {
            state.apply(ttyNotification: report)
        }
        return state
    }

    func testModes() {
        let s = state(after: "-echo -icanon")
        XCTAssertFalse(s.echo)
        XCTAssertFalse(s.icanon)
        XCTAssertFalse(s.atPasswordPrompt)
        XCTAssertTrue(state(after: "-echo +icanon").atPasswordPrompt)
    }

    func testForegroundProcessGroup() {
        XCTAssertEqual(state(after: "-echo -icanon fgpgid=4242").foregroundProcessGroup, 4242)
    }

    func testForegroundProcessGroupIsUnknownUntilReported() {
        XCTAssertNil(Conductor.TTYState().foregroundProcessGroup)
    }

    func testAReportWithoutFgpgidMakesItUnknown() {
        // Every report carries everything framer knows, so one without fgpgid means it couldn't
        // tell, as does a report from a framer that predates it.
        XCTAssertNil(state(after: "-echo -icanon fgpgid=4242", "+echo +icanon").foregroundProcessGroup)
    }

    func testUnusableFgpgidIsUnknown() {
        XCTAssertNil(state(after: "-echo -icanon fgpgid=0").foregroundProcessGroup)
        XCTAssertNil(state(after: "-echo -icanon fgpgid=x").foregroundProcessGroup)
    }

    func testMalformedWordsAreIgnored() {
        let s = state(after: "-echo junk + - +icanon")
        XCTAssertFalse(s.echo)
        XCTAssertTrue(s.icanon)
    }
}
