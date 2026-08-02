//
//  iTermRosettaSupport.swift
//  iTerm2SharedARC
//
//  macOS 27 removes Rosetta 2, so an Intel-only legacy Python runtime cannot run there
//  and the "Install Rosetta?" prompt would offer an install that can never succeed. This
//  holds the pure, injectable decisions (so they are unit-testable without reading the
//  host OS) plus a Mach-O arch reader. The pythonRuntimeUsesUV gate is unchanged; this
//  only fixes the Rosetta prompt and the handling of leftover x86_64 environments.
//

import Foundation

// What to do when launching a legacy (iterm2env) script given its interpreter's arch.
@objc enum iTermLegacyLaunchDisposition: Int {
    case launch      // the interpreter can run as-is (native slice, or Rosetta available)
    case rebuild     // Intel-only and Rosetta unavailable, gate off: rebuild from setup.cfg
    case unrunnable  // Intel-only and Rosetta unavailable, gate on: cannot run, cannot rebuild here
}

@objc(iTermRosettaSupport)
class iTermRosettaSupport: NSObject {
    // Rosetta 2 cannot be installed on macOS 27+. Injectable major version for tests;
    // Apple moved to year-based major versions (macOS 26, 27, ...), so a numeric
    // comparison is exactly what an @available(macOS 27, *) check resolves to at runtime,
    // without needing an SDK that knows about 27.
    @objc static func canInstallRosetta(osMajorVersion: Int) -> Bool {
        return osMajorVersion < 27
    }

    @objc static func canInstallRosetta() -> Bool {
        return canInstallRosetta(osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    // Whether to show the "Install Rosetta?" prompt: only on an ARM Mac where Rosetta can
    // still be installed. (The caller separately short-circuits if Rosetta is already
    // present, and an Intel Mac never needs it.)
    @objc static func shouldPromptForRosetta(hasARM: Bool, canInstallRosetta: Bool) -> Bool {
        return hasARM && canInstallRosetta
    }

    // What to do when launching a legacy iterm2env script. interpreterHasNativeSlice is
    // whether the env's python has an arm64 slice.
    @objc static func legacyLaunchDisposition(interpreterHasNativeSlice: Bool,
                                              canInstallRosetta: Bool,
                                              gateOn: Bool) -> iTermLegacyLaunchDisposition {
        if interpreterHasNativeSlice {
            // Runs natively regardless of Rosetta.
            return .launch
        }
        if canInstallRosetta {
            // Intel-only, but Rosetta can run it (macOS <= 26).
            return .launch
        }
        // Intel-only and Rosetta is unavailable (macOS 27+). Gate off: rebuild the env
        // against the current (arm64) runtime. Gate on: we are on the migration-failure
        // fallback, so surface an error rather than exec an unrunnable binary.
        return gateOn ? .unrunnable : .rebuild
    }

    // MARK: - Mach-O arch reader

    private static let fatMagic: UInt32 = 0xcafebabe
    private static let fatMagic64: UInt32 = 0xcafebabf
    private static let machMagic: UInt32 = 0xfeedface
    private static let machMagic64: UInt32 = 0xfeedfacf
    private static let cpuTypeArm64: UInt32 = 0x0100000c  // CPU_TYPE_ARM | CPU_ARCH_ABI64

    // True iff the Mach-O at path contains an arm64 slice (native, no Rosetta). Inspects a
    // thin or fat binary by reading header bytes; a missing, unreadable, or non-Mach-O
    // file returns false. Fat headers are big-endian on disk; a thin header's byte order
    // is given by its magic.
    @objc static func binaryHasArm64Slice(atPath path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path), data.count >= 8 else {
            return false
        }
        let bytes = [UInt8](data)
        func u32BE(_ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) |
                   (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        }
        func u32LE(_ offset: Int) -> UInt32? {
            guard offset >= 0, offset + 4 <= bytes.count else { return nil }
            return (UInt32(bytes[offset + 3]) << 24) | (UInt32(bytes[offset + 2]) << 16) |
                   (UInt32(bytes[offset + 1]) << 8) | UInt32(bytes[offset])
        }
        guard let magicBE = u32BE(0) else { return false }

        // Fat binary: nfat_arch and each fat_arch are big-endian on disk. A 32-bit
        // fat_arch is 20 bytes (cputype first); a 64-bit fat_arch is 32 bytes.
        if magicBE == fatMagic || magicBE == fatMagic64 {
            guard let nfat = u32BE(4) else { return false }
            let entrySize = (magicBE == fatMagic64) ? 32 : 20
            var offset = 8
            // Cap the count so a corrupt/hostile header cannot spin.
            for _ in 0..<min(nfat, 64) {
                guard let cpuType = u32BE(offset) else { return false }
                if cpuType == cpuTypeArm64 {
                    return true
                }
                offset += entrySize
            }
            return false
        }

        // Thin binary: cputype is the second header field, in the file's byte order.
        if let magicLE = u32LE(0), magicLE == machMagic || magicLE == machMagic64 {
            return u32LE(4) == cpuTypeArm64
        }
        if magicBE == machMagic || magicBE == machMagic64 {
            return u32BE(4) == cpuTypeArm64
        }
        return false
    }
}
