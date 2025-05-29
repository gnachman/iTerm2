//
//  AITermControllerRegistrationHelper.swift
//  iTerm2
//
//  Created by George Nachman on 6/5/25.
//

class AITermControllerRegistrationHelper {
    static var instance = AITermControllerRegistrationHelper()

    var registration: AITermController.Registration? {
        if !iTermAITermGatekeeper.allowed {
            return nil
        }
        return AITermController.Registration(apiKey: AITermControllerObjC.apiKey)
    }

    func setKey(_ key: String) {
        AITermControllerObjC.apiKey = key
    }

    func requestRegistration(in window: NSWindow, completion: @escaping (AITermController.Registration?) -> ()) {
        if !iTermAITermGatekeeper.check() {
            completion(nil)
            return
        }
        let windowController = AITermRegistrationWindowController.create()
        window.beginSheet(windowController.window!) { [weak self] response in
            windowController.window?.orderOut(nil)
            if response == .OK, let key = windowController.apiKey {
                self?.setKey(key)
            }
            if response == .OK, let registration = AITermController.Registration(apiKey: windowController.apiKey) {
                completion(registration)
            } else {
                completion(nil)
            }
        }
    }
}

@objc
class AITermRegistrationWindowController: NSWindowController {
    @IBOutlet var message: NSTextView!
    @IBOutlet var okButton: NSButton!
    @IBOutlet var textField: NSTextField!
    @IBOutlet var titleImageView: NSImageView!
    private(set) var apiKey: String?

    static func create() -> AITermRegistrationWindowController {
        return AITermRegistrationWindowController(windowNibName: NSNib.Name("AITerm"))
    }

    override func awakeFromNib() {
        var temp = message.string
        let urls = ["https://openai.com/join/",
                    "https://platform.openai.com/api-keys",
                    "https://iterm2.com/aiterm"]
        for (i, url) in urls.enumerated() {
            temp = temp.replacingOccurrences(of: "$\(i + 1)", with: url)
        }

        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let attributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
        ]

        let attributed = NSMutableAttributedString(string: temp, attributes: attributes)
        attributed.makeLinks()
        message.textStorage?.setAttributedString(attributed)
        super.awakeFromNib()
        okButton.isEnabled = !textField.stringValue.isEmpty
        titleImageView.image?.isTemplate = true

        DispatchQueue.main.async { [self] in
            self.window?.makeFirstResponder(textField)
        }
    }

    @IBAction func ok(_ sender: Any) {
        apiKey = textField.stringValue
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @IBAction func cancel(_ sender: Any) {
        apiKey = nil
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }
}

extension AITermRegistrationWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        DLog("\(link)")
        return true
    }
}

extension AITermRegistrationWindowController: NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        okButton.isEnabled = !textField.stringValue.isEmpty
    }
}

class AITermRegistrationWindow: NSWindow {
    override var acceptsFirstResponder: Bool {
        true
    }
    override var canBecomeKey: Bool {
        true
    }
    override var canBecomeMain: Bool {
        true
    }
}

protocol AIRegistrationProvider: AnyObject {
    func registrationProviderRequestRegistration(
        _ completion: @escaping (AITermController.Registration?) -> ())
}

extension NSWindow: AIRegistrationProvider {
    func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: self,
                                                                        completion: completion)
    }
}
