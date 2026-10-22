//
//  ManPageURLValidationTests.swift
//  ModernTests
//
//  Allowlist validation of x-man-page: URL operands. See issue 5298.
//

import XCTest
@testable import iTerm2SharedARC

final class ManPageURLValidationTests: XCTestCase {
    // MARK: - Page names and apropos patterns

    func testAcceptsOrdinaryPageNames() {
        for name in ["ls", "git-commit", "Xorg", "zshall", "libc++", "std::string", "x_y", "2to3", "foo.1", "pkg@1"] {
            XCTAssertEqual(iTermSessionLauncher.validatedManArgument(name), name, name)
        }
    }

    func testRejectsEmptyOperand() {
        XCTAssertNil(iTermSessionLauncher.validatedManArgument(""))
    }

    func testRejectsLeadingDash() {
        // man.sh re-runs getopts on the operands in the -k branch, so "--" does not
        // protect against this. "-d" would turn on debug output; "-P" is eval'd.
        for arg in ["-d", "-sfoo", "-P", "--", "-"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg)
        }
    }

    func testRejectsSlashesSoManCannotRenderAFile() {
        // /usr/bin/man treats any operand containing a slash as a path to a roff
        // file and renders it directly.
        for arg in ["/tmp/evil.1", "Downloads/evil.1", "../evil.1", "a/b", "ls/"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg)
        }
    }

    func testRejectsBackslashAndControlCharacters() {
        for arg in ["ls\\n", "ls\\", "a\u{1B}b", "a\u{00}b", "a\tb", "a b", "ls\n"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg.debugDescription)
        }
    }

    func testRejectsShellAndGlobMetacharacters() {
        for arg in ["a;b", "a|b", "a&b", "a>b", "a<b", "$HOME", "`id`", "a*", "a?", "[a]", "{a}", "~", "a^b", "a%b", "a!b", "a#b", "a(b)", "a'b", "a\"b", "a=b", "a,b"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg)
        }
    }

    func testRejectsNonASCII() {
        for arg in ["é", "ls\u{200B}", "ﬁle", "日本"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg)
        }
    }

    func testPunctuationIsNotAllowedAsFirstCharacter() {
        for arg in [".hidden", "+x", ":x", "@x"] {
            XCTAssertNil(iTermSessionLauncher.validatedManArgument(arg), arg)
        }
        XCTAssertEqual(iTermSessionLauncher.validatedManArgument("_x"), "_x")
    }

    // MARK: - Sections

    func testAcceptsOrdinarySections() {
        for section in ["1", "3", "3tcl", "n", "8", "1ssl"] {
            XCTAssertEqual(iTermSessionLauncher.validatedManSection(section), section, section)
        }
    }

    func testRejectsBadSections() {
        for section in ["", "-P", "3/", "3.1", "3 ", "3;", "a/b", "é", "_"] {
            XCTAssertNil(iTermSessionLauncher.validatedManSection(section), section)
        }
    }
}
