//
//  NSLocaleITermTests.swift
//  ModernTests
//
//  Characterization tests for the category NSLocale (iTerm):
//  -commasAndPeriodsGoInsideQuotationMarks, which is YES exactly when the
//  receiver's localeIdentifier is the string en_US. Written against the
//  Objective-C runtime interface so they run unchanged against a Swift
//  extension with the same selector.
//

import XCTest
import ObjectiveC
@testable import iTerm2SharedARC

final class NSLocaleITermTests: XCTestCase {
    private func locale(_ identifier: String) -> NSLocale {
        return NSLocale(localeIdentifier: identifier)
    }

    func testEnglishUnitedStatesIsTrue() {
        XCTAssertTrue(locale("en_US").commasAndPeriodsGoInsideQuotationMarks())
    }

    func testOtherIdentifiersAreFalse() {
        let identifiers = [
            "en_GB",
            "en",
            "en_US_POSIX",
            "fr_FR",
            "en_CA",
            "es_US",
            "",
            "en_US ",
            " en_US",
            "en_USA",
            "en_US@calendar=japanese",
            "en_US@rg=gbzzzz",
        ]
        for identifier in identifiers {
            XCTAssertFalse(locale(identifier).commasAndPeriodsGoInsideQuotationMarks(),
                           "identifier \(identifier) (localeIdentifier \(locale(identifier).localeIdentifier))")
        }
    }

    // NSLocale keeps these as the localeIdentifier en_US, so they answer YES.
    func testIdentifiersNSLocaleCanonicalizesToEnglishUnitedStatesAreTrue() {
        for identifier in ["en_us", "EN_US"] {
            XCTAssertTrue(locale(identifier).commasAndPeriodsGoInsideQuotationMarks(),
                          "identifier \(identifier) (localeIdentifier \(locale(identifier).localeIdentifier))")
        }
    }

    // The hyphenated form is answered from whatever localeIdentifier NSLocale
    // keeps for it, which is not the string en_US.
    func testHyphenatedFormIsFalse() {
        let hyphenated = locale("en-US")
        XCTAssertNotEqual(hyphenated.localeIdentifier, "en_US")
        XCTAssertFalse(hyphenated.commasAndPeriodsGoInsideQuotationMarks())
    }

    // A Swift Locale bridged to NSLocale is another concrete class; the
    // category applies to it too.
    func testBridgedSwiftLocale() {
        XCTAssertTrue((Locale(identifier: "en_US") as NSLocale).commasAndPeriodsGoInsideQuotationMarks())
        XCTAssertFalse((Locale(identifier: "en_GB") as NSLocale).commasAndPeriodsGoInsideQuotationMarks())
    }

    // The answer comes from -localeIdentifier as the receiver implements it.
    func testReadsTheReceiversLocaleIdentifier() {
        XCTAssertTrue(FixedIdentifierLocale(reported: "en_US", underlying: "fr_FR").commasAndPeriodsGoInsideQuotationMarks())
        XCTAssertFalse(FixedIdentifierLocale(reported: "fr_FR", underlying: "en_US").commasAndPeriodsGoInsideQuotationMarks())
    }

    // A receiver whose -localeIdentifier breaks the SDK's nonnull claim and
    // returns nil answers NO, as messaging nil did in the Objective-C. Swift
    // traps on `localeIdentifier as NSString` with a nil identifier.
    func testNilLocaleIdentifierIsFalse() {
        XCTAssertFalse(NilIdentifierLocale.make().commasAndPeriodsGoInsideQuotationMarks())
    }

    // The selector and its type encoding, which NSInvocation and
    // respondsToSelector: callers depend on.
    func testSelectorAndEncoding() {
        let selector = NSSelectorFromString("commasAndPeriodsGoInsideQuotationMarks")
        XCTAssertTrue(NSLocale.instancesRespond(to: selector))
        guard let method = class_getInstanceMethod(NSLocale.self, selector),
              let encoding = method_getTypeEncoding(method) else {
            XCTFail("no method")
            return
        }
        // BOOL and Swift's Bool encode as B on arm64 and as c on x86_64.
#if arch(arm64)
        XCTAssertEqual(String(cString: encoding), "B16@0:8")
#else
        XCTAssertEqual(String(cString: encoding), "c16@0:8")
#endif
    }

    // The one caller in the app: -[NSString stringByInsertingTerminalPunctuation:]
    // moves the punctuation inside the closing quotation mark only when the
    // current locale is en_US.
    func testTerminalPunctuationFollowsTheCurrentLocale() {
        guard let current = NSLocale.value(forKey: "currentLocale") as? NSLocale,
              let endQuote = current.object(forKey: .quotationEndDelimiterKey) as? String,
              let beginQuote = current.object(forKey: .quotationBeginDelimiterKey) as? String else {
            XCTFail("no current locale or quotation marks")
            return
        }
        let quoted = beginQuote + "foo" + endQuote
        NSLog("NSLocaleITermTests: current locale is %@", current.localeIdentifier)
        let actual = (quoted as NSString).insertingTerminalPunctuation(".")
        if current.localeIdentifier == "en_US" {
            XCTAssertEqual(actual, beginQuote + "foo." + endQuote)
        } else {
            XCTAssertEqual(actual, quoted + ".")
        }
    }
}

// An NSLocale whose -localeIdentifier returns nil. Swift cannot write such an
// override, since the SDK declares the property nonnull, so the getter is
// replaced through the runtime, on this subclass only.
private final class NilIdentifierLocale: NSLocale, @unchecked Sendable {
    private static let installNilGetter: Void = {
        let getter: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
        class_replaceMethod(NilIdentifierLocale.self,
                            Selector(("localeIdentifier")),
                            imp_implementationWithBlock(getter),
                            "@16@0:8")
    }()

    static func make() -> NilIdentifierLocale {
        _ = installNilGetter
        return NilIdentifierLocale(localeIdentifier: "en_US")
    }

    override init(localeIdentifier string: String) {
        super.init(localeIdentifier: string)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func object(forKey key: NSLocale.Key) -> Any? {
        return nil
    }

    override func displayName(forKey key: NSLocale.Key, value: Any) -> String? {
        return nil
    }
}

// An NSLocale whose -localeIdentifier differs from the identifier it was made
// with.
private final class FixedIdentifierLocale: NSLocale, @unchecked Sendable {
    private let reported: String

    init(reported: String, underlying: String) {
        self.reported = reported
        super.init(localeIdentifier: underlying)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var localeIdentifier: String {
        return reported
    }

    override func object(forKey key: NSLocale.Key) -> Any? {
        return key == .identifier ? reported : nil
    }

    override func displayName(forKey key: NSLocale.Key, value: Any) -> String? {
        return nil
    }
}
