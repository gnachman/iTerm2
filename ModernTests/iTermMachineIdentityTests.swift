//
//  iTermMachineIdentityTests.swift
//  iTerm2
//
//  Covers iTermMachineIdentity.locality(forToken:), which turns the OSC 7
//  ?machineID=<version>:<value> token into a localhost verdict by comparing the
//  reported value to this machine's own identity (version 1 = kern.bootsessionuuid).
//  Tests use the machine's real boot-session UUID so no advanced-setting override
//  is needed, keeping them hermetic.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermMachineIdentityTests: XCTestCase {
    // This machine's real value for version 1, read the same way the code under
    // test reads it (with no fake override configured).
    private var realBootSessionUUID: String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }

    func testMatchingValueIsLocalhost() {
        let token = iTermMachineIdentity.localVersion1TokenForTesting()
        XCTAssertNotNil(token)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: token), .localhost)
    }

    // The value is lowercase hex; the receiver compares case-insensitively, so an
    // uppercased hex value still matches.
    func testMatchingValueIsCaseInsensitive() {
        let token = iTermMachineIdentity.localVersion1TokenForTesting()!
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: token.uppercased()), .localhost)
    }

    func testDifferentValueIsRemote() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "1:00000000-0000-0000-0000-000000000000"),
                       .remote)
    }

    // A non-Darwin shell positively asserts "not this machine" with an empty value.
    func testEmptyValueIsRemote() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "1:"), .remote)
    }

    // No token at all: fall back to hostname comparison.
    func testNilTokenIsUnknown() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: nil), .unknown)
    }

    // A version we can't compute for ourselves (e.g. a future algorithm) falls
    // back to hostname comparison rather than asserting remote, so a genuinely
    // local Mac stays detectable by an older client.
    func testUnknownVersionIsUnknown() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "2:\(realBootSessionUUID)"), .unknown)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "99:anything"), .unknown)
    }

    // Version 0 ("0:") is what shell integration sends when it is our own report
    // but the identity couldn't be computed (e.g. sysctl failed). It is an unknown
    // version, so it yields .unknown and the caller falls back to hostname matching
    // rather than being forced remote.
    func testVersionZeroIsUnknown() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "0:"), .unknown)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "0:\(realBootSessionUUID)"), .unknown)
    }

    func testMalformedTokenIsUnknown() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "garbage"), .unknown)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: ""), .unknown)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "x:1"), .unknown)
    }

    // Only the version prefix is delimited: the first colon splits, and any colon
    // in the value stays part of the value (so it just won't match our UUID).
    func testOnlyFirstColonDelimitsVersion() {
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "1:a:b:c"), .remote)
    }

    // Pins the shell<->app interop: the token the shell scripts compute (openssl
    // HMAC of kern.bootsessionuuid) must be what iTermMachineIdentity treats as this
    // machine. Shell out to /usr/bin/openssl exactly as the scripts do, so a drift
    // in the HMAC key, the message encoding, or the hex format on either side fails
    // here rather than silently degrading every verdict to .unknown.
    func testShellComputedTokenIsLocalhost() throws {
        // The reference is computed over the REAL bootsessionuuid, but the code
        // under test HMACs the FakeBootSessionUUID override first when it is set, so
        // skip rather than fail confusingly for a developer who left the debug
        // override in their defaults suite.
        try XCTSkipUnless((iTermAdvancedSettingsModel.fakeBootSessionUUID() ?? "").isEmpty,
                          "FakeBootSessionUUID override is set")
        let bsid = realBootSessionUUID
        try XCTSkipIf(bsid.isEmpty)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = ["dgst", "-sha256", "-hmac", "iterm2-osc7-machine-id"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(bsid.utf8))
        stdin.fileHandleForWriting.closeFile()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        // openssl prints "SHA2-256(stdin)= <hex>" (OpenSSL) or bare "<hex>"
        // (LibreSSL); the scripts take the last whitespace-separated field.
        let hex = output.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init) ?? ""
        XCTAssertEqual(hex.count, 64)
        XCTAssertEqual(iTermMachineIdentity.locality(forToken: "1:\(hex)"), .localhost)
    }
}
