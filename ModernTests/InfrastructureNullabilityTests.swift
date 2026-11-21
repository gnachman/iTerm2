//
//  InfrastructureNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of external attributes, file transfer,
//  warnings, input broadcasting and screen char arrays that the nullability
//  sanitizer found false (unit N12 of
//  docs/swift-migration/nullability-triage.md). The Objective-C code accepts
//  or produces nil by design; these tests pin what Swift sees. A test that
//  passes nil only compiles because the position is now optional.
//

import XCTest
@testable import iTerm2SharedARC

final class ExternalAttributeIndexNullabilityTests: XCTestCase {
    private func hyperlink(_ string: String) -> iTermExternalAttribute {
        let url = iTermURL(url: URL(string: string)!, identifier: "1", target: nil)
        return iTermExternalAttribute(underlineColor: VT100TerminalColorValue(),
                                      url: url,
                                      blockIDList: nil,
                                      controlCode: nil)
    }

    // The screen passes the terminal's current external attributes, nil when
    // none are set. A uniform index of nothing is nil, so the factory's result
    // is optional too.
    func testUniformAttributesWithNilAttributeIsNil() {
        XCTAssertNil(iTermUniformExternalAttributes.withAttribute(nil))
    }

    func testUniformAttributesWithAnAttributeExists() {
        XCTAssertNotNil(iTermUniformExternalAttributes.withAttribute(hyperlink("https://a.example.com")))
    }

    // An attribute without a control code is made through the private
    // -initWithURL:blockIDList:controlCode:, which was declared nonnull for
    // the code but records an invalid control code for nil.
    func testAttributeWithoutControlCodeHasAnInvalidOne() throws {
        let url = iTermURL(url: URL(string: "https://a.example.com")!, identifier: "1", target: nil)
        let attribute = try XCTUnwrap(iTermExternalAttribute(havingUnderlineColor: false,
                                                             underlineColor: VT100TerminalColorValue(),
                                                             url: url,
                                                             blockIDList: nil,
                                                             controlCode: nil,
                                                             dualModeForeground: iTermDualModeColor(),
                                                             dualModeBackground: iTermDualModeColor()))
        XCTAssertFalse(attribute.controlCode.valid.boolValue)
    }

    // A line appended without attributes contributes none.
    func testConcatenatingNilKeepsTheLeftSide() {
        let lhs = iTermExternalAttributeIndex()
        lhs.setObject(hyperlink("https://a.example.com"), atIndexedSubscript: 0)
        let result = iTermExternalAttributeIndex.concatenation(of: lhs, length: 1, with: nil, length: 3)
        XCTAssertNotNil(result.attribute(at: 0))
        XCTAssertNil(result.attribute(at: 1))
        XCTAssertEqual(result.attributes.count, 1)
    }

    // +externalAttributeIndex:isEqualToIndex: compares two possibly-nil
    // indexes and passes nil on. That claim is pinned at compile time with a
    // non-nil optional: a nil would reach -[NSMutableSet
    // addObjectsFromArray:], whose parameter Apple declares nonnull, and the
    // nullability sanitizer would report it.
    func testIsEqualToOptionalIndexCompiles() {
        let other: iTermExternalAttributeIndex? = iTermExternalAttributeIndex()
        XCTAssertTrue(iTermExternalAttributeIndex().isEqual(toExternalAttributeIndex: other))
    }
}

final class ScreenCharArrayNullabilityTests: XCTestCase {
    // The first line has no previous line. Nothing duplicates nil.
    func testNothingIsADECDHLDuplicateOfNil() {
        XCTAssertFalse(ScreenCharArray.emptyLine(ofLength: 4).isDECDHLDuplicate(of: nil))
    }
}

final class BroadcastInputHelperNullabilityTests: XCTestCase {
    // With broadcasting off no domain contains a session. While the return
    // was claimed nonnull, Swift read the nil as an empty set.
    func testDomainContainingSessionWithBroadcastOffIsNil() {
        let helper = iTermBroadcastInputHelper()
        XCTAssertNil(helper.domainContainingSession("session"))
    }
}

final class WarningNullabilityTests: XCTestCase {
    // The warning handler is nil until one is installed, and the app installs
    // one only for remote handling. It is pinned at compile time because
    // tests install handlers of their own: guard let needs an optional.
    func testWarningHandlerIsOptional() {
        let haveHandler: () -> Bool = {
            guard let handler = iTermWarning.warningHandler() else {
                return false
            }
            _ = handler
            return true
        }
        XCTAssertNotNil(haveHandler as Any)
    }
}

final class TransferrableFileNullabilityTests: XCTestCase {
    // A download canceled before it had a local path unlocks nil, which does
    // nothing.
    func testUnlockingNilDoesNothing() {
        let name = "/tmp/nullability-test-" + UUID().uuidString
        TransferrableFile.lockName(name)
        defer {
            TransferrableFile.unlockName(name)
        }
        TransferrableFile.unlockName(nil)
        XCTAssertTrue(TransferrableFile.fileNameIsLocked(name))
    }
}
