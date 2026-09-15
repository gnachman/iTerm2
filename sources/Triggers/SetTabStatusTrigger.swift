import Foundation

@objc(iTermSetTabStatusTrigger)
class SetTabStatusTrigger: Trigger, iTermColorSettable {
    // Parameter is encoded as three separator-delimited components:
    //   dotColorHex <sep> statusTextColorHex <sep> statusText
    private static let separator = "\u{1}"

    // MARK: - Parameter string helpers

    private static func split(param: Any?) -> (String, String, String) {
        guard let str = param as? String else { return ("", "", "") }
        let parts = str.components(separatedBy: Self.separator)
        return (parts.count > 0 ? parts[0] : "",
                parts.count > 1 ? parts[1] : "",
                parts.count > 2 ? parts[2] : "")
    }

    private var components: (String, String, String) {
        return Self.split(param: param)
    }

    private func encode(dotColor: String, textColor: String, statusText: String) -> String {
        [dotColor, textColor, statusText].joined(separator: Self.separator)
    }

    // MARK: - iTermColorSettable (textColor = dot color, backgroundColor = status text color)

    override var textColor: NSColor? {
        get {
            let hex = components.0
            return hex.isEmpty ? nil : NSColor(preservingColorspaceFrom: hex)
        }
        set {
            super.textColor = newValue
            let c = components
            param = encode(dotColor: newValue?.hexStringPreservingColorSpace() ?? "",
                           textColor: c.1,
                           statusText: c.2)
        }
    }

    override var backgroundColor: NSColor? {
        get {
            let hex = components.1
            return hex.isEmpty ? nil : NSColor(preservingColorspaceFrom: hex)
        }
        set {
            super.backgroundColor = newValue
            let c = components
            param = encode(dotColor: c.0,
                           textColor: newValue?.hexStringPreservingColorSpace() ?? "",
                           statusText: c.2)
        }
    }

    // MARK: - Trigger overrides

    override static var title: String { String(localized: "SetTabStatusTrigger.Title", defaultValue: "Set Tab Status…", comment: "Title of the set tab status trigger") }

