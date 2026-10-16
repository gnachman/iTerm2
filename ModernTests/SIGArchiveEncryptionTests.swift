//
//  SIGArchiveEncryptionTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/12/26.
//

import XCTest
@testable import iTerm2SharedARC

final class SIGArchiveEncryptionTests: XCTestCase {
    // Far below the production minimum so the tests stay fast. Readers are lowered to match.
    private let iterations: UInt32 = 1000
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeArchive(_ payload: Data, passphrase: String = "hunter2") throws -> URL {
        let url = directory.appendingPathComponent("archive")
        let encryption = try XCTUnwrap(SIGArchivePassphraseEncryption(passphrase: passphrase,
                                                                      cipher: SIGArchiveAESGCMCipher(),
                                                                      iterations: iterations))
        try SIGArchiveBuilder(payloadData: payload, identity: nil, encryption: encryption).write(to: url)
        return url
    }

    private func decrypt(_ url: URL,
                         passphrase: String = "hunter2",
                         minimumIterations: UInt32? = nil) throws -> Data {
        let reader = try XCTUnwrap(SIGArchiveReader(url: url))
        try reader.load()
        reader.minimumKDFIterations = minimumIterations ?? iterations
        return try reader.decryptedPayload(withPassphrase: passphrase, cipher: SIGArchiveAESGCMCipher())
    }

    private func assertSIGError(_ expected: SIGErrorCode,
                                file: StaticString = #filePath,
                                line: UInt = #line,
                                _ block: () throws -> Any) {
        XCTAssertThrowsError(try block(), file: file, line: line) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, SIGErrorDomain, file: file, line: line)
            XCTAssertEqual(nsError.code, Int(expected.rawValue), "\(nsError)", file: file, line: line)
        }
    }

    // Replaces the only occurrence of `target` in the file.
    private func patch(_ url: URL, replacing target: String, with replacement: String) throws {
        var data = try Data(contentsOf: url)
        let range = try XCTUnwrap(data.range(of: Data(target.utf8)))
        XCTAssertNil(data.range(of: Data(target.utf8), in: range.upperBound..<data.endIndex))
        data.replaceSubrange(range, with: Data(replacement.utf8))
        try data.write(to: url)
    }

    func testRoundTrip() throws {
        let payload = Data("the payload".utf8)
        XCTAssertEqual(try decrypt(try writeArchive(payload)), payload)
    }

    func testEmptyPayloadRoundTrips() throws {
        XCTAssertEqual(try decrypt(try writeArchive(Data())), Data())
    }

    func testPayloadIsNotStoredInTheClear() throws {
        let url = try writeArchive(Data("plaintext-marker".utf8))
        XCTAssertNil(try Data(contentsOf: url).range(of: Data("plaintext-marker".utf8)))
    }

    func testWrongPassphrase() throws {
        let url = try writeArchive(Data("x".utf8))
        assertSIGError(.decryptionFailed) {
            try decrypt(url, passphrase: "wrong")
        }
    }

    // The metadata is authenticated, so a change that still parses must fail decryption.
    func testTamperedMetadataFails() throws {
        let url = try writeArchive(Data("x".utf8))
        try patch(url, replacing: "version=2", with: "version=1")
        assertSIGError(.decryptionFailed) {
            try decrypt(url)
        }
    }

    func testTamperedCiphertextFails() throws {
        let url = try writeArchive(Data("some bytes to encrypt".utf8))
        var data = try Data(contentsOf: url)
        data[data.count - 1] ^= 1
        try data.write(to: url)
        assertSIGError(.decryptionFailed) {
            try decrypt(url)
        }
    }

    // The same passphrase may arrive composed (typed) or decomposed (pasted from a filename).
    func testPassphraseIsNormalized() throws {
        let decomposed = "cafe\u{0301}"
        let composed = "caf\u{00E9}"
        XCTAssertNotEqual(Data(decomposed.utf8), Data(composed.utf8))
        let payload = Data("secret".utf8)
        let url = try writeArchive(payload, passphrase: decomposed)
        XCTAssertEqual(try decrypt(url, passphrase: composed), payload)
    }

    func testTooFewIterationsAreRejected() throws {
        let url = try writeArchive(Data("x".utf8))
        assertSIGError(.badEncryptionParameters) {
            try decrypt(url, minimumIterations: SIGArchiveEncryptionMinimumIterations)
        }
    }

    // A forged file can't make us run an enormous number of iterations. Patching the archive would
    // change chunk lengths, so check the metadata parser directly.
    func testTooManyIterationsAreRejected() throws {
        let valid = try XCTUnwrap(SIGArchivePassphraseEncryption(passphrase: "x",
                                                                cipher: SIGArchiveAESGCMCipher(),
                                                                iterations: iterations)).metadataEntries()
        var metadata = valid
        metadata[SIGArchiveMetadataKeyKDFIterations] = "99999999"
        // Reported as unsupported rather than damaged, since a newer version might allow more.
        assertSIGError(.unsupportedAlgorithm) {
            try SIGArchivePassphraseEncryption(passphrase: "x",
                                               cipher: SIGArchiveAESGCMCipher(),
                                               metadata: metadata,
                                               minimumIterations: iterations)
        }
        metadata = valid
        metadata[SIGArchiveMetadataKeyKDFSalt] = Data(count: 4).base64EncodedString()
        assertSIGError(.badEncryptionParameters) {
            try SIGArchivePassphraseEncryption(passphrase: "x",
                                               cipher: SIGArchiveAESGCMCipher(),
                                               metadata: metadata,
                                               minimumIterations: iterations)
        }
        XCTAssertNoThrow(try SIGArchivePassphraseEncryption(passphrase: "x",
                                                            cipher: SIGArchiveAESGCMCipher(),
                                                            metadata: valid,
                                                            minimumIterations: iterations))
    }

    func testUnsignedArchiveMustBeEncrypted() {
        let url = directory.appendingPathComponent("archive")
        assertSIGError(.noCertificate) {
            try SIGArchiveBuilder(payloadData: Data("x".utf8), identity: nil, encryption: nil).write(to: url)
        }
    }

    // The script importer verifies archives with SIGArchiveVerifier. It must not hand out
    // ciphertext as if it were a verified payload.
    func testVerifierRejectsEncryptedArchive() throws {
        let url = try writeArchive(Data("x".utf8))
        let verifier = SIGArchiveVerifier(url: url)
        var result: (Bool, Error?)?
        verifier.verify { ok, error in
            result = (ok, error)
        }
        let (ok, error) = try XCTUnwrap(result)
        XCTAssertFalse(ok)
        XCTAssertEqual((error as NSError?)?.code, Int(SIGErrorCode.encrypted.rawValue))
    }
}
