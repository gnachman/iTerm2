//
//  BufferInputTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 12/12/25.
//


@objc(iTermBufferInputTrigger)
class BufferInputTrigger: Trigger {
    private enum Tag: Int {
        case start = 0
        case stop = 1
    }

    private var shouldBuffer: Bool {
        switch Tag(rawValue: (self.param as? NSNumber)?.intValue ?? 0) {
        case .none, .start:
            return true
        case .stop:
            return false
        }
    }
    override var description: String {
        if shouldBuffer {
            return "Buffer Input"
        } else {
            return "Stop Buffering Input"
        }
    }

    override static var title: String {
        return "Buffer Input…"
    }

    override func takesParameter() -> Bool {
        return true
    }

    override func paramIsPopupButton() -> Bool {
        true
    }

    override var isIdempotent: Bool {
        return true
    }

    override func index(for object: Any?) -> Int {
        return objectsSortedByValue(inDict: menuItemsForPoupupButton()!).firstIndex { obj in
            (obj as? NSNumber) == (object as? NSNumber)
        } ?? -1
    }

    override func object(at index: Int) -> Any? {
        let sorted = objectsSortedByValue(inDict: menuItemsForPoupupButton()!)
        return sorted[index]
    }

    override func menuItemsForPoupupButton() -> [AnyHashable : Any]? {
        [ NSNumber(value: Tag.start.rawValue): "Start Buffering Input",
          NSNumber(value: Tag.stop.rawValue): "Stop Buffering Input" ]
    }

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        session.triggerSetBufferInput(self, shouldBuffer: shouldBuffer)
        return false
    }

    override func paramAttributedString() -> NSAttributedString? {
        NSAttributedString(string: shouldBuffer ? "Start buffering" : "Stop buffering",
                           attributes: regularAttributes())
    }
}
