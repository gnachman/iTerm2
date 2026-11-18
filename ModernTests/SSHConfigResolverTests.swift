//
//  SSHConfigResolverTests.swift
//  ModernTests
//
//  Tests for NMSSH's SSHConfigResolver, a port of OpenSSH's readconf.c. The first group ports
//  the trials in OpenSSH's regress/cfginclude.sh, which compare against `ssh -G`. The rest
//  cover each behavior of the port, including where it deliberately differs from OpenSSH
//  (errors are skipped rather than fatal, comma lists in Host, no Match exec).
//
//  Everything uses fixture files in a temporary directory and a fake home directory, user,
//  and environment. Nothing reads the real ~/.ssh or /etc/ssh.
//

import XCTest
@_spi(Testing) import NMSSH

final class SSHConfigResolverTests: XCTestCase {
    private var root: URL!
    private var home: String!
    private var system: String!
    private var messages = [String]()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SSHConfigResolverTests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home").path
        system = root.appendingPathComponent("etc-ssh").path
        try FileManager.default.createDirectory(atPath: home + "/.ssh", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: system, withIntermediateDirectories: true)
        messages = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private var dir: String { root.path }

    /// Writes `contents` to `path` (absolute, or relative to the temporary directory) with
    /// mode 0644 and returns the absolute path.
    @discardableResult
    private func write(_ path: String, _ contents: String) throws -> String {
        let absolute = path.hasPrefix("/") ? path : dir + "/" + path
        try FileManager.default.createDirectory(atPath: (absolute as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try contents.write(toFile: absolute, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: absolute)
        return absolute
    }

    private func resolver(_ files: [SSHConfigFile],
                          environment: [String: String] = ["SITE": "prod"]) -> SSHConfigResolver {
        let local = SSHConfigResolver.LocalSystem(homeDirectory: home,
                                                  userName: "localuser",
                                                  uid: getuid(),
                                                  hostname: "mac.example.com",
                                                  environment: environment,
                                                  systemConfigDirectory: system)
        let resolver = SSHConfigResolver(files: files, localSystem: local)
        resolver.logHandler = { [weak self] in self?.messages.append($0) }
        return resolver
    }

    /// Resolves `host` against a single user config with `contents`.
    private func resolve(_ host: String,
                         _ contents: String,
                         user: String? = nil,
                         port: Int? = nil,
                         remoteCommand: String? = nil,
                         file: StaticString = #filePath,
                         line: UInt = #line) throws -> NMSSHHostConfig {
        let path = try write(home + "/.ssh/config", contents)
        return resolver([SSHConfigFile(path: path, isUserConfig: true)])
            .resolve(host: host, user: user, port: port, remoteCommand: remoteCommand)
    }

    /// What `ssh -G` would print as the hostname.
    private func connectHostname(_ host: String, _ resolver: SSHConfigResolver) -> String {
        return resolver.resolve(host: host, user: nil, port: nil, remoteCommand: nil).hostname ?? host
    }

    private func identityFiles(_ config: NMSSHHostConfig) -> [String] {
        return (config.identityFiles as? [String]) ?? []
    }

    // MARK: - regress/cfginclude.sh

    private func writeCfgincludeFixtures(commentsInIncluder: Bool) throws -> SSHConfigResolver {
        let c = commentsInIncluder
        let main = try write("ssh_config.i", """
            Match host a
            \tHostname aa

            Match host\(c ? "=" : " ")b\(c ? " # comment" : "")
            \tHostname bb
            \tInclude \(dir)/ssh_config.i.*

            Match host c
            \tInclude \(dir)/ssh_config.i.*
            \tHostname cc

            Match host\(c ? "=m !user xxxyfake" : " m")
            \tInclude \(dir)/ssh_config.i.*\(c ? " # comment" : "")

            Host d
            \tHostname dd\(c ? " # comment" : "")

            Host e
            \tHostname ee
            \tInclude \(dir)/ssh_config.i.*

            Host f
            \tInclude \(dir)/ssh_config.i.*
            \tHostname ff

            Host n
            \tInclude \(dir)/ssh_config.i.*

            """)
        try write("ssh_config.i.0", "Match host xxxxxx\n")
        try write("ssh_config.i.1", """
            Match host\(c ? "=" : " ")a
            \tHostname aaa

            Match host b\(c ? "" : " # comment")
            \tHostname bbb

            Match host c\(c ? " # comment" : "")
            \tHostname ccc\(c ? "" : " # comment")

            Host d\(c ? " # comment" : "")
            \tHostname ddd

            Host e
            \tHostname eee

            Host f
            \tHostname fff\(c ? " # comment" : "")

            """)
        try write("ssh_config.i.2", """
            Match host a
            \tHostname aaaa

            Match host\(c ? "=b !user blahblahfake" : " b")
            \tHostname bbbb

            Match host\(c ? "=" : " ")c
            \tHostname cccc

            Host d
            \tHostname dddd

            Host e
            \tHostname eeee

            Host f
            \tHostname ffff

            Match all\(c ? "" : " # comment")
            \tHostname xxxx\(c ? "" : " # comment")

            """)
        // `ssh -F` reads a file as a user config.
        return resolver([SSHConfigFile(path: main, isUserConfig: true)])
    }

    private func assertCfgincludeTrials(_ resolver: SSHConfigResolver, file: StaticString = #filePath, line: UInt = #line) {
        let trials = [("a", "aa"), ("b", "bb"), ("c", "ccc"), ("d", "dd"), ("e", "ee"),
                      ("f", "fff"), ("m", "xxxx"), ("n", "xxxx"), ("x", "x")]
        for (host, expected) in trials {
            XCTAssertEqual(connectHostname(host, resolver), expected, "trial \(host)", file: file, line: line)
        }
    }

    func testCfgincludeTrials() throws {
        assertCfgincludeTrials(try writeCfgincludeFixtures(commentsInIncluder: true))
    }

    func testCfgincludeTrialsWithCommentsInIncludedFiles() throws {
        assertCfgincludeTrials(try writeCfgincludeFixtures(commentsInIncluder: false))
    }

    /// OpenSSH rejects the whole config when an included file has a bad line ("Junk"). The
    /// port skips that line and keeps going.
    func testCfgincludeInvalidIncludedLineIsSkipped() throws {
        let resolver = try writeCfgincludeFixtures(commentsInIncluder: true)
        try write("ssh_config.i.3", "Hostname xxxx\n\tJunk\n")
        XCTAssertEqual(connectHostname("a", resolver), "aa")
        XCTAssertEqual(connectHostname("x", resolver), "x")
        XCTAssertTrue(messages.contains { $0.contains("ssh_config.i.3 line 2") }, "\(messages)")
    }

    /// The second half of cfginclude.sh: an Include before a top-level setting, and included
    /// files whose Match or Host lines must not change the includer's state afterward.
    func testCfgincludeIncludedBlocksDoNotLeakOut() throws {
        let main = try write("ssh_config.i", "Include \(dir)/ssh_config.i.*\nHostname aa\n")
        let resolver = resolver([SSHConfigFile(path: main, isUserConfig: true)])
        XCTAssertEqual(connectHostname("a", resolver), "aa")

        try write("ssh_config.i.x", "Match host x\n")
        XCTAssertEqual(connectHostname("a", resolver), "aa")

        try write("ssh_config.i.x", "Host x\n")
        XCTAssertEqual(connectHostname("a", resolver), "aa")
    }

    // MARK: - Lexing

    func testEqualsSeparator() throws {
        let config = try resolve("web", "Host=web\n    Hostname=web.example.com\n    Port = 2222\n    User =alice\n")
        XCTAssertEqual(config.hostname, "web.example.com")
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(config.user, "alice")
    }

    func testCommentEndsHostLine() throws {
        let contents = "Host web # production\n    User alice\n"
        XCTAssertEqual(try resolve("web", contents).user, "alice")
        XCTAssertNil(try resolve("production", contents).user)
    }

    func testQuotedAndEscapedValues() throws {
        let config = try resolve("web", """
            Host web
                IdentityFile "/path with spaces/id"
                IdentityFile /other\\ path/id

            """)
        XCTAssertEqual(identityFiles(config), ["/path with spaces/id", "/other path/id"])
    }

    func testCRLFAndTabs() throws {
        let config = try resolve("web", "Host\tweb\r\n\tHostname\tweb.example.com\r\n\tPort 2222\r\n")
        XCTAssertEqual(config.hostname, "web.example.com")
        XCTAssertEqual(config.port, 2222)
    }

    /// A Host or Match line OpenSSH would reject starts a block that doesn't match, rather
    /// than letting its settings apply to whatever came before.
    func testMalformedHostLineMakesBlockInactive() throws {
        let contents = "User global\nHost web \"unterminated\n    Port 1\nMatch host \"web\n    Hostname x\n"
        let config = try resolve("web", contents)
        XCTAssertEqual(config.user, "global")
        XCTAssertNil(config.port)
        XCTAssertNil(config.hostname)
    }

    /// OpenSSH rejects extra words after a single-valued setting; the port uses the first.
    func testExtraWordsAfterValueAreIgnored() throws {
        XCTAssertEqual(try resolve("web", "Host web\n    Hostname a.example.com b.example.com\n").hostname,
                       "a.example.com")
    }

    func testUnterminatedQuoteSkipsLine() throws {
        let config = try resolve("web", "Host web\n    Hostname \"web.example.com\n    Port 2222\n")
        XCTAssertNil(config.hostname)
        XCTAssertEqual(config.port, 2222)
    }

    // MARK: - Blocks and precedence

    /// Settings before the first Host or Match apply to every host.
    func testSettingsBeforeFirstHostApplyToEveryHost() throws {
        let contents = "User global\nPort 2222\nHost web\n    Hostname web.example.com\n"
        let web = try resolve("web", contents)
        XCTAssertEqual(web.user, "global")
        XCTAssertEqual(web.port, 2222)
        XCTAssertEqual(web.hostname, "web.example.com")
        XCTAssertEqual(try resolve("other", contents).user, "global")
    }

    func testFirstValueWinsWithinBlock() throws {
        let config = try resolve("web", """
            Host web
                Hostname first.example.com
                Hostname second.example.com
                Port 1
                Port 2

            """)
        XCTAssertEqual(config.hostname, "first.example.com")
        XCTAssertEqual(config.port, 1)
    }

    func testFirstValueWinsAcrossBlocks() throws {
        let config = try resolve("web", """
            Host web
                Hostname web.example.com
            Host other
                Port 1
            Host *
                Hostname fallback.example.com
                Port 2222
                User alice

            """)
        XCTAssertEqual(config.hostname, "web.example.com")
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(config.user, "alice")
    }

    func testIdentityFilesAccumulateWithoutDuplicatesAndExpandTilde() throws {
        let config = try resolve("web", """
            Host web
                IdentityFile ~/.ssh/id_web
                IdentityFile /keys/b
            Host *
                IdentityFile /keys/b
                IdentityFile ~/.ssh/id_default

            """)
        XCTAssertEqual(identityFiles(config), [home + "/.ssh/id_web", "/keys/b", home + "/.ssh/id_default"])
    }

    /// Host patterns match the host as typed, case-sensitively, as in OpenSSH.
    func testHostMatchingIsCaseSensitive() throws {
        XCTAssertNil(try resolve("WEB", "Host web\n    User alice\n").user)
        XCTAssertEqual(try resolve("web", "Host web\n    User alice\n").user, "alice")
    }

    func testHostNegation() throws {
        let contents = "Host * !bastion\n    User inner\nHost *\n    User outer\n"
        XCTAssertEqual(try resolve("web", contents).user, "inner")
        XCTAssertEqual(try resolve("bastion", contents).user, "outer")
    }

    /// Not in OpenSSH: a comma-separated Host argument is a pattern list, as NMSSH has always
    /// treated it.
    func testCommaListInHostArgument() throws {
        let contents = "Host a*,!ab\n    User alice\n"
        XCTAssertEqual(try resolve("abc", contents).user, "alice")
        XCTAssertNil(try resolve("ab", contents).user)
        XCTAssertEqual(try resolve("b", "Host a,b\n    User alice\n").user, "alice")
    }

    // MARK: - HostName

    func testHostNameExpandsTokens() throws {
        XCTAssertEqual(try resolve("web", "Host *\n    Hostname %h.example.com\n").hostname, "web.example.com")
        XCTAssertEqual(try resolve("web", "Host *\n    Hostname 100%%.example.com\n").hostname, "100%.example.com")
    }

    /// ssh lowercases the host name it connects to, unless it's an address.
    func testResolvedHostNameIsLowercasedUnlessAddress() throws {
        XCTAssertEqual(try resolve("web", "Host web\n    Hostname Web.Example.COM\n").hostname, "web.example.com")
        XCTAssertEqual(try resolve("v6", "Host v6\n    Hostname FE80::1\n").hostname, "FE80::1")
    }

    func testNoHostNameWhenNoneConfigured() throws {
        XCTAssertNil(try resolve("WEB", "Host other\n    Hostname other.example.com\n").hostname)
    }

    // MARK: - Port and User

    func testPortValues() throws {
        XCTAssertEqual(try resolve("web", "Host web\n    Port 65535\n").port, 65535)
        XCTAssertEqual(try resolve("web", "Host web\n    Port ssh\n").port, 22)
        for bad in ["0", "65536", "22x", "-1", "nosuchservice"] {
            XCTAssertNil(try resolve("web", "Host web\n    Port \(bad)\n").port, bad)
        }
        // A bad port doesn't stop a later block from supplying one.
        XCTAssertEqual(try resolve("web", "Host web\n    Port 99999\nHost *\n    Port 2222\n").port, 2222)
    }

    /// A user or port given explicitly beats the config, as with ssh -l and -p.
    func testExplicitUserAndPortWin() throws {
        let config = try resolve("web", "Host web\n    User alice\n    Port 2222\n", user: "bob", port: 2200)
        XCTAssertEqual(config.user, "bob")
        XCTAssertEqual(config.port, 2200)
    }

    // MARK: - Match

    /// Settings under a Match that doesn't apply don't leak into the previous Host block.
    func testNonMatchingMatchBlockDoesNotLeak() throws {
        let config = try resolve("web", """
            Host web
                Hostname web.example.com
            Match host other.example.com
                Port 9999
                User intruder

            """)
        XCTAssertEqual(config.hostname, "web.example.com")
        XCTAssertNil(config.port)
        XCTAssertNil(config.user)
    }

    /// Match host sees the HostName set so far; Match originalhost sees the host as typed.
    func testMatchHostAndOriginalHost() throws {
        let contents = """
            Host web
                Hostname web.example.com
            Match host *.example.com
                User byhostname
            Match originalhost web
                Port 2222

            """
        let config = try resolve("web", contents)
        XCTAssertEqual(config.user, "byhostname")
        XCTAssertEqual(config.port, 2222)
        XCTAssertNil(try resolve("web.example.com", "Match originalhost web\n    Port 2222\n").port)
    }

    func testMatchHostIgnoresCase() throws {
        XCTAssertEqual(try resolve("WEB.example.com", "Match host web.EXAMPLE.com\n    User alice\n").user, "alice")
    }

    func testMatchUserUsesExplicitUserThenLocalUser() throws {
        let contents = "Match user bob\n    Port 1\nMatch user localuser\n    Port 2\n"
        XCTAssertEqual(try resolve("web", contents, user: "bob").port, 1)
        XCTAssertEqual(try resolve("web", contents).port, 2)
        XCTAssertEqual(try resolve("web", "Match localuser local*\n    Port 3\n", user: "bob").port, 3)
    }

    func testMatchAllAndNegation() throws {
        XCTAssertEqual(try resolve("web", "Match all\n    User alice\n").user, "alice")
        XCTAssertNil(try resolve("web", "Match !all\n    User alice\n").user)
        XCTAssertEqual(try resolve("web", "Match !host other\n    User alice\n").user, "alice")
        XCTAssertNil(try resolve("web", "Match host web !originalhost web\n    User alice\n").user)
    }

    func testMatchTagged() throws {
        let contents = "Tag work\nMatch tagged work\n    User alice\nMatch tagged \"\"\n    Port 1\n"
        XCTAssertEqual(try resolve("web", contents).user, "alice")
        XCTAssertNil(try resolve("web", contents).port)
        XCTAssertEqual(try resolve("web", "Match tagged \"\"\n    Port 1\n").port, 1)
    }

    func testMatchCommandAndSessionType() throws {
        let contents = "Match sessiontype exec command git*\n    User git\nMatch sessiontype shell\n    User human\n"
        XCTAssertEqual(try resolve("web", contents, remoteCommand: "git-upload-pack").user, "git")
        XCTAssertEqual(try resolve("web", contents).user, "human")
    }

    /// Match exec never matches, negated or not, because it would run a command.
    func testMatchExecNeverMatches() throws {
        XCTAssertNil(try resolve("web", "Match exec true\n    User alice\n").user)
        XCTAssertNil(try resolve("web", "Match !exec false\n    User alice\n").user)
        XCTAssertNil(try resolve("web", "Match host web exec=true\n    User alice\n").user)
        XCTAssertTrue(messages.contains { $0.contains("Match exec is not supported") }, "\(messages)")
    }

    /// A Match line OpenSSH would reject makes its block inactive instead of failing.
    func testBadMatchLineMakesBlockInactive() throws {
        let contents = """
            Host web
                Port 1
            Match bogus thing
                User alice
            Match all host web
                Hostname x
            Match host
                Port 3
            Match
                Port 4

            """
        let config = try resolve("web", contents)
        XCTAssertEqual(config.port, 1)
        XCTAssertNil(config.user)
        XCTAssertNil(config.hostname)
    }

    /// Match final blocks apply in a second pass, in which Host patterns match the resolved
    /// host name.
    func testMatchFinal() throws {
        let contents = """
            Host web
                Hostname web.example.com
            Match final host *.example.com
                User alice
            Host *.example.com
                Port 2222

            """
        let config = try resolve("web", contents)
        XCTAssertEqual(config.user, "alice")
        XCTAssertEqual(config.port, 2222)
        XCTAssertNil(try resolve("web", "Host web\n    Hostname web.example.com\nHost *.example.com\n    Port 2222\n").port)
    }

    /// CanonicalizeHostname triggers the final pass too, so Match canonical applies (without
    /// any DNS lookup).
    func testCanonicalizeHostnameTriggersFinalPass() throws {
        let contents = "CanonicalizeHostname yes\nMatch canonical\n    User alice\nMatch !canonical\n    Port 1\n"
        let config = try resolve("web", contents)
        XCTAssertEqual(config.user, "alice")
        XCTAssertEqual(config.port, 1)
        XCTAssertNil(try resolve("web", "Match canonical\n    User alice\n").user)
    }

    // MARK: - Include

    func testRelativeIncludeInUserConfigIsUnderDotSSH() throws {
        try write(home + "/.ssh/hosts/web.conf", "Host web\n    Port 2222\n")
        XCTAssertEqual(try resolve("web", "Include hosts/*.conf\n").port, 2222)
    }

    func testTildeIncludeInUserConfig() throws {
        try write(home + "/elsewhere.conf", "Host web\n    Port 2222\n")
        XCTAssertEqual(try resolve("web", "Include ~/elsewhere.conf\n").port, 2222)
    }

    func testSystemConfigIncludes() throws {
        try write(system + "/ssh_config.d/web.conf", "Host web\n    Port 2222\n")
        try write(home + "/elsewhere.conf", "Host web\n    User alice\n")
        let main = try write(system + "/ssh_config", "Include ssh_config.d/*\nInclude ~/elsewhere.conf\n")
        let config = resolver([SSHConfigFile(path: main, isUserConfig: false)])
            .resolve(host: "web", user: nil, port: nil, remoteCommand: nil)
        XCTAssertEqual(config.port, 2222)
        XCTAssertNil(config.user)
        XCTAssertTrue(messages.contains { $0.contains("bad include path") }, "\(messages)")
    }

    func testIncludePathTokensAndEnvironment() throws {
        try write(home + "/.ssh/hosts/web.conf", "Port 2222\n")
        try write(home + "/.ssh/sites/prod.conf", "User alice\n")
        try write(home + "/.ssh/byname/web.example.com.conf", "IdentityFile /keys/web\n")
        let config = try resolve("web", """
            Host web
                Hostname %h.example.com
            Include hosts/%n.conf sites/${SITE}.conf byname/%h.conf

            """)
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(config.user, "alice")
        XCTAssertEqual(identityFiles(config), ["/keys/web"])
    }

    func testIncludeWithUnsupportedTokenOrMissingVariableIsSkipped() throws {
        try write(home + "/.ssh/ok.conf", "Port 2222\n")
        let config = try resolve("web", "Include conn-%C.conf ${NOPE}.conf ok.conf\n")
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(messages.filter { $0.contains("unable to expand include path") }.count, 2, "\(messages)")
    }

    func testMissingIncludeIsIgnored() throws {
        XCTAssertEqual(try resolve("web", "Include nosuchfile nosuchdir/*\nHost web\n    Port 2222\n").port, 2222)
    }

    /// An Include inside a block that doesn't apply reads the file, but nothing in it applies.
    func testIncludeInInactiveBlockAppliesNothing() throws {
        try write(home + "/.ssh/inc.conf", "Port 1\nHost web\n    User alice\nMatch all\n    Hostname x\n")
        let config = try resolve("web", "Host other\n    Include inc.conf\n")
        XCTAssertNil(config.port)
        XCTAssertNil(config.user)
        XCTAssertNil(config.hostname)
    }

    /// Lines in an included file before its first Host take the includer's state, and the
    /// includer's state is restored afterward.
    func testIncludeInheritsAndRestoresActiveState() throws {
        try write(home + "/.ssh/inc.conf", "User alice\nMatch host nomatch\n    Hostname x\n")
        let config = try resolve("web", "Host web\n    Include inc.conf\n    Port 2222\n")
        XCTAssertEqual(config.user, "alice")
        XCTAssertNil(config.hostname)
        XCTAssertEqual(config.port, 2222)
    }

    /// Not in OpenSSH (where it's fatal): an included file that others can write is skipped.
    func testIncludedFileWithUnsafePermissionsIsSkipped() throws {
        let path = try write(home + "/.ssh/inc.conf", "Host web\n    User alice\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: path)
        XCTAssertNil(try resolve("web", "Include inc.conf\n").user)
        XCTAssertTrue(messages.contains { $0.contains("bad owner or permissions") }, "\(messages)")
    }

    /// The top-level files are read whatever their permissions, as NMSSH always has.
    func testTopLevelFilePermissionsAreNotChecked() throws {
        let path = try write(home + "/.ssh/config", "Host web\n    User alice\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: path)
        let config = resolver([SSHConfigFile(path: path, isUserConfig: true)])
            .resolve(host: "web", user: nil, port: nil, remoteCommand: nil)
        XCTAssertEqual(config.user, "alice")
    }

    func testIncludeCycleTerminates() throws {
        try write(home + "/.ssh/loop.conf", "Include loop.conf\nHost web\n    User alice\n")
        XCTAssertEqual(try resolve("web", "Include loop.conf\n").user, "alice")
        XCTAssertTrue(messages.contains { $0.contains("too many nested includes") }, "\(messages)")
    }

    /// Lima adds its VMs with an Include of a glob, which is what issue 13219 is about.
    func testLimaStyleInclude() throws {
        try write(home + "/.lima/default/ssh.config", """
            # This SSH config file can be passed to 'ssh -F'.
            Host lima-default
              IdentityFile "\(home!)/.lima/_config/user"
              User localuser
              Hostname 127.0.0.1
              Port 60022

            """)
        try write(home + "/.lima/other/ssh.config", "Host lima-other\n  Hostname 127.0.0.1\n  Port 60023\n")
        let config = try resolve("lima-default", "Include ~/.lima/*/ssh.config\n\nHost *\n    User fallback\n")
        XCTAssertEqual(config.hostname, "127.0.0.1")
        XCTAssertEqual(config.port, 60022)
        XCTAssertEqual(config.user, "localuser")
        XCTAssertEqual(identityFiles(config), [home + "/.lima/_config/user"])
    }

    // MARK: - Several files

    /// Files are read as one pass, so a HostName from the user config is what Match host sees
    /// in the system config, and the first value wins across files.
    func testFilesAreOnePass() throws {
        let user = try write(home + "/.ssh/config", "Host web\n    Hostname web.example.com\n    Port 2222\n")
        let sys = try write(system + "/ssh_config", "Match host *.example.com\n    User alice\n    Port 1\n")
        let config = resolver([SSHConfigFile(path: user, isUserConfig: true),
                               SSHConfigFile(path: sys, isUserConfig: false)])
            .resolve(host: "web", user: nil, port: nil, remoteCommand: nil)
        XCTAssertEqual(config.hostname, "web.example.com")
        XCTAssertEqual(config.port, 2222)
        XCTAssertEqual(config.user, "alice")
    }

    /// Each top-level file starts with its settings applying to every host, even if the
    /// previous file ended inside a block that didn't match.
    func testEachFileStartsActive() throws {
        let user = try write(home + "/.ssh/config", "Host other\n    Port 1\n")
        let sys = try write(system + "/ssh_config", "User everyone\n")
        let config = resolver([SSHConfigFile(path: user, isUserConfig: true),
                               SSHConfigFile(path: sys, isUserConfig: false)])
            .resolve(host: "web", user: nil, port: nil, remoteCommand: nil)
        XCTAssertEqual(config.user, "everyone")
        XCTAssertNil(config.port)
    }

    func testMissingTopLevelFilesAreIgnored() throws {
        let sys = try write(system + "/ssh_config", "Host web\n    Port 2222\n")
        let config = resolver([SSHConfigFile(path: dir + "/nope", isUserConfig: true),
                               SSHConfigFile(path: sys, isUserConfig: false)])
            .resolve(host: "web", user: nil, port: nil, remoteCommand: nil)
        XCTAssertEqual(config.port, 2222)
    }
}
