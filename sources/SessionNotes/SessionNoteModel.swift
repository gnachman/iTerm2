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

    /// Posted when a session swaps one note model for another (including for no model at all).
    /// Observers that hold onto a model need this so they stop editing one the session has dropped.
    /// The object is the PTYSession whose model changed.
    @objc static let modelDidChangeNotification = NSNotification.Name("iTermSessionNoteModelDidChange")

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

    /// Raises `generation` so it is strictly greater than `floor`. A session calls this when it
    /// installs a replacement model, so the delta encoder never sees the new model at the same
    /// generation as the record it saved for the old one.
    @objc(advanceGenerationPast:)
    func advanceGeneration(past floor: Int) {
        if generation <= floor {
            generation = floor + 1
        }
    }

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

    /// Whether the note is showing over the terminal. SessionView owns the real answer, since it
    /// either has a note view or it does not; this mirrors it for two reasons. It lets visibility be
    /// saved in an arrangement, and because the delta encoder reuses the previously encoded record
    /// whenever `generation` has not moved, a mirrored property is what makes a show or hide reach
    /// disk at all.
    @objc var isVisible: Bool = false {
        didSet {
            if isVisible != oldValue {
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
        encoder.setObject(NSNumber(value: isVisible), forKey: "visible")
        encoder.setObject(NSStringFromRect(noteFrame) as NSString, forKey: "frame")
        // The delta encoder reuses the saved record whenever the generation it is handed equals the
        // record's. A restored model must therefore pick up where the saved one left off; if it
        // restarted near zero it could later land exactly on the record's generation and the
        // encoder would keep the stale record instead of the user's edits.
        encoder.setObject(NSNumber(value: generation), forKey: "generation")
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
        // Arrangements written before visibility was saved always came back showing, so default to
        // true rather than hiding a note those users expect to see.
        model.isVisible = (dict["visible"] as? NSNumber)?.boolValue ?? true
        if let frameString = dict["frame"] as? String {
            model.noteFrame = NSRectFromString(frameString)
        }
        // Last, after the property sets above have done their own bumping, so the restored model
        // is never behind the record it was saved in. Arrangements from older builds lack the key.
        if let saved = (dict["generation"] as? NSNumber)?.intValue {
            model.advanceGeneration(past: saved - 1)
        }
        return model
    }
}
