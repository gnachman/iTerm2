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

    override var description: String {
        if let string = param as? String, let (name, value) = variableNameAndValue(string) {
            return String(localized: "SetUserVariableTrigger.DescriptionNameValue", defaultValue: "Set User Variable “\(name)” to “\(value)”", comment: "Description of a Set User Variable trigger; first interpolation is the variable name, second is the value")
        } else {
            return String(localized: "SetUserVariableTrigger.DescriptionName", defaultValue: "Set User Variable “\(String(describing: param ?? ""))”", comment: "Description of a Set User Variable trigger; interpolated value is the variable name")
        }
    }

    override static var title: String {
        return String(localized: "SetUserVariableTrigger.Title", defaultValue: "Set User Variable…", comment: "Menu title for the Set User Variable trigger action")
    }

    override func takesParameter() -> Bool {
        return true
    }

    override var allowedMatchTypes: Set<NSNumber> {
        var set: Set<NSNumber> = [NSNumber(value: iTermTriggerMatchType.regex.rawValue)]
        set.formUnion(EventTriggerMatchTypeHelper.allEventTypesSet)
        return set
    }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return String(localized: "SetUserVariableTrigger.ValuePlaceholder", defaultValue: "Value for variable", comment: "Placeholder text for the value field of a Set User Variable trigger")
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

    override func paramAttributedString() -> NSAttributedString? {
        if let string = param as? String, let (name, value) = variableNameAndValue(string) {
            return NSAttributedString(string: String(localized: "SetUserVariableTrigger.NameEqualsValue", defaultValue: "\(name) = \(value)", comment: "Compact display of a Set User Variable trigger; shows variable name = value"), attributes: regularAttributes())
        } else {
            return NSAttributedString(string: (param as? String) ?? "", attributes: regularAttributes())
        }
    }
}
