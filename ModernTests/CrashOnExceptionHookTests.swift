//
//  CrashOnExceptionHookTests.swift
//  iTerm2 ModernTests
//
//  iTermApplication replaces +[NSApplication _crashOnException:] so that an
//  exception AppKit crashes on (such as one raised while drawing) is logged first.
//

import XCTest
import AppKit
import ObjectiveC
@testable import iTerm2SharedARC

final class CrashOnExceptionHookTests: XCTestCase {
    func testCrashOnExceptionIsHooked() {
        _ = iTermApplication.shared()
        guard let method = class_getClassMethod(NSApplication.self, NSSelectorFromString("_crashOnException:")) else {
            XCTFail("+[NSApplication _crashOnException:] no longer exists, so the hook does nothing")
            return
        }
        var info = Dl_info()
        let implementation = unsafeBitCast(method_getImplementation(method), to: UnsafeRawPointer.self)
        XCTAssertNotEqual(dladdr(implementation, &info), 0)
        let image = info.dli_fname.map { String(cString: $0) } ?? ""
        XCTAssertFalse(image.contains("AppKit"), "The implementation is still AppKit's: \(image)")
    }
}
