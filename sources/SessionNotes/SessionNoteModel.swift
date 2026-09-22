import Foundation

@objc(iTermSessionNoteAPIUpdate)
final class SessionNoteAPIUpdate: NSObject {
    let text: String?
    let visible: Bool?
    let collapsed: Bool?

    @objc var hasText: Bool { text != nil }
    @objc var textValue: String { text ?? "" }
    @objc var hasVisible: Bool { visible != nil }
    @objc var visibleValue: Bool { visible ?? false }
    @objc var hasCollapsed: Bool { collapsed != nil }
    @objc var collapsedValue: Bool { collapsed ?? false }

    private init(text: String?, visible: Bool?, collapsed: Bool?) {
        self.text = text
        self.visible = visible
        self.collapsed = collapsed
    }

    @objc(parse:)
    static func parse(_ object: Any) -> SessionNoteAPIUpdate? {
        guard let dictionary = object as? NSDictionary,
              dictionary.count > 0 else {
            return nil
        }

        let allowedKeys = Set(["text", "visible", "collapsed"])
        let keys = dictionary.allKeys.compactMap { $0 as? String }
        guard keys.count == dictionary.count,
              Set(keys).isSubset(of: allowedKeys) else {
            return nil
        }

        var text: String?
        if let value = dictionary["text"] {
            guard let string = value as? String else {
                return nil
            }
            text = string
        }

        func strictBoolean(_ key: String) -> Bool?? {
            guard let value = dictionary[key] else {
                return .some(nil)
            }
            guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
                  let number = value as? NSNumber else {
                return nil
            }
            return .some(number.boolValue)
        }

        guard let visible = strictBoolean("visible"),
              let collapsed = strictBoolean("collapsed") else {
            return nil
        }
        return SessionNoteAPIUpdate(text: text, visible: visible, collapsed: collapsed)
    }
}

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
