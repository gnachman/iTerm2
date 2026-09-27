//
//  ExpressionBindableView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/25.
//

import Foundation

@objc(iTermExpressionBindableView)
protocol ExpressionBindableView: AnyObject {
    @objc var bindingDidChange: ((String?) -> ())? { get set }
    @objc var expression: String? { get set }
    @objc var typeHelp: String? { get set }
    var textFieldDelegate: iTermFunctionCallTextFieldDelegate? { get set }
    @objc func editBinding(_ sender: Any)
    @objc func removeBinding(_ sender: Any)
    var iconContainerView: ExpressionBindingIconView? { get set }
    func iconOrigin(size: NSSize) -> NSPoint
}

extension ExpressionBindableView where Self: NSView, Self: NSAlertDelegate {
    func handleRightMouseDown(with event: NSEvent, view: NSView) {
        guard bindingDidChange != nil else {
            return
        }
        let menu = NSMenu()
        let hasExpression = (expression?.isEmpty == false)
        do {
            let item = NSMenuItem(title: hasExpression ? String(localized: "ExpressionBindableView.EditBinding", defaultValue: "Edit Expression Binding", comment: "Menu item to edit an existing expression binding") : String(localized: "ExpressionBindableView.BindToExpression", defaultValue: "Bind to Expression", comment: "Menu item to bind a setting to an expression"),
                                  action: #selector(editBinding(_:)),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if hasExpression {
            let item = NSMenuItem(title: String(localized: "ExpressionBindableView.RemoveBinding", defaultValue: "Remove Expression Binding", comment: "Menu item to remove an expression binding"),
                                  action: #selector(removeBinding(_:)),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func set(binding: String?) {
        if let binding, binding.isEmpty {
            set(binding: nil)
            return
        }
        expression = binding
        bindingDidChange?(binding)
    }

    func removeBinding() {
        set(binding: nil)
    }

    func editBinding(example: String) {
        guard let window else {
            return
        }

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 24))
        textField.isEditable = true
        textField.isSelectable = true
        textField.stringValue = expression ?? ""
        textField.placeholderString = String(localized: "ExpressionBindableView.ExpressionPlaceholder", defaultValue: "Expression (e.g., \(example))", comment: "Placeholder text for the expression input field")

        let pathSource = iTermVariableHistory.pathSource(for: .session)
        textFieldDelegate = iTermFunctionCallTextFieldDelegate(
            forExpressionsWithPathSource: pathSource,
            passthrough: nil)
        textField.delegate = textFieldDelegate

        let alert = NSAlert()
        alert.messageText = String(localized: "ExpressionBindableView.BindMessageText", defaultValue: "Bind Expression to Setting", comment: "Title of the dialog for binding a setting to an expression")
        alert.informativeText = String(localized: "ExpressionBindableView.BindInformativeText", defaultValue: "Enter expression to bind to this setting, or leave empty to clear the binding.", comment: "Explanation in the dialog for binding a setting to an expression")
        alert.accessoryView = textField
        alert.layout()
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(textField)
        }
        alert.addButton(withTitle: iTermLocalizedOK())
        alert.addButton(withTitle: iTermLocalizedCancel())
        alert.showsHelp = true
        alert.delegate = self
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                self?.set(binding: textField.stringValue)
            default:
                DLog("Cancel \(response)")
            }
        }
    }

    func updateIcon() {
        if expression?.isEmpty != false {
            iconContainerView?.removeFromSuperview()
            iconContainerView = nil
            return
        }
        if iconContainerView != nil {
            return
        }

        let containerSize = ExpressionBindingIconView.preferredSize
        let containerOrigin = iconOrigin(size: containerSize)

        let containerView = ExpressionBindingIconView(frame: NSRect(origin: containerOrigin,
                                                                    size: containerSize))
        addSubview(containerView)

        self.iconContainerView = containerView
    }
}

extension ExpressionBindableView {
    func showHelp(alert: NSAlert, exampleUserVar: String, exampleEnvironmentVar: String) -> Bool {
        let optionalTypeHelp = if let typeHelp {
            String(localized: "ExpressionBindableView.HelpForThisSetting", defaultValue: """
            ### For This Setting
            \(typeHelp)


            """, comment: "Help section header describing the current setting's expression binding")
        } else {
            ""
        }
        alert.accessoryView?.it_showInformativeMessage(withMarkdown:
                                                            optionalTypeHelp +
            String(localized: "ExpressionBindableView.HelpBackground", defaultValue: """
            ### Background
            Binding a setting to an expression lets you change settings programmatically.
            
            iTerm2 tracks a collection of “Variables” for each session. You can learn more about them in [Scripting Fundamentals](https://iterm2.com/documentation-scripting-fundamentals.html).
            
            Typically this feature is used by binding a setting to a user-defined variable.
            
            ### Example
            The easiest way to set a user-defined variable is to install shell integration and then define a `iterm2_print_user_vars` function. Here's an example using bash:
            
            ```
            iterm2_print_user_vars() {
              iterm2_set_user_var \(exampleUserVar) $(echo $\(exampleEnvironmentVar))
            }
            ```
            
            This runs each time the shell prompt is printed. The example sets a user-defined variable to the value of the environment variable `\(exampleEnvironmentVar)`.
            
            The appropriate expression to bind this example would be `user.\(exampleUserVar)`. All user-defined variables go in the `user` scope.
            
            ### Debugging
            You can view variables in the Inspector (**Scripts > Manage > Console** and then click **Inspector**).
            """, comment: "Help text explaining how to bind a setting to an expression"))
        return true
    }
}
