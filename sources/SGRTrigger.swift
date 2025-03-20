//
//  SGRTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 3/19/25.
//

import Foundation

@objc(iTermSGRTrigger)
class SGRTrigger: Trigger {
    override var description: String {
        return "Change Style “\(self.param ?? "")”"
    }

    override static var title: String {
        return "Change Style…"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return "Enter SGR codes. See help button for details."
    }

    override var helpText: String? {
        """
        A sequence of SGR codes specifying the style to apply. Codes are delimited by semicolons. For example, to change text to be bold and red you’d use `1;31`. You may use the following codes:
        
        ```
        Numeric Code    Description
        ------------    --------------------------
                   0    Normal (default         

                   1    Bold
                   2    Faint
                  22    Reset bold and faint

                   3    Italicized
                  23    Not italicized

                   4    Single underline
                  21    Doubly underlined
                 4:3    Curly underline
                  24    Not underlined

        58:2:1:R:G:B    24-bit underline color. 
                        R, G, and B are values in 0…255.
              58:5:I    8-bit underline color. 
                        I is a value in 0…255.
        
                   5    Blink
                  25    Reset blink

                   7    Inverse
                  27    Reset inverse

                   8    Invisible
                  28    Reset invisible

                   9    Crossed-out
                  29    Not crossed-out

                  30    Black text color
                  31    Red text color
                  32    Green text color
                  33    Yellow text color
                  34    Blue text color
                  35    Magenta text color
                  36    Cyan text color
                  37    White text color
                  39    Default text color

                  40    Black background color
                  41    Red background color
                  42    Green background color
                  43    Yellow background color
                  44    Blue background color
                  45    Magenta background color
                  46    Cyan background color
                  47    White background color
                  49    Default background color

                  90    Bright Black text color
                  91    Bright Red text
                  92    Bright Green text color
                  93    Bright Yellow text color
                  94    Bright Blue text color
                  95    Bright Magenta text color
                  96    Bright Cyan text color
                  97    Bright White text color

                 100    Bright Black background color
                 101    Bright Red background
                 102    Bright Green background color
                 103    Bright Yellow background color
                 104    Bright Blue background color
                 105    Bright Magenta background color
                 106    Bright Cyan background color
                 107    Bright White background color

        38:2:1:R:G:B    24-bit text color. 
                        R, G, and B are values in 0…255.
        48:2:1:R:G:B    24-bit background color. 
                        R, G, and B are values in 0…255.
              38;5;I    8-bit text color. 
                        I is a value in 0…255.
              48;5;I    8-bit background color. 
                        I is a value in 0…255.
        """
    }

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let range = s.rangeOfScreenCharsForRange(inString: capturedRanges[0])
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        paramWithBackreferencesReplaced(withValues: strings,
                                        absLine: lineNumber,
                                        scope: scopeProvider,
                                        useInterpolation: useInterpolation).then { message in
            scheduler.scheduleTriggerCallback {
                let majorParts = (message as String).components(separatedBy: ";")
                let subsList = majorParts.compactMap { subList -> [Int32] in
                    subList.components(separatedBy: ":").compactMap { Int32($0) }
                }
                var csi = CSIParam()
                for subs in subsList {
                    iTermParserAddCSIParameter(&csi, subs.first ?? -1)
                    for sub in subs.dropFirst() {
                        iTermParserAddCSISubparameter(&csi, csi.count - 1, sub)
                    }
                }
                csi.cmd = Int32("m".firstASCIICharacter)
                session.triggerSession(self, setRange: range, absoluteLine: lineNumber, sgr: csi);
            }
        }
        return false
    }
}
