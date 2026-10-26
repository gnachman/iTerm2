//
//  SignedArchiveCorruptCertificateTests.swift
//  ModernTests
//
//  Regression tests for QA finding F-414: importing a .its script archive whose embedded
//  signing certificate is damaged crashed iTerm2 with "CFRelease() called with NULL".
//  SIGCertificate's initWithData: returned nil when SecCertificateCreateWithData failed and
//  its dealloc then released the NULL SecCertificateRef. Verification must instead fail
//  with SIGErrorCodeInputMalformedCertificate.
//

import XCTest
@testable import iTerm2SharedARC

final class SignedArchiveCorruptCertificateTests: XCTestCase {
    private let corruptCertificate = Data(repeating: 0xFF, count: 512)

    func testCertificateFromCorruptDataIsNil() {
        XCTAssertNil(SIGCertificate(data: corruptCertificate))
        XCTAssertNil(SIGCertificate(data: Data()))
    }

    // Builds a well-formed version 2 archive whose only certificate chunk holds bytes that
    // are not a DER certificate.
    private func writeArchive(certificate: Data) throws -> URL {
        func chunk(_ tag: Int64, _ payload: Data) -> Data {
            var result = Data()
            for value in [tag, Int64(payload.count)] {
                var bigEndian = value.bigEndian
                result.append(Data(bytes: &bigEndian, count: MemoryLayout<Int64>.size))
            }
            result.append(payload)
            return result
        }
        var archive = Data()
        archive.append(chunk(0, Data("signed-archive".utf8)))
        archive.append(chunk(2, Data("version=2\ndigest-type=SHA2".utf8)))
        archive.append(chunk(1, Data("payload".utf8)))
        archive.append(chunk(4, certificate))
        archive.append(chunk(5, Data(repeating: 0, count: 256)))

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("corrupt-cert-\(UUID().uuidString).its")
        try archive.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testVerifyingArchiveWithCorruptCertificateFailsWithError() throws {
        let url = try writeArchive(certificate: corruptCertificate)
        let verifier = SIGArchiveVerifier(url: url)
        XCTAssertNoThrow(try verifier.smellsLikeSignedArchive())

        let done = expectation(description: "verification completes")
        var result: (Bool, NSError?)?
        verifier.verify { ok, error in
            result = (ok, error as NSError?)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)

        XCTAssertEqual(result?.0, false)
        XCTAssertEqual(result?.1?.domain, SIGErrorDomain)
        XCTAssertEqual(result?.1?.code, Int(SIGErrorCode.inputMalformedCertificate.rawValue))
    }
}

// Exercises SIGCertificate's Core Foundation ownership on a real signing certificate taken
// from a signed example script in the repo. An over-release in these accessors crashes once
// the autorelease pool drains. Found while fixing QA finding F-414.
final class SignedArchiveCertificateOwnershipTests: XCTestCase {
    private func certificateData(file: StaticString = #filePath) throws -> Data {
        let repo = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().deletingLastPathComponent()
        let archive = try Data(contentsOf: repo.appendingPathComponent(
            "api/library/python/iterm2/docs/examples/tab_group_test.its"))
        func int64(at offset: Int) -> Int {
            return Int(archive[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        }
        var offset = 0
        while offset + 16 <= archive.count {
            let tag = int64(at: offset)
            let length = int64(at: offset + 8)
            let start = offset + 16
            if tag == 4 {
                return archive.subdata(in: start..<(start + length))
            }
            offset = start + length
        }
        throw NSError(domain: "SignedArchiveCertificateOwnershipTests", code: 1)
    }

    func testCertificateAccessorsSurvivePoolDrain() throws {
        let data = try certificateData()
        var name: String?
        var serial: Data?
        var description: String?
        var issuerData: Data?
        for _ in 0..<20 {
            autoreleasepool {
                guard let certificate = SIGCertificate(data: data) else {
                    XCTFail("fixture certificate should parse")
                    return
                }
                name = certificate.name
                serial = certificate.serialNumber
                description = certificate.longDescription
                issuerData = certificate.issuer?.data
            }
        }
        XCTAssertNotNil(name)
        XCTAssertFalse(serial?.isEmpty ?? true)
        XCTAssertNotNil(description)
        // The issuer is found only if it is in this machine's keychain; when it is, its data
        // must still be readable after the pool drained.
        if let issuerData {
            XCTAssertFalse(issuerData.isEmpty)
        }
    }
}
