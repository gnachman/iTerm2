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

    override static var title: String { "Set Tab Status…" }

    override func takesParameter() -> Bool { true }

    override func triggerOptionalParameterPlaceholder(withInterpolation interpolation: Bool) -> String? {
        return ""
    }

    override func paramIsComboBoxAndTwoColorWells() -> Bool { true }

    override func comboBoxItems() -> [String] {
        ["Working", "Waiting", "Idle"]
    }

    override func comboBoxValue(inParam param: Any?) -> String? {
        guard let str = param as? String else { return nil }
        let parts = str.components(separatedBy: Self.separator)
        return parts.count > 2 ? parts[2] : nil
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
        return encode(dotColor: dotColor, textColor: textColor, statusText: value)
    }

    override var isIdempotent: Bool { true }

    override func paramAttributedString() -> NSAttributedString? {
        let statusText = components.2
        let text = statusText.isEmpty ? "(no status)" : statusText
        let result = NSMutableAttributedString(string: text, attributes: regularAttributes())

        if let dotColor = textColor {
            result.append(NSAttributedString(string: "  Dot: ", attributes: regularAttributes()))
            appendColorSwatch(dotColor, to: result)
        }
        if let statusTextColor = backgroundColor {
            result.append(NSAttributedString(string: "  Text: ", attributes: regularAttributes()))
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
