//
//  NSHostLocalityTests.swift
//  iTerm2
//
//  Covers +[NSHost it_hostnameIsThisMachine:], which decides whether a
//  shell-reported hostname names this machine. It enumerates the machine's
//  actual names (the Unix name, the Bonjour .local name, and the DHCP FQDN) and
//  matches them exactly, so a machine that answers to MacBook-Pro-3.local and
//  MacBook-Pro-3.attlocal.net is recognized either way, but a remote reporting
//  "localhost" or a same-first-label name over plain ssh is not mistaken for us.
//  It also matches remembered names (from it_rememberLocalHostname:) exactly so a
//  name the machine has since drifted away from stays recognized.
//

import XCTest
@testable import iTerm2SharedARC

final class NSHostLocalityTests: XCTestCase {
    private var localFQDN: String { Host.fullyQualifiedDomainName() }
    private var localShortLabel: String {
        String(localFQDN.prefix(while: { $0 != "." }))
    }

    override func setUp() {
        super.setUp()
        // The remembered-local-names set is process-global; keep tests hermetic.
        Host.it_resetRememberedLocalHostnamesForTesting()
    }

    override func tearDown() {
        Host.it_resetRememberedLocalHostnamesForTesting()
        super.tearDown()
    }

    func testGethostnameMatches() {
        XCTAssertTrue(Host.it_hostnameIsThisMachine(localFQDN))
    }

    // Every enumerated name is recognized, case-insensitively. This is what makes
    // .local-vs-DHCP-FQDN detection symmetric: whichever form a shell reports is
    // in the set.
    func testEveryEnumeratedNameMatches() {
        let names = Host.it_localHostNames()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            XCTAssertTrue(Host.it_hostnameIsThisMachine(name), "\(name) should be local")
            XCTAssertTrue(Host.it_hostnameIsThisMachine(name.uppercased()),
                          "\(name) should match case-insensitively")
        }
    }

    // Bare "localhost" (e.g. reported by a shell on an unconfigured remote box
    // reached over plain ssh) is not automatically this machine.
    func testBareLocalhostIsNotAutomaticallyLocal() {
        let machineIsLiterallyLocalhost = Host.it_localHostNames().contains {
            $0.caseInsensitiveCompare("localhost") == .orderedSame
        }
        if !machineIsLiterallyLocalhost {
            XCTAssertFalse(Host.it_hostnameIsThisMachine("localhost"))
        }
    }

    // A different base name is remote even under the .local domain.
    func testForeignShortLabelDoesNotMatch() {
        XCTAssertFalse(Host.it_hostnameIsThisMachine("build-box-\(localShortLabel)x.local"))
    }

    // No short-label leniency: a foreign host that shares only our first DNS
    // label under a different domain is remote.
    func testSameShortLabelForeignDomainDoesNotMatch() {
        XCTAssertFalse(Host.it_hostnameIsThisMachine(localShortLabel + ".corp.example.invalid"),
                       "same first label under a foreign domain must not be judged local")
    }

    // The stock unconfigured Linux hostname is a real remote, not us.
    func testLocalhostLocaldomainDoesNotMatch() {
        XCTAssertFalse(Host.it_hostnameIsThisMachine("localhost.localdomain"))
    }

    // A foreign IP is never local.
    func testForeignIPDoesNotMatch() {
        XCTAssertFalse(Host.it_hostnameIsThisMachine("203.0.113.7"))
        XCTAssertFalse(Host.it_hostnameIsThisMachine("::1"))
    }

    func testEmptyAndNilDoNotMatch() {
        XCTAssertFalse(Host.it_hostnameIsThisMachine(""))
        XCTAssertFalse(Host.it_hostnameIsThisMachine(nil))
    }

    // MARK: - Growing set of known-local names

    // A name the machine has drifted away from (not a live name) is recognized
    // once remembered. This is the mDNS renumber case: -3.local today, -2
    // tomorrow, but -3.local was remembered while it was live.
    func testRememberedNameSurvivesLiveNameDrift() {
        let oldName = "MacBook-Pro-was-99.local"
        XCTAssertFalse(Host.it_hostnameIsThisMachine(oldName),
                       "precondition: not known before remembering")
        Host.it_addRememberedLocalHostname(forTesting: oldName)
        XCTAssertTrue(Host.it_hostnameIsThisMachine(oldName),
                      "a remembered local name is recognized even though it isn't a live name")
    }

    // Remembered names match exactly, not by short label, so a foreign host that
    // only shares the base name of a drifted-away name isn't taken for us.
    func testRememberedMatchIsExactNotShortLabel() {
        Host.it_addRememberedLocalHostname(forTesting: "MacBook-Pro-was-99.local")
        XCTAssertFalse(Host.it_hostnameIsThisMachine("MacBook-Pro-was-99.corp.invalid"))
    }

    func testRememberedMatchIsCaseInsensitive() {
        Host.it_addRememberedLocalHostname(forTesting: "MacBook-Pro-was-99.local")
        XCTAssertTrue(Host.it_hostnameIsThisMachine("MACBOOK-PRO-WAS-99.LOCAL"))
    }

    // it_rememberLocalHostname: only stores names the live names vouch for now,
    // so the set can't accumulate foreign names.
    func testRememberOnlyStoresLiveConfirmedNames() {
        Host.it_rememberLocalHostname("build-box.example.invalid")
        XCTAssertFalse(Host.it_hostnameIsThisMachine("build-box.example.invalid"),
                       "a name that isn't live now must not be remembered")

        Host.it_rememberLocalHostname(localFQDN)
        XCTAssertTrue(Host.it_hostnameIsThisMachine(localFQDN))
    }
}