    override func takesParameter() -> Bool { true }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return ""
    }

    override func paramIsComboBoxAndTwoColorWells() -> Bool { true }

    // MARK: - Canonical status mapping
    //
    // The STORED/canonical status value is the lowercase English wire-protocol
    // token ("work"/"wait"/"idle") so it matches
    // StatusPrioritySettings.defaultPatterns (["wait", "work", "idle"]). What
    // the UI shows is localized and capitalized. This table is the single
    // source of truth for both directions and for the render-time display of a
    // known wire value (including statuses that arrive over the wire).
    private static var canonicalStatuses: [(wire: String, display: String)] {
        [("work", String(localized: "SetTabStatusTrigger.Working", defaultValue: "Working", comment: "Combo box option for a working tab status")),
         ("wait", String(localized: "SetTabStatusTrigger.Waiting", defaultValue: "Waiting", comment: "Combo box option for a waiting tab status")),
         ("idle", String(localized: "SetTabStatusTrigger.Idle", defaultValue: "Idle", comment: "Combo box option for an idle tab status"))]
    }

    // Localized display string for a known wire value, else nil.
    private static func localizedDisplay(forWireValue wire: String) -> String? {
        canonicalStatuses.first { $0.wire == wire }?.display
    }

    // Wire value whose current-locale display equals the given string, else nil.
    private static func wireValue(forDisplayString display: String) -> String? {
        canonicalStatuses.first { $0.display == display }?.wire
    }

    /// Maps a stored/wire status value to its localized display string. Known
    /// wire values ("work"/"wait"/"idle") become the localized capitalized
    /// form; anything else (free text) passes through unchanged. Used by the
    /// tab subtitle, the Session Status tool, and the status-change alert so a
    /// canonical status renders in the user's language.
    @objc static func localizedStatusForDisplay(_ status: String?) -> String? {
        guard let status else { return nil }
        return localizedDisplay(forWireValue: status) ?? status
    }

    override func comboBoxItems() -> [String] {
        Self.canonicalStatuses.map { $0.display }
    }

    override func comboBoxValue(inParam param: Any?) -> String? {
        guard let str = param as? String else { return nil }
        let parts = str.components(separatedBy: Self.separator)
        guard parts.count > 2 else { return nil }
        let statusText = parts[2]
        // Show a stored wire value as its localized display string; leave free
        // text as typed.
        return Self.localizedDisplay(forWireValue: statusText) ?? statusText
    }

    override func textColor(inParam param: Any?) -> NSColor? {
        let components = Self.split(param: param)
        let hex = components.0
        return hex.isEmpty ? nil : NSColor(preservingColorspaceFrom: hex)
    }

    override func backgroundColor(inParam param: Any?) -> NSColor? {
        let components = Self.split(param: param)
        let hex = components.1
        return hex.isEmpty ? nil : NSColor(preservingColorspaceFrom: hex)
    }


    override func param(byReplacingComboBoxValue value: String, inParam param: Any?) -> Any? {
        let str = (param as? String) ?? ""
        let parts = str.components(separatedBy: Self.separator)
        let dotColor = parts.count > 0 ? parts[0] : ""
        let textColor = parts.count > 1 ? parts[1] : ""
        // When the user picks one of the localized suggestions, store the
        // canonical wire value so priority matching works. Free text is stored
        // as typed.
        let statusText = Self.wireValue(forDisplayString: value) ?? value
        return encode(dotColor: dotColor, textColor: textColor, statusText: statusText)
    }

    override var isIdempotent: Bool { true }

    override func paramAttributedString() -> NSAttributedString? {
        let statusText = components.2
        let text = statusText.isEmpty ? String(localized: "SetTabStatusTrigger.NoStatus", defaultValue: "(no status)", comment: "Placeholder shown when no status text is set") : statusText
        let result = NSMutableAttributedString(string: text, attributes: regularAttributes())

        if let dotColor = textColor {
            result.append(NSAttributedString(string: String(localized: "SetTabStatusTrigger.DotLabel", defaultValue: "  Dot: ", comment: "Label preceding the dot color swatch"), attributes: regularAttributes()))
            appendColorSwatch(dotColor, to: result)
        }
        if let statusTextColor = backgroundColor {
            result.append(NSAttributedString(string: String(localized: "SetTabStatusTrigger.TextLabel", defaultValue: "  Text: ", comment: "Label preceding the status text color swatch"), attributes: regularAttributes()))
            appendColorSwatch(statusTextColor, to: result)
        }
        return result
    }

    private func appendColorSwatch(_ color: NSColor, to result: NSMutableAttributedString) {
        let attachment = NSTextAttachment()
        attachment.image = NSImage.it_image(forColorSwatch: color, size: NSSize(width: 22, height: 14))
        let attachmentString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        attachmentString.addAttribute(.baselineOffset, value: -2, range: NSRange(location: 0, length: attachmentString.length))
        result.append(attachmentString)
    }

    // MARK: - Action

    override func performAction(withCapturedStrings strings: [String],
                                capturedRanges: UnsafePointer<NSRange>,
                                in session: any iTermTriggerSession,
                                onString s: iTermStringLine,
                                atAbsoluteLineNumber lineNumber: Int64,
                                useInterpolation: Bool,
                                stop: UnsafeMutablePointer<ObjCBool>) -> Bool {
        let scopeProvider = session.triggerSessionVariableScopeProvider(self)
        let scheduler = scopeProvider.triggerCallbackScheduler()
        let textColor = self.textColor
        let components = self.components
        let backgroundColor = self.backgroundColor
        promisedValue(ofInterpolatedString: components.2,
                      withBackreferencesReplacedWithValues: strings,
                      absLine: lineNumber,
                      scope: scopeProvider,
                      useInterpolation: useInterpolation).then { [weak self] message in
            scheduler.scheduleTriggerCallback {
                if let self {
                    let update = VT100TabStatusUpdate()

                    if let dotColor = textColor?.usingColorSpace(.sRGB) {
                        update.indicatorPresence = .set
                        update.indicator = iTermSRGBColor(r: dotColor.redComponent,
                                                          g: dotColor.greenComponent,
                                                          b: dotColor.blueComponent)
                    }

                    let statusText = message as String
                    if !statusText.isEmpty {
                        update.statusPresence = .set
                        update.status = statusText
                    }

                    if let color = backgroundColor?.usingColorSpace(.sRGB) {
                        update.statusColorPresence = .set
                        update.statusColor = iTermSRGBColor(r: color.redComponent,
                                                            g: color.greenComponent,
                                                            b: color.blueComponent)
                    }

                    session.triggerSession(self, setTabStatus: update)
                }
            }
        }
        return true
    }
}
