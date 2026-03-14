import XCTest
import Network
@testable import iTerm2SharedARC

final class PrivateIPCheckerTests: XCTestCase {

    // MARK: - Localhost Tests

    func testLocalhost() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("localhost"))
    }

    func testLocalhostUppercase() {
        // DNS names are case-insensitive, but we match exactly
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("LOCALHOST"))
    }

    // MARK: - .local Domain Tests

    func testLocalDomain() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("myserver.local"))
    }

    func testLocalDomainSubdomain() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("gpu.server.local"))
    }

    func testLocalDomainNotSuffix() {
        // "local" appearing elsewhere shouldn't match
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("local.example.com"))
    }

    // MARK: - IPv4 Loopback Tests

    func testIPv4Loopback127_0_0_1() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("127.0.0.1"))
    }

    func testIPv4Loopback127_0_0_2() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("127.0.0.2"))
    }

    func testIPv4Loopback127_255_255_255() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("127.255.255.255"))
    }

    // MARK: - IPv4 Private Range 10.x.x.x Tests

    func testIPv4Private10_0_0_1() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("10.0.0.1"))
    }

    func testIPv4Private10_255_255_255() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("10.255.255.255"))
    }

    // MARK: - IPv4 Private Range 172.16-31.x.x Tests

    func testIPv4Private172_16_0_1() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("172.16.0.1"))
    }

    func testIPv4Private172_31_255_255() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("172.31.255.255"))
    }

    func testIPv4NotPrivate172_15_0_1() {
        // 172.15.x.x is NOT private
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("172.15.0.1"))
    }

    func testIPv4NotPrivate172_32_0_1() {
        // 172.32.x.x is NOT private
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("172.32.0.1"))
    }

    // MARK: - IPv4 Private Range 192.168.x.x Tests

    func testIPv4Private192_168_0_1() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("192.168.0.1"))
    }

    func testIPv4Private192_168_255_255() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("192.168.255.255"))
    }

    func testIPv4NotPrivate192_169_0_1() {
        // 192.169.x.x is NOT private
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("192.169.0.1"))
    }

    // MARK: - IPv4 Link-Local Tests

    func testIPv4LinkLocal169_254_0_1() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("169.254.0.1"))
    }

    func testIPv4LinkLocal169_254_255_255() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("169.254.255.255"))
    }

    func testIPv4NotLinkLocal169_255_0_1() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("169.255.0.1"))
    }

    // MARK: - IPv4 Public Address Tests

    func testIPv4Public8_8_8_8() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("8.8.8.8"))
    }

    func testIPv4Public1_1_1_1() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("1.1.1.1"))
    }

    // MARK: - IPv4 Hostname Spoofing Prevention Tests

    func testIPv4SpoofedHostname192_168_example_com() {
        // Must NOT match - this is a hostname, not an IP
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("192.168.example.com"))
    }

    func testIPv4SpoofedHostname10_evil_com() {
        // Must NOT match - this is a hostname, not an IP
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("10.evil.com"))
    }

    func testIPv4SpoofedHostname172_16_attacker_net() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("172.16.attacker.net"))
    }

    // MARK: - IPv6 Loopback Tests

    func testIPv6LoopbackShort() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("::1"))
    }

    func testIPv6LoopbackFull() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("0:0:0:0:0:0:0:1"))
    }

    func testIPv6LoopbackFullWithLeadingZeros() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("0000:0000:0000:0000:0000:0000:0000:0001"))
    }

    // MARK: - IPv6 Link-Local Tests (fe80::/10)

    func testIPv6LinkLocalFe80() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("fe80::1"))
    }

    func testIPv6LinkLocalFe80Full() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("fe80:0:0:0:0:0:0:1"))
    }

    func testIPv6LinkLocalFebf() {
        // febf is still within fe80::/10
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("febf::1"))
    }

    func testIPv6NotLinkLocalFec0() {
        // fec0 is outside fe80::/10 (deprecated site-local, but not link-local)
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("fec0::1"))
    }

    // MARK: - IPv6 Unique Local Tests (fc00::/7)

    func testIPv6UniqueLocalFc00() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("fc00::1"))
    }

    func testIPv6UniqueLocalFd00() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("fd00::1"))
    }

    func testIPv6UniqueLocalFdab() {
        XCTAssertTrue(PrivateIPChecker.isLocalOrPrivate("fdab:cdef:1234::1"))
    }

    func testIPv6NotUniqueLocalFe00() {
        // fe00 is outside fc00::/7
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("fe00::1"))
    }

    // MARK: - IPv6 Public Address Tests

    func testIPv6PublicGoogle() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("2001:4860:4860::8888"))
    }

    func testIPv6PublicCloudflare() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("2606:4700:4700::1111"))
    }

    // MARK: - Invalid Input Tests

    func testEmptyString() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate(""))
    }

    func testRandomHostname() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("api.openai.com"))
    }

    func testInvalidIPv4TooManyOctets() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("192.168.1.1.1"))
    }

    func testInvalidIPv4OctetOutOfRange() {
        XCTAssertFalse(PrivateIPChecker.isLocalOrPrivate("192.168.1.256"))
    }
}
