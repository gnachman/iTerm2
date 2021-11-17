//
//  SetUserVariableTrigger.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/3/21.
//

import Foundation

@objc(iTermTwoParameterTriggerCodec) class TwoParameterTriggerCodec: NSObject {
    // Two-string parameters are encoded as <first string> <separator character> <second string>
    private static let separator = "\u{1}"

    private static func clean(_ string: NSString) -> String {
        return string.replacingOccurrences(of: separator, with: "")
    }

    @objc(stringFromTuple:) static func convert(tuple: iTermTuple<NSString, NSString>) -> String {
        return clean(tuple.firstObject) + separator + clean(tuple.secondObject)
    }

    @objc(tupleFromString:) static func convert(string: NSString?) -> iTermTuple<NSString, NSString> {
        guard let pair = string?.it_stringBySplitting(onFirstSubstring: separator) else {
            return iTermTuple(object: "", andObject: "")
        }
        return pair
    }
}

@objc(iTermSetUserVariableTrigger)
class SetUserVariableTrigger: Trigger {
    private static let nameKey = "name"
    private static let valueKey = "value"

    private func variableNameAndValue(_ param: String) -> (String, String)? {
        let tuple = TwoParameterTriggerCodec.convert(string: param as NSString)
        guard !tuple.firstObject.contains(".") else {
            return nil
        }
        return (tuple.firstObject.removingPrefix("user.") as String,
                tuple.secondObject as String)
    }

    override static var title: String {
        return "Set User Variable…"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return "Value for variable"
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
                                        useInterpolation: useInterpolation) { [weak self] message in
            if let (name, value) = self?.variableNameAndValue(message) {
                session.genericScope.setValue(value, forVariableNamed: "user." + name)
            }
        }
        return false
    }

    override func paramIsTwoStrings() -> Bool {
        return true
    }
}
