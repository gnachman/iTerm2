//
//  ConductorViewInBrowserURLTests.swift
//  iTerm2
//
//  F-1050: “Download or View File?” > View opened iterm2-ssh://<remote hostname>/path. When the
//  ssh destination was an alias (nlc-far, HostName localhost, Port 2222) whose name differed from
//  the hostname the remote shell reported (ubuntu), ConductorRegistry could not find the
//  connection and the page said no SSH Integration connection could be found.
//

import XCTest
@testable import iTerm2SharedARC

@MainActor
final class ConductorViewInBrowserURLTests: XCTestCase {
    private var conductors = [Conductor]()

    override func tearDown() {
        for conductor in conductors {
            ConductorRegistry.instance.remove(conductorGUID: conductor.guid,
                                              sshIdentity: conductor.sshIdentity)
        }
        conductors = []
        super.tearDown()
    }

    private func makeConductor() -> Conductor {
        let conductor = Conductor("nlc-far", boolArgs: "", dcsID: "dcs",
                                  clientUniqueID: "f1050-\(conductors.count)",
                                  varsToSend: [:], clientVars: [:], initialDirectory: nil,
                                  shouldInjectShellIntegration: false, parent: nil)
        conductors.append(conductor)
        return conductor
    }

    private let aliasIdentity = SSHIdentity(host: "nlc-far",
                                            hostname: "localhost",
                                            username: "gnachman",
                                            port: 2222)

    func testRegistryFindsConductorForAliasThatDiffersFromRemoteHostname() throws {
        let registry = ConductorRegistry()
        let conductor = makeConductor()
        registry.addConductor(conductor, for: aliasIdentity)

        let url = try XCTUnwrap(aliasIdentity.viewInBrowserURL(path: "/home/gnachman/f960dl/c.txt"))
        XCTAssertEqual(url.scheme, iTermBrowserSchemes.ssh)
        XCTAssertEqual(url.path, "/home/gnachman/f960dl/c.txt")
        XCTAssertEqual(registry.conductors(for: url), [conductor])

        // The URL that used to be built from the shell-reported hostname finds nothing.
        let old = try XCTUnwrap(URL(string: "iterm2-ssh://ubuntu/home/gnachman/f960dl/c.txt"))
        XCTAssertEqual(registry.conductors(for: old), [])
    }

    func testURLDistinguishesConnectionsToTheSameAliasOnDifferentPorts() throws {
        let registry = ConductorRegistry()
        let conductor = makeConductor()
        let other = makeConductor()
        registry.addConductor(conductor, for: aliasIdentity)
        registry.addConductor(other, for: SSHIdentity(host: "nlc-far",
                                                      hostname: "localhost",
                                                      username: "gnachman",
                                                      port: 2223))
        let url = try XCTUnwrap(aliasIdentity.viewInBrowserURL(path: "/tmp/x.txt"))
        XCTAssertEqual(registry.conductors(for: url), [conductor])
    }

    // `it2ssh ::1` gives an identity whose host is a bare IPv6 address, which can't go in a URL
    // unbracketed.
    func testIPv6IdentityRoundTrips() throws {
        for address in ["::1", "fe80::1%en0"] {
            let registry = ConductorRegistry()
            let conductor = makeConductor()
            let identity = SSHIdentity(host: address, hostname: address, username: "qa", port: 22)
            registry.addConductor(conductor, for: identity)
            let url = try XCTUnwrap(identity.viewInBrowserURL(path: "/tmp/x.txt"), address)
            XCTAssertEqual(url.host, address)
            XCTAssertEqual(registry.conductors(for: url), [conductor], address)
        }
    }

    func testDefaultPortIdentityRoundTrips() throws {
        let registry = ConductorRegistry()
        let conductor = makeConductor()
        let identity = SSHIdentity(host: "example", hostname: "example.com", username: nil, port: 22)
        registry.addConductor(conductor, for: identity)
        let url = try XCTUnwrap(identity.viewInBrowserURL(path: "/etc/motd"))
        XCTAssertEqual(registry.conductors(for: url), [conductor])
    }
}
