import Foundation

@objc(iTermSessionNoteModel)
class SessionNoteModel: NSObject {
    @objc static let textDidChangeNotification = NSNotification.Name("iTermSessionNoteModelTextDidChange")

    @objc var text: String = "" {
        didSet {
            if text != oldValue {
                generation += 1
                NotificationCenter.default.post(name: SessionNoteModel.textDidChangeNotification,
                                                object: self)
            }
        }
    }

    @objc private(set) var generation: Int = 0

    /// The full (expanded) frame, even when currently collapsed.
    @objc var noteFrame: NSRect = NSRect.zero {
        didSet {
            if !NSEqualRects(noteFrame, oldValue) {
                generation += 1
            }
        }
    }

    @objc var isCollapsed: Bool = false {
        didSet {
            if isCollapsed != oldValue {
                generation += 1
            }
        }
    }

    @objc var hasContent: Bool {
        return !text.isEmpty
    }

    // MARK: - Graph Encoder Encoding

    @objc(encodeWithAdapter:)
    func encode(with encoder: any iTermEncoderAdapter) {
        encoder.setObject(text as NSString, forKey: "text")
        encoder.setObject(NSNumber(value: isCollapsed), forKey: "collapsed")
        encoder.setObject(NSStringFromRect(noteFrame) as NSString, forKey: "frame")
    }

    // MARK: - Arrangement Restoration

    @objc(fromArrangement:)
    static func fromArrangement(_ dict: NSDictionary) -> SessionNoteModel? {
        guard let text = dict["text"] as? String else {
            return nil
        }
        let model = SessionNoteModel()
        model.text = text
        model.isCollapsed = (dict["collapsed"] as? NSNumber)?.boolValue ?? false
        if let frameString = dict["frame"] as? String {
            model.noteFrame = NSRectFromString(frameString)
        }
        return model
    }
}
