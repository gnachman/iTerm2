//
//  iTermSSHConfigIncludeExpanderTests.swift
//  ModernTests
//
//  NMSSH's config parser ignores Include, so iTerm2 expands Include lines itself before handing
//  the text to NMSSH. Only unconditional includes (top level or inside “Host *”) are supported;
//  everything else must be skipped so a host never resolves to another host's settings.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSSHConfigIncludeExpanderTests: XCTestCase {
    private var root: URL!
    private var home: String!
    private var sys: String!
    private var unreadablePaths = [String]()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iTermSSHConfigIncludeExpanderTests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home").path
        sys = root.appendingPathComponent("etc-ssh").path
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: sys, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for path in unreadablePaths {
            chmod(path, 0o644)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func makeExpander(environment: [String: String] = [:]) -> iTermSSHConfigIncludeExpander {
        return iTermSSHConfigIncludeExpander(homeDirectory: home,
                                             userName: "tu",
                                             uid: 501,
                                             localHostname: { "lh.example.com" },
                                             environment: environment,
                                             systemConfigDirectory: sys)
    }

    private func write(_ path: String, _ lines: [String], trailingNewline: Bool = true) {
        let dir = (path as NSString).deletingLastPathComponent
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try! text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private var userConfig: String { home + "/.ssh/config" }

    private func expandUserConfig(environment: [String: String] = [:]) -> String? {
        return makeExpander(environment: environment).expandedContents(ofFile: userConfig, isUserConfig: true)
    }

    private func parse(_ text: String?) -> NMSSHConfig {
        let text = try! XCTUnwrap(text)
        return try! XCTUnwrap(NMSSHConfig(string: text), "NMSSH could not parse:\n\(text)")
    }

    private func port(_ config: NMSSHConfig, _ host: String) -> Int? {
        return config.hostConfig(forHost: host)?.port?.intValue
    }

    // MARK: - Tests

    func testLimaStyleGlobInclude() {
        write(userConfig, ["Include ~/.lima/*/ssh.config"])
        write(home + "/.lima/dev/ssh.config", ["Host lima-dev",
                                               "  Hostname 127.0.0.1",
                                               "  Port 56266",
                                               "  User u",
                                               "  IdentityFile \"\(home!)/key\""])
        let hostConfig = parse(expandUserConfig()).hostConfig(forHost: "lima-dev")
        XCTAssertEqual(hostConfig?.hostname, "127.0.0.1")
        XCTAssertEqual(hostConfig?.port?.intValue, 56266)
        XCTAssertEqual(hostConfig?.user, "u")
        XCTAssertTrue((hostConfig?.identityFiles as? [String] ?? []).contains(home + "/key"))
    }

    func testRelativePathResolvesAgainstDotSSH() {
        write(userConfig, ["Include config.d/*"])
        write(home + "/.ssh/config.d/a", ["Host a", "Port 2201"])
        XCTAssertEqual(port(parse(expandUserConfig()), "a"), 2201)
    }

    func testGlobOrderIsLexical() {
        write(userConfig, ["Include config.d/*"])
        write(home + "/.ssh/config.d/20", ["Host x", "Port 20"])
        write(home + "/.ssh/config.d/10", ["Host x", "Port 10"])
        XCTAssertEqual(port(parse(expandUserConfig()), "x"), 10)
    }

    func testMultipleArgsQuotingEqualsAndCase() {
        write(userConfig, ["include=\"\(home!)/a b\" '\(home!)/c'"])
        write(home + "/a b", ["Host ab", "Port 1"])
        write(home + "/c", ["Host c", "Port 2"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "ab"), 1)
        XCTAssertEqual(port(config, "c"), 2)
    }

    func testQuotedHashIsFilenameUnquotedHashIsComment() {
        write(userConfig, ["Include \"\(home!)/#f\" #\(home!)/g"])
        write(home + "/#f", ["Host f", "Port 1"])
        write(home + "/g", ["Host g", "Port 2"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "f"), 1)
        XCTAssertNil(config.hostConfig(forHost: "g"))
    }

    func testUnterminatedQuoteSkipsLine() {
        write(userConfig, ["Include \"\(home!)/a", "Host h", "Port 2222"])
        write(home + "/a", ["Host a", "Port 1"])
        let config = parse(expandUserConfig())
        XCTAssertNil(config.hostConfig(forHost: "a"))
        XCTAssertEqual(port(config, "h"), 2222)
    }

    func testMissingGlobAndMissingFileIgnored() {
        write(userConfig, ["Include ~/nope/*", "Include ~/missing", "Host h", "Port 2222"])
        XCTAssertEqual(port(parse(expandUserConfig()), "h"), 2222)
    }

    func testUnreadableIncludedFileSkipped() {
        let secret = home + "/secret"
        write(userConfig, ["Include ~/secret", "Host h", "Port 2222"])
        write(secret, ["Host s", "Port 1"])
        XCTAssertEqual(chmod(secret, 0), 0)
        unreadablePaths.append(secret)
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "h"), 2222)
        XCTAssertNil(config.hostConfig(forHost: "s"))
    }

    func testSelfIncludeTerminates() {
        write(userConfig, ["Include config", "Host h", "Port 2222"])
        XCTAssertEqual(port(parse(expandUserConfig()), "h"), 2222)
    }

    func testMutualIncludeTerminates() {
        write(userConfig, ["Include a"])
        write(home + "/.ssh/a", ["Include b", "Host ha", "Port 1"])
        write(home + "/.ssh/b", ["Include a", "Host hb", "Port 2"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "ha"), 1)
        XCTAssertEqual(port(config, "hb"), 2)
    }

    func testSelfReferentialGlobDoesNotExplode() {
        // Each file includes every file in the directory, itself included. Without cycle
        // detection this is 4^16 file reads.
        write(userConfig, ["Include d/*"])
        for i in 0..<4 {
            write(home + "/.ssh/d/\(i)", ["Include d/*", "Host h\(i)", "Port \(100 + i)"])
        }
        let config = parse(expandUserConfig())
        for i in 0..<4 {
            XCTAssertEqual(port(config, "h\(i)"), 100 + i)
        }
    }

    func testDepthBoundary() {
        // f0 is the top-level file (depth 0); f16 is at depth 16 and its include of f17 is skipped.
        write(userConfig, ["Include f1", "Host h0", "Port 1000"])
        for i in 1...17 {
            write(home + "/.ssh/f\(i)", ["Include f\(i + 1)", "Host h\(i)", "Port \(1000 + i)"])
        }
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "h16"), 1016)
        XCTAssertNil(config.hostConfig(forHost: "h17"))
    }

    func testIncludeInsideHostStarIsTopLevel() {
        write(userConfig, ["Host *", "Include inc"])
        write(home + "/.ssh/inc", ["Host inner", "Port 2300"])
        XCTAssertEqual(port(parse(expandUserConfig()), "inner"), 2300)
    }

    func testHostStarRestoredAfterEachIncludedFile() {
        write(userConfig, ["Host *", "Include a b", "User star"])
        write(home + "/.ssh/a", ["Host a", "Port 1"])
        write(home + "/.ssh/b", ["User fromb", "Host b", "Port 2"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(config.hostConfig(forHost: "other")?.user, "fromb")
        XCTAssertEqual(config.hostConfig(forHost: "a")?.user, "fromb")
        XCTAssertEqual(config.hostConfig(forHost: "b")?.user, "fromb")
        XCTAssertEqual(port(config, "a"), 1)
        XCTAssertEqual(port(config, "b"), 2)
    }

    func testTopLevelIncludeDoesNotCaptureFollowingGlobals() {
        write(userConfig, ["Include inc", "Port 2400", "Host other", "Hostname o"])
        write(home + "/.ssh/inc", ["Host inner", "Port 2300"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "inner"), 2300)
        XCTAssertEqual(config.hostConfig(forHost: "other")?.hostname, "o")
        XCTAssertNil(port(config, "other"))
    }

    func testIncludeInsideOtherHostSkipped() {
        write(userConfig, ["Host prod-*", "Include inc", "Port 2200"])
        write(home + "/.ssh/inc", ["Host prod-api", "Port 1"])
        XCTAssertEqual(port(parse(expandUserConfig()), "prod-api"), 2200)
    }

    func testIncludeInsideMatchSkipped() {
        write(userConfig, ["Match all", "Include inc"])
        write(home + "/.ssh/inc", ["Host inner", "Port 1"])
        XCTAssertNil(parse(expandUserConfig()).hostConfig(forHost: "inner"))
    }

    func testMatchInIncludedFileDropped() {
        write(userConfig, ["Include inc"])
        write(home + "/.ssh/inc", ["Host *",
                                   "User star",
                                   "Match host internal",
                                   "HostName internal.example",
                                   "Port 2300",
                                   "Host real",
                                   "Port 22"])
        let config = parse(expandUserConfig())
        let unrelated = config.hostConfig(forHost: "unrelated")
        XCTAssertEqual(unrelated?.user, "star")
        XCTAssertNil(unrelated?.hostname)
        XCTAssertNil(unrelated?.port)
        XCTAssertEqual(port(config, "real"), 22)
        XCTAssertNil(config.hostConfig(forHost: "real")?.hostname)
    }

    func testParentMatchAfterTopLevelIncludeDoesNotLeak() {
        write(userConfig, ["Include inc",
                           "Match host internal",
                           "Hostname internal.example",
                           "Port 2400",
                           "Host other",
                           "Port 5"])
        write(home + "/.ssh/inc", ["Host inner", "Port 2300"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "inner"), 2300)
        XCTAssertNil(config.hostConfig(forHost: "inner")?.hostname)
        XCTAssertEqual(port(config, "other"), 5)
    }

    func testNoIncludeUnchanged() {
        write(userConfig, ["User globaluser",
                           "Port 1",
                           "Host *",
                           "IdentityFile ~/.ssh/star",
                           "Host alpha",
                           "Hostname alpha.example",
                           "Port 2",
                           "Match host beta",
                           "User matched",
                           "Host beta b2",
                           "User betauser",
                           "Port 3"])
        let expanded = parse(expandUserConfig())
        let original = try! XCTUnwrap(NMSSHConfig(fromFile: userConfig))
        for host in ["alpha", "beta", "b2", "gamma"] {
            let lhs = expanded.hostConfig(forHost: host)
            let rhs = original.hostConfig(forHost: host)
            XCTAssertEqual(lhs?.hostname, rhs?.hostname, host)
            XCTAssertEqual(lhs?.port, rhs?.port, host)
            XCTAssertEqual(lhs?.user, rhs?.user, host)
            XCTAssertEqual(lhs?.identityFiles as? [String], rhs?.identityFiles as? [String], host)
        }
    }

    func testTokensAndEnvironment() {
        write(userConfig, ["Include ${D}/x %d/y %u-%i-%l-%L ${UNSET}/z %h/w ${P}/v"])
        write(home + "/d/x", ["Host x", "Port 1"])
        write(home + "/y", ["Host y", "Port 2"])
        write(home + "/.ssh/tu-501-lh.example.com-lh", ["Host t", "Port 3"])
        write(home + "/.ssh/z", ["Host z", "Port 4"])  // would match if ${UNSET} expanded to ""
        write(home + "/.ssh/%h/v", ["Host v", "Port 5"])
        let config = parse(expandUserConfig(environment: ["D": home + "/d", "P": "%h"]))
        XCTAssertEqual(port(config, "x"), 1)
        XCTAssertEqual(port(config, "y"), 2)
        XCTAssertEqual(port(config, "t"), 3)
        XCTAssertNil(config.hostConfig(forHost: "z"))
        XCTAssertEqual(port(config, "v"), 5, "${P} must expand to a literal %h, not be rescanned")
    }

    func testTildeOtherUserSkipped() {
        write(userConfig, ["Include ~root/x"])
        XCTAssertNotNil(expandUserConfig())
        XCTAssertEqual(makeExpander().resolvedPaths(forArgument: "~root/x", isUserConfig: true), [])
        write(home + "/x", ["Host x"])
        XCTAssertEqual(makeExpander().resolvedPaths(forArgument: "~/x", isUserConfig: true), [home + "/x"])
    }

    func testSystemConfigRelativeAndTilde() {
        let systemConfig = sys + "/ssh_config"
        write(systemConfig, ["Include rel ~/x"])
        write(sys + "/rel", ["Host r", "Port 3"])
        write(home + "/x", ["Host tx", "Port 4"])
        let config = parse(makeExpander().expandedContents(ofFile: systemConfig, isUserConfig: false))
        XCTAssertEqual(port(config, "r"), 3)
        XCTAssertNil(config.hostConfig(forHost: "tx"))
    }

    func testNoTrailingNewline() {
        write(userConfig, ["Include inc"], trailingNewline: false)
        write(home + "/.ssh/inc", ["Host inner", "Port 7"], trailingNewline: false)
        XCTAssertEqual(port(parse(expandUserConfig()), "inner"), 7)
    }

    func testUnreadableTopLevelReturnsNil() {
        XCTAssertNil(makeExpander().expandedContents(ofFile: home + "/does-not-exist", isUserConfig: true))
    }

    func testLocalHostnameLookedUpOnlyForHostnameTokens() {
        // Looking up the hostname can be slow, and configs are loaded on the main thread.
        var lookups = 0
        let expander = iTermSSHConfigIncludeExpander(homeDirectory: home,
                                                     userName: "tu",
                                                     uid: 501,
                                                     localHostname: { lookups += 1; return "lh.example.com" },
                                                     environment: [:],
                                                     systemConfigDirectory: sys)
        write(userConfig, ["Include ~/x %u", "Host h", "Port 1"])
        XCTAssertNotNil(expander.expandedContents(ofFile: userConfig, isUserConfig: true))
        XCTAssertEqual(lookups, 0)

        write(userConfig, ["Include hosts-%L"])
        write(home + "/.ssh/hosts-lh", ["Host l", "Port 9"])
        XCTAssertEqual(port(parse(expander.expandedContents(ofFile: userConfig, isUserConfig: true)), "l"), 9)
        XCTAssertGreaterThan(lookups, 0)
    }

    func testNonUTF8ConfigStillLoads() {
        // A Latin-1 byte (0xE9, “é”) in a comment must not make the whole file disappear.
        var data = Data("# caf".utf8)
        data.append(0xE9)
        data.append(contentsOf: Array("\nInclude inc\nHost h\nPort 2222\n".utf8))
        try! data.write(to: URL(fileURLWithPath: userConfig))
        write(home + "/.ssh/inc", ["Host inner", "Port 7"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "h"), 2222)
        XCTAssertEqual(port(config, "inner"), 7)
    }

    func testIncludedHostEqualsHeaderDoesNotRedirectUnrelatedHosts() {
        // NMSSH only splits on whitespace, so it would ignore “Host=backup” and attach the
        // HostName to the preceding Host * block, redirecting every host.
        write(userConfig, ["Host *", "Include inc", "User star"])
        write(home + "/.ssh/inc", ["Host=backup", "HostName backup.example"])
        let config = parse(expandUserConfig())
        XCTAssertNil(config.hostConfig(forHost: "unrelated")?.hostname)
        XCTAssertEqual(config.hostConfig(forHost: "unrelated")?.user, "star")
        XCTAssertEqual(config.hostConfig(forHost: "backup")?.hostname, "backup.example")
    }

    func testIncludedHostEqualsHeaderDoesNotAttachToPreviousFile() {
        write(userConfig, ["Include a b"])
        write(home + "/.ssh/a", ["Host a", "Port 1"])
        write(home + "/.ssh/b", ["Host=backup", "HostName backup.example"])
        let config = parse(expandUserConfig())
        XCTAssertNil(config.hostConfig(forHost: "a")?.hostname)
        XCTAssertEqual(config.hostConfig(forHost: "backup")?.hostname, "backup.example")
    }

    func testOverlappingGlobsBoundTotalWork() {
        // Every file includes every file, so each distinct ordering is a separate chain.
        // Cycle detection alone visits roughly e·n! files; the budget must cap both the work
        // and the size of the output.
        write(userConfig, ["Include d/*"])
        for i in 0..<6 {
            write(home + "/.ssh/d/\(i)", ["Include d/*", "Host h\(i)", "Port \(100 + i)"])
        }
        let expander = iTermSSHConfigIncludeExpander(homeDirectory: home,
                                                     userName: "tu",
                                                     uid: 501,
                                                     localHostname: { "lh.example.com" },
                                                     environment: [:],
                                                     systemConfigDirectory: sys,
                                                     maxIncludedFiles: 50)
        let text = try! XCTUnwrap(expander.expandedContents(ofFile: userConfig, isUserConfig: true))
        let hostLines = text.components(separatedBy: "\n").filter { $0.hasPrefix("Host h") }
        XCTAssertLessThanOrEqual(hostLines.count, 50)
        let config = parse(text)
        for i in 0..<6 {
            XCTAssertEqual(port(config, "h\(i)"), 100 + i)
        }
    }

    func testIncludedFileLeadingOptionsApplyGlobally() {
        // In OpenSSH, options before any Host line are global, like a Host * block in place.
        write(userConfig, ["Include defaults.conf", "Host build", "Hostname b"])
        write(home + "/.ssh/defaults.conf", ["Port 2222", "User d"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(port(config, "build"), 2222)
        XCTAssertEqual(config.hostConfig(forHost: "build")?.user, "d")
        XCTAssertEqual(config.hostConfig(forHost: "build")?.hostname, "b")
        XCTAssertEqual(port(config, "unrelated"), 2222)
    }

    func testIncludedFileLeadingOptionsRestoredAfterNestedInclude() {
        write(userConfig, ["Include defaults.conf"])
        write(home + "/.ssh/defaults.conf", ["Port 2222", "Include more", "User d"])
        write(home + "/.ssh/more", ["Host m", "Port 1"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(config.hostConfig(forHost: "unrelated")?.user, "d")
        XCTAssertEqual(port(config, "unrelated"), 2222)
        // The global Port comes first, so it wins for m too, as it does in OpenSSH.
        XCTAssertEqual(port(config, "m"), 2222)
    }

    func testNestedIncludeBeforeAnyOptionsAddsNoEmptyHostStar() {
        write(userConfig, ["Include a"])
        write(home + "/.ssh/a", ["Include b", "User fromA"])
        write(home + "/.ssh/b", ["Host b", "Port 1"])
        let config = parse(expandUserConfig())
        XCTAssertEqual(config.hostConfig(forHost: "unrelated")?.user, "fromA")
        XCTAssertEqual(port(config, "b"), 1)
        XCTAssertNil(port(config, "unrelated"))
    }

    func testTokenizer() {
        let expander = makeExpander()
        XCTAssertEqual(expander.tokenize(line: "Include a\\ b")?.arguments, ["a b"])
        XCTAssertEqual(expander.tokenize(line: "Include a\\zb")?.arguments, ["a\\zb"])
        XCTAssertEqual(expander.tokenize(line: "Include \"\"")?.arguments, [])
        XCTAssertEqual(expander.tokenize(line: "  Include  =  x  y # z")?.arguments, ["x", "y"])
        XCTAssertEqual(expander.tokenize(line: "  Include  =  x")?.keyword, "Include")
        XCTAssertNil(expander.tokenize(line: "  # x"))
        XCTAssertNil(expander.tokenize(line: "   "))
        XCTAssertNil(expander.tokenize(line: "Include \"unterminated"))
    }
}
