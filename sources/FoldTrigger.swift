//
//  FoldTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 12/31/24.
//

@objc(iTermFoldTrigger)
class FoldTrigger: Trigger {
    override var description: String {
        return "Fold to \(self.param ?? "")"
    }

    override static var title: String {
        return "Fold to Named Mark"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return "Name of Mark"
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
            scheduler.scheduleTriggerCallback {
                if let self {
                    session.triggerSession(self,
                                           foldFromNamedMark: message as String,
                                           toAbsoluteLine: lineNumber)
                }
            }
        }
        return true
    }
}
