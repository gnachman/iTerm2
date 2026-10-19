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
