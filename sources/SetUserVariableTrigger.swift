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

    private static func clean(_ string: String) -> String {
        return string.replacingOccurrences(of: separator, with: "")
    }

    @objc(stringFromTuple:) static func objc_convert(tuple: iTermTuple<NSString, NSString>) -> String {
        let stringTuple: (String, String) = (tuple.firstObject as String? ?? "",
                                             tuple.secondObject as String? ?? "")
        return convert(tuple: stringTuple)
    }

    static func convert(tuple: (String, String)) -> String {
        return clean(tuple.0) + separator + clean(tuple.1)
    }

    @objc(tupleFromString:) static func objc_convert(string: NSString?) -> iTermTuple<NSString, NSString> {
        guard let string = string as String? else {
            return iTermTuple(object: "", andObject: "")
        }
        let tuple = convert(string: string)
        return iTermTuple<NSString, NSString>(object: tuple.0 as NSString,
                                              andObject: tuple.1 as NSString)
    }

    static func convert(string: String?) -> (String, String) {
        guard let pair = string?.it_stringBySplitting(onFirstSubstring: separator),
              let key = pair.firstObject as String?,
              let value = pair.secondObject as String? else {
                  return ("", "")
              }
        return (key, value)
    }
}

@objc(iTermSetUserVariableTrigger)
class SetUserVariableTrigger: Trigger {
    private static let nameKey = "name"
    private static let valueKey = "value"

    private func variableNameAndValue(_ param: String) -> (String, String)? {
        let (key, value) = TwoParameterTriggerCodec.convert(string: param)
        guard !key.contains(".") else {
            return nil
        }
        return (key.removingPrefix("user."), value)
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

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        paramWithBackreferencesReplaced(withValues: strings,
                                        absLine: lineNumber,
                                        scope: scopeProvider,
                                        useInterpolation: useInterpolation).then { [weak self] message in
            if let self = self, let (name, value) = self.variableNameAndValue(message as String) {
                scheduler.scheduleTriggerCallback {
                    session.triggerSession(self,
                                           setVariableNamed: "user." + name,
                                           toValue: value)
                }
            }
        }
        return true
    }

    override func paramIsTwoStrings() -> Bool {
        return true
    }
}
