//
//  iTermUvDownload.swift
//  iTerm2SharedARC
//
//  Phase 1 of the uv Python-runtime migration. Integrity checking for the
//  downloaded uv tarball. For the development source (Astral's unsigned tarball)
//  trust is a pinned SHA-256; when hosting moves to iterm2.com this is joined by
//  RSA-signature verification via iTermSignatureVerifier. No code path ever skips
//  verification. See docs/uv-python-runtime-migration.md (Phase 1).
//

import Foundation

enum iTermUvDownload {
    // True iff the SHA-256 of `data` equals `expectedHex` (case-insensitive).
    // Reuses NSData.it_sha256 so there is a single hashing implementation.
    static func matchesSHA256(data: Data, expectedHex: String) -> Bool {
        let actualHex = ((data as NSData).it_sha256() as NSData).it_hexEncoded()
        return actualHex.compare(expectedHex, options: .caseInsensitive) == .orderedSame
    }
}
