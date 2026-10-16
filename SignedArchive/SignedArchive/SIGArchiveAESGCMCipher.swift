//
//  SIGArchiveAESGCMCipher.swift
//  SignedArchive
//
//  Created by George Nachman on 10/12/26.
//

import CryptoKit
import Foundation

// Supplies AES-256-GCM to SIGArchive, which is Objective-C and has no public GCM API to call.
// Compiled into iTerm2 and into the extract tool, which each expose SIGArchiveEncryption.h to
// Swift through their bridging headers. The SignedArchive library itself stays Objective-C.
@objc(SIGArchiveAESGCMCipher)
final class SIGArchiveAESGCMCipher: NSObject, SIGAuthenticatedCipher {
    func sealPlaintext(_ plaintext: Data, key: Data, aad: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: aad)
        guard let combined = box.combined else {
            // Only nil for a nonce that isn't 12 bytes, and seal makes a 12-byte one.
            throw SIGError(code: .encryptionFailed)
        }
        return combined
    }

    func openSealedBox(_ sealedBox: Data, key: Data, aad: Data) throws -> Data {
        return try AES.GCM.open(try AES.GCM.SealedBox(combined: sealedBox),
                                using: SymmetricKey(data: key),
                                authenticating: aad)
    }
}
