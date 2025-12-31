//
//  iTermSettingsColorWell.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/25.
//

import Foundation
import ColorPicker

@objc(iTermSettingsColorWell)
class SettingsColorWell: CPKColorWell {
    private var textFieldDelegate: iTermFunctionCallTextFieldDelegate?
    @objc var bindingDidChange: ((String?) -> ())?
    @objc var expression: String? {
        didSet {
            if expression != oldValue {
                DLog("Change to \(expression ?? "(nil)")")
                updateIcon()
            }
        }
    }
    @objc var typeHelp: String?
    private var iconContainerView: NSView?
    private var iconView: NSImageView?
}

extension SettingsColorWell {
    override func rightMouseDown(with event: NSEvent) {
        guard bindingDidChange != nil else {
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem(title: expression == nil ? "Bind to Expression" : "Edit Expression Binding",
                              action: #selector(editBinding(_:)),
                              keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateIcon()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        if let iconContainerView {
            let cSize = iconContainerView.frame.size
            let cOrigin = NSPoint(x: 32 - cSize.width - 2, y: 2)
            var frame = iconContainerView.frame
            frame.origin = cOrigin
            iconContainerView.frame = frame
        }
    }
}

extension SettingsColorWell {
    private var iconSize: NSSize {
        NSSize(width: 10, height: 10)
    }
    private var iconContainerInset: CGFloat { 2.0 }

    private func updateIcon() {
        if expression?.isEmpty != false {
            iconContainerView?.removeFromSuperview()
            iconContainerView = nil
            iconView = nil
            return
        }
        if iconContainerView != nil {
            return
        }

        let inset = iconContainerInset
        let iSize = iconSize
        let cSize = NSSize(width: iSize.width + inset * 2,
                           height: iSize.height + inset * 2)
        let cOrigin = NSPoint(x: 32 - cSize.width - 2, y: 2)
        DLog("inset=\(inset) iconSize=\(iSize) containerSize=\(cSize)")

        // Create container view with styling
        let containerView = NSView(frame: NSRect(origin: cOrigin, size: cSize))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.white.cgColor
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerRadius = cSize.width / 2
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.gray.cgColor

        // Create icon view inside container
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconSize.height * 0.8,
                                                       weight: .regular)
        let image = NSImage(
            systemSymbolName: "link",
            accessibilityDescription: "Expression Binding")?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.frame = NSRect(x: inset,
                                 y: inset,
                                 width: iconSize.width,
                                 height: iconSize.height)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .black

        containerView.addSubview(imageView)
        addSubview(containerView)

        self.iconContainerView = containerView
        self.iconView = imageView
    }

    @objc
    private func editBinding(_ sender: Any) {
        guard let window else {
            return
        }

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.isEditable = true
        textField.isSelectable = true
        textField.stringValue = expression ?? ""
        textField.placeholderString = "Expression (e.g., user.bgColor)"

        let pathSource = iTermVariableHistory.pathSource(for: .session)
        textFieldDelegate = iTermFunctionCallTextFieldDelegate(
            forExpressionsWithPathSource: pathSource,
            passthrough: nil)
        textField.delegate = textFieldDelegate

        let alert = NSAlert()
        alert.messageText = "Bind Expression to Setting"
        alert.informativeText = "Enter expression to bind to this setting, or leave empty to clear the binding."
        alert.accessoryView = textField
        alert.layout()
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(textField)
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.showsHelp = true
        alert.delegate = self
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                let newBinding: String? = if textField.stringValue.isEmpty {
                    nil
                } else {
                    textField.stringValue
                }
                self?.expression = textField.stringValue
                self?.bindingDidChange?(newBinding)
            default:
                DLog("Cancel \(response)")
            }
        }
    }
}

extension SettingsColorWell: NSAlertDelegate {
    func alertShowHelp(_ sender: NSAlert) -> Bool {
        let optionalTypeHelp = if let typeHelp {
            """
            ### For This Setting
            \(typeHelp)
            
            
            """
        } else {
            ""
        }
        sender.accessoryView?.it_showInformativeMessage(withMarkdown:
                                                            optionalTypeHelp +
            """
            ### Background
            Binding a setting to an expression lets you change settings programatically.
            
            iTerm2 tracks a collection of “Variables” for each session. You can learn more about them in [Scripting Fundamentals](https://iterm2.com/documentation-scripting-fundamentals.html).
            
            Typically this feature is used by binding a setting to a user-defined variable.
            
            ### Example
            The easiest way to set a user-defined variable is to install shell integration and then define a `iterm2_print_user_vars` function. Here's an example using bash:
            
            ```
            iterm2_print_user_vars() {
              iterm2_set_user_var bgColor $(echo $ITERM2_BACKGROUND_COLOR)
            }
            ```
            
            This runs each time the shell prompt is printed. The example sets a user-defined variable to the value of the environment variable `ITERM2_BACKGROUND_COLOR`.
            
            The appropriate expression to bind this example would be `user.bgColor`. All user-defined variables go in the `user` scope.
            
            ### Debugging
            You can view variables in the Inspector (**Scripts > Manage > Console** and then click **Inspector**).
            """)
        return true
    }
}
