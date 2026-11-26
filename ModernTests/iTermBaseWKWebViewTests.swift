//
//  iTermBaseWKWebViewTests.swift
//  ModernTests
//
//  Characterization tests for iTermBaseWKWebView, the WKWebView subclass
//  that iTermBrowserWebView inherits from. It overrides
//  -insertText:replacementRange: and -doCommandBySelector:, two methods
//  WKWebView implements privately, only to call super, so that a Swift
//  subclass can call super on them. Written against the Objective-C runtime
//  so they run unchanged against a Swift class with the same runtime name.
//  No view is put on screen.
//

import XCTest
import ObjectiveC
import WebKit
@testable import iTerm2SharedARC

// Receives the action that NSResponder's -doCommandBySelector: sends up the
// responder chain when the view itself does not respond to it.
private final class iTermBaseWKWebViewTestsProbe: NSResponder {
    var senders: [String] = []

    @objc func iTermBaseWKWebViewTestsAction(_ sender: Any?) {
        senders.append(String(describing: sender))
    }
}

final class iTermBaseWKWebViewTests: XCTestCase {
    private let unitClassName = "iTermBaseWKWebView"

    private func webViewClass() -> WKWebView.Type? {
        return NSClassFromString(unitClassName) as? WKWebView.Type
    }

    private func ownMethods(_ cls: AnyClass) -> [String: String] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else {
            return [:]
        }
        defer { free(methods) }
        return Dictionary(uniqueKeysWithValues: (0..<Int(count)).map {
            (NSStringFromSelector(method_getName(methods[$0])),
             method_getTypeEncoding(methods[$0]).map { String(cString: $0) } ?? "")
        })
    }

    func testClassExistsUnderItsObjectiveCNameWithItsSuperclass() {
        guard let cls = webViewClass() else {
            XCTFail("no class")
            return
        }
        XCTAssertTrue(class_getSuperclass(cls) === WKWebView.self)
    }

    func testSelectorsAndEncodings() {
        guard let cls = webViewClass() else {
            XCTFail("no class")
            return
        }
        let own = ownMethods(cls)
        XCTAssertEqual(own["insertText:replacementRange:"], "v40@0:8@16{_NSRange=QQ}24")
        XCTAssertEqual(own["doCommandBySelector:"], "v24@0:8:16")
    }

    func testTheSwiftSubclassStillInheritsFromIt() {
        XCTAssertEqual(class_getSuperclass(iTermBrowserWebView.self).map { NSStringFromClass($0) }, unitClassName)
    }

    // The override passes the selector on to WKWebView, which hands one it
    // does not know to NSResponder's -doCommandBySelector:, which sends it up
    // the responder chain. The probe as next responder sees it arrive.
    func testDoCommandBySelectorReachesSuper() {
        guard let cls = webViewClass() else {
            XCTFail("no class")
            return
        }
        let view = cls.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100),
                            configuration: WKWebViewConfiguration())
        let probe = iTermBaseWKWebViewTestsProbe()
        view.nextResponder = probe
        view.doCommand(by: #selector(iTermBaseWKWebViewTestsProbe.iTermBaseWKWebViewTestsAction(_:)))
        XCTAssertEqual(probe.senders.count, 1)
    }
}
