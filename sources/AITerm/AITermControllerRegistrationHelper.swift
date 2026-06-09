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
        return registration(for: LLMMetadata.effectiveVendor)
    }

    func registration(for vendor: iTermAIVendor) -> AITermController.Registration? {
        if !iTermAITermGatekeeper.allowed {
            return nil
        }
        return AITermController.Registration(apiKey: AITermControllerObjC.apiKey(for: vendor),
                                             vendor: vendor)
    }

    func setKey(_ key: String) {
        setKey(key, for: LLMMetadata.effectiveVendor)
    }

    func setKey(_ key: String, for vendor: iTermAIVendor) {
        AITermControllerObjC.setAPIKey(key, for: vendor)
    }

    func requestRegistration(in window: NSWindow, completion: @escaping (AITermController.Registration?) -> ()) {
        requestRegistration(in: window, for: LLMMetadata.effectiveVendor, completion: completion)
    }

    func requestRegistration(in window: NSWindow,
                             for vendor: iTermAIVendor,
                             completion: @escaping (AITermController.Registration?) -> ()) {
        if !iTermAITermGatekeeper.check() {
            completion(nil)
            return
        }
        if let registration = registration(for: vendor) {
            completion(registration)
            return
        }
        let windowController = AITermRegistrationWindowController.create(vendor: vendor)
        window.beginSheet(windowController.window!) { [weak self] response in
            windowController.window?.orderOut(nil)
            if response == .OK, let key = windowController.apiKey {
                self?.setKey(key, for: vendor)
            }
            if response == .OK,
               let registration = AITermController.Registration(apiKey: windowController.apiKey,
                                                                vendor: vendor) {
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
    private var vendor = LLMMetadata.effectiveVendor

    static func create() -> AITermRegistrationWindowController {
        create(vendor: LLMMetadata.effectiveVendor)
    }

    static func create(vendor: iTermAIVendor) -> AITermRegistrationWindowController {
        let controller = AITermRegistrationWindowController(windowNibName: NSNib.Name("AITerm"))
        controller.vendor = vendor
        return controller
    }

    override func awakeFromNib() {
        var temp = message.string
        let urls = switch vendor {
        case .openAI, .llama:
            ["https://auth.openai.com/create-account",
             "https://platform.openai.com/api-keys",
             "https://iterm2.com/aiterm",
             "OpenAI"]
        case .anthropic:
            ["https://console.anthropic.com/login",
             "https://console.anthropic.com/settings/keys",
             "https://iterm2.com/aiterm",
             "Claude"]
        case .deepSeek:
            ["https://chat.deepseek.com/sign_up",
             "https://platform.deepseek.com/api_keys",
             "https://iterm2.com/aiterm",
             "Deep Seek"]
        case .gemini:
            ["https://aistudio.google.com/prompts/new_chat",
             "https://aistudio.google.com/app/api-keys",
             "https://iterm2.com/aiterm",
             "Gemini"]
        case .apple:
            // Apple Intelligence runs on-device and needs no API key, so this
            // registration dialog is never shown for it. Present harmless
            // placeholders to keep the switch exhaustive.
            ["https://support.apple.com/apple-intelligence",
             "https://support.apple.com/apple-intelligence",
             "https://iterm2.com/aiterm",
             "Apple Intelligence"]
        @unknown default:
            it_fatalError()
        }
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

extension AIRegistrationProvider {
    func registrationProviderRequestRegistration(for vendor: iTermAIVendor,
                                                 _ completion: @escaping (AITermController.Registration?) -> ()) {
        registrationProviderRequestRegistration(completion)
    }
}

extension NSWindow: AIRegistrationProvider {
    func registrationProviderRequestRegistration(_ completion: @escaping (AITermController.Registration?) -> ()) {
        registrationProviderRequestRegistration(for: LLMMetadata.effectiveVendor, completion)
    }

    func registrationProviderRequestRegistration(for vendor: iTermAIVendor,
                                                 _ completion: @escaping (AITermController.Registration?) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: self,
                                                                        for: vendor,
                                                                        completion: completion)
    }
}
