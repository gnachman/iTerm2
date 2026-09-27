//
//  RosettaSupportTests.swift
//  ModernTests
//
//  macOS 27 Rosetta handling: pure decisions (OS version injected, never read from the
//  host) plus the Mach-O arm64-slice reader (crafted header fixtures, no real binaries).
//

import XCTest
@testable import iTerm2SharedARC

final class RosettaSupportTests: XCTestCase {
    // MARK: - canInstallRosetta

    func testCanInstallRosettaByOSMajor() {
        XCTAssertTrue(iTermRosettaSupport.canInstallRosetta(osMajorVersion: 25))
        XCTAssertTrue(iTermRosettaSupport.canInstallRosetta(osMajorVersion: 26))
        XCTAssertFalse(iTermRosettaSupport.canInstallRosetta(osMajorVersion: 27))
        XCTAssertFalse(iTermRosettaSupport.canInstallRosetta(osMajorVersion: 28))
    }

    // MARK: - shouldPromptForRosetta

    func testShouldPromptForRosettaMatrix() {
        XCTAssertTrue(iTermRosettaSupport.shouldPromptForRosetta(hasARM: true, canInstallRosetta: true))
        XCTAssertFalse(iTermRosettaSupport.shouldPromptForRosetta(hasARM: true, canInstallRosetta: false))
        XCTAssertFalse(iTermRosettaSupport.shouldPromptForRosetta(hasARM: false, canInstallRosetta: true))
        XCTAssertFalse(iTermRosettaSupport.shouldPromptForRosetta(hasARM: false, canInstallRosetta: false))
    }

    // MARK: - legacyLaunchDisposition (macOS 26/27 x gate on/off x native/x86)

    func testLegacyLaunchDispositionNativeAlwaysLaunches() {
        for canInstall in [true, false] {
            for gateOn in [true, false] {
                XCTAssertEqual(iTermRosettaSupport.legacyLaunchDisposition(interpreterHasNativeSlice: true,
                                                                          canInstallRosetta: canInstall,
                                                                          gateOn: gateOn),
                               .launch)
            }
        }
    }

    func testLegacyLaunchDispositionX86WithRosettaLaunches() {
        // macOS <= 26: Rosetta can run the Intel binary.
        XCTAssertEqual(iTermRosettaSupport.legacyLaunchDisposition(interpreterHasNativeSlice: false,
                                                                  canInstallRosetta: true,
                                                                  gateOn: false),
                       .launch)
        XCTAssertEqual(iTermRosettaSupport.legacyLaunchDisposition(interpreterHasNativeSlice: false,
                                                                  canInstallRosetta: true,
                                                                  gateOn: true),
                       .launch)
    }

    func testLegacyLaunchDispositionX86NoRosetta() {
        // macOS 27, gate off: rebuild the env against the arm64 runtime.
        XCTAssertEqual(iTermRosettaSupport.legacyLaunchDisposition(interpreterHasNativeSlice: false,
                                                                  canInstallRosetta: false,
                                                                  gateOn: false),
                       .rebuild)
        // macOS 27, gate on: on the migration-failure fallback; surface an error.
        XCTAssertEqual(iTermRosettaSupport.legacyLaunchDisposition(interpreterHasNativeSlice: false,
                                                                  canInstallRosetta: false,
                                                                  gateOn: true),
                       .unrunnable)
    }

    // MARK: - binaryHasArm64Slice (crafted Mach-O header fixtures)

    private func writeFixture(_ bytes: [UInt8]) throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("macho-" + UUID().uuidString)
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    func testThinArm64HasSlice() throws {
        // MH_MAGIC_64 (little-endian on disk) + CPU_TYPE_ARM64 (little-endian).
        let path = try writeFixture([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01])
        XCTAssertTrue(iTermRosettaSupport.binaryHasArm64Slice(atPath: path))
    }

    func testThinX86HasNoArm64Slice() throws {
        // MH_MAGIC_64 + CPU_TYPE_X86_64 (0x01000007).
        let path = try writeFixture([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0x00, 0x00, 0x01])
        XCTAssertFalse(iTermRosettaSupport.binaryHasArm64Slice(atPath: path))
    }

    func testFatWithArm64Slice() throws {
        // FAT_MAGIC (big-endian) + nfat=1 + one 32-bit fat_arch whose cputype is arm64.
        var bytes: [UInt8] = [0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x01]
        bytes += [0x01, 0x00, 0x00, 0x0c]                 // cputype = CPU_TYPE_ARM64 (BE)
        bytes += [UInt8](repeating: 0, count: 16)         // rest of the 20-byte fat_arch
        let path = try writeFixture(bytes)
        XCTAssertTrue(iTermRosettaSupport.binaryHasArm64Slice(atPath: path))
    }

    func testFatWithOnlyX86HasNoArm64Slice() throws {
        var bytes: [UInt8] = [0xca, 0xfe, 0xba, 0xbe, 0x00, 0x00, 0x00, 0x01]
        bytes += [0x01, 0x00, 0x00, 0x07]                 // cputype = CPU_TYPE_X86_64 (BE)
        bytes += [UInt8](repeating: 0, count: 16)
        let path = try writeFixture(bytes)
        XCTAssertFalse(iTermRosettaSupport.binaryHasArm64Slice(atPath: path))
    }

    func testGarbageAndMissingReturnFalse() throws {
        let garbage = try writeFixture([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        XCTAssertFalse(iTermRosettaSupport.binaryHasArm64Slice(atPath: garbage))
        XCTAssertFalse(iTermRosettaSupport.binaryHasArm64Slice(atPath: "/no/such/file/here"))
    }
}
