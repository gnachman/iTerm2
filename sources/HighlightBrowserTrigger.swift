//
//  HighlightBrowserTrigger.swift
//  iTerm2
//
//  Created by George Nachman on 8/3/25.
//

class HighlightBrowserTrigger: Trigger, iTermColorSettable {
    override var description: String {
        "Highlight Text"
    }
    override static var title: String {
        "Highlight Text"
    }
    override func takesParameter() -> Bool {
        true
    }
    override func paramIsPopupButton() -> Bool {
        false
    }
    override func paramIsTwoColorWells() -> Bool {
        true
    }
    var colors: (String, String) {
        if let components = (param as? String)?.components(separatedBy: ";"), components.count >= 2 {
            return (components[0], components[1])
        }
        return ("", "")
    }
    @objc
    override var textColor: NSColor? {
        get {
            let c = colors
            if c.0.isEmpty {
                return nil
            }
            return NSColor(preservingColorspaceFrom: c.0)
        }
        set {
            super.textColor = newValue
            param = [newValue?.hexStringPreservingColorSpace() ?? "", colors.1].joined(separator: ";")
        }
    }
    @objc
    override var backgroundColor: NSColor? {
        get {
            let c = colors
            if c.1.isEmpty {
                return nil
            }
            return NSColor(preservingColorspaceFrom: c.1)
        }
        set {
            super.textColor = newValue
            param = [colors.0, newValue?.hexStringPreservingColorSpace() ?? ""].joined(separator: ";")
        }
    }
    override func paramAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()

        result.append(NSAttributedString(string:"Text: "))

        let textColorAttachment = NSTextAttachment()
        textColorAttachment.image = image(for: self.textColor)
        let textAttachmentString = NSAttributedString(attachment: textColorAttachment)
        let mutableTextAttachmentString = textAttachmentString.mutableCopy() as! NSMutableAttributedString
        // Lower the image by adjusting the baseline offset.
        mutableTextAttachmentString.addAttribute(.baselineOffset,
                                                 value: -2,
                                                 range: NSRange(0..<mutableTextAttachmentString.length))
        result.append(mutableTextAttachmentString)

        result.append(NSAttributedString(string: " Background: "))

        let backgroundColorAttachment = NSTextAttachment()
        backgroundColorAttachment.image = image(for: backgroundColor)
        let backgroundAttachmentString = NSAttributedString(attachment: backgroundColorAttachment)
        let mutableBackgroundAttachmentString = backgroundAttachmentString.mutableCopy() as! NSMutableAttributedString
        // Lower the image by adjusting the baseline offset.
        mutableBackgroundAttachmentString.addAttribute(.baselineOffset,
                                                       value: -2,
                                                       range: NSRange(0..<mutableBackgroundAttachmentString.length))
        result.append(mutableBackgroundAttachmentString)

        return result;
    }

    private func image(for color: NSColor?) -> NSImage {
        return NSImage.it_image(forColorSwatch: color, size: NSSize(width: 22, height: 14))
    }
}

extension HighlightBrowserTrigger: BrowserTrigger {
    func performBrowserAction(urlCaptures: [String],
                              contentCaptures: [String]?,
                              in client: any BrowserTriggerClient) async -> [BrowserTriggerAction] {
        let colors = self.colors
        let regex = contentRegex
        let scheduler = client.scopeProvider.triggerCallbackScheduler()
        paramWithBackreferencesReplaced(withValues: urlCaptures + (contentCaptures ?? []),
                                        absLine: -1,
                                        scope: client.scopeProvider,
                                        useInterpolation: client.useInterpolation).then { message in
            scheduler.scheduleTriggerCallback {
                client.triggerDelegate?.browserTriggerHighlightText(regex: regex,
                                                                    textColor: colors.0.nilIfEmpty,
                                                                    backgroundColor: colors.1.nilIfEmpty)
            }
        }
        return []
    }
}

extension String {
    var nilIfEmpty: String? {
        if isEmpty {
            nil
        } else {
            self
        }
    }
}

