//
//  InjectTrigger.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/26/21.
//

import Foundation

@objc(iTermInjectTrigger)
class InjectTrigger: Trigger {
    override static var title: String {
        return "Inject Data…"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return "Use \\e for esc, \\a for ^G."
    }

    override func performAction(withCapturedStrings capturedStrings: UnsafePointer<NSString>,
                                capturedRanges: UnsafePointer<NSRange>,
                                captureCount: Int,
                                in session: PTYSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let buffer = UnsafeBufferPointer(start: capturedStrings, count: captureCount)
        let strings = Array(buffer).compactMap { $0 as String? }
        paramWithBackreferencesReplaced(withValues: strings,
                                        scope: session.genericScope,
                                        owner: session,
                                        useInterpolation: useInterpolation) { message in
                        session.inject(message.data(using: .utf8))
        }
        return false
    }
}
