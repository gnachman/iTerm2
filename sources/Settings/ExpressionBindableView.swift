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
            let item = NSMenuItem(title: hasExpression ? String(localized: "ExpressionBindableView_EditExpressionBinding", defaultValue: "Edit Expression Binding", comment: "Menu item title in handleRightMouseDown") : String(localized: "ExpressionBindableView_BindToExpression", defaultValue: "Bind to Expression", comment: "Menu item title in handleRightMouseDown"),
                                  action: #selector(editBinding(_:)),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if hasExpression {
            let item = NSMenuItem(title: String(localized: "ExpressionBindableView_RemoveExpressionBinding", defaultValue: "Remove Expression Binding", comment: "Menu item title in handleRightMouseDown"),
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
        textField.placeholderString = String(format: String(localized: "ExpressionBindableView_ExpressionEG_FORMAT", defaultValue: "Expression (e.g., %1$@)", comment: "Placeholder text in editBinding"), example)

        let pathSource = iTermVariableHistory.pathSource(for: .session)
        textFieldDelegate = iTermFunctionCallTextFieldDelegate(
            forExpressionsWithPathSource: pathSource,
            passthrough: nil)
        textField.delegate = textFieldDelegate

        let alert = NSAlert()
        alert.messageText = String(localized: "ExpressionBindableView_BindExpressionToSetting", defaultValue: "Bind Expression to Setting", comment: "Alert title in editBinding")
        alert.informativeText = String(localized: "ExpressionBindableView_EnterExpressionToBindToThisSetting", defaultValue: "Enter expression to bind to this setting, or leave empty to clear the binding.", comment: "Alert explanatory text in editBinding")
        alert.accessoryView = textField
        alert.layout()
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(textField)
        }
        alert.addButton(withTitle: String(localized: "COMMON_OK", defaultValue: "OK", comment: "Button title in editBinding"))
        alert.addButton(withTitle: String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Button title in editBinding"))
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
            String(
                format: String(localized: "EXPRESSION_BINDING_FOR_THIS_SETTING_FORMAT",
                               defaultValue: "### For This Setting\n%1$@\n\n",
                               comment: "Markdown help section title followed by the setting-specific explanation"),
                typeHelp)
        } else {
            ""
        }
        alert.accessoryView?.it_showInformativeMessage(withMarkdown:
                                                            optionalTypeHelp +
            String(
                format: String(localized: "EXPRESSION_BINDING_HELP_FORMAT",
                               defaultValue: """
                               ### Background
                               Binding a setting to an expression lets you change settings programmatically.

                               iTerm2 tracks a collection of “Variables” for each session. You can learn more about them in [Scripting Fundamentals](https://iterm2.com/documentation-scripting-fundamentals.html).

                               Typically this feature is used by binding a setting to a user-defined variable.

                               ### Example
                               The easiest way to set a user-defined variable is to install shell integration and then define a `iterm2_print_user_vars` function. Here's an example using bash:

                               ```
                               iterm2_print_user_vars() {
                                 iterm2_set_user_var %1$@ $(echo $(%2$@))
                               }
                               ```

                               This runs each time the shell prompt is printed. The example sets a user-defined variable to the value of the environment variable `%3$@`.

                               The appropriate expression to bind this example would be `user.%4$@`. All user-defined variables go in the `user` scope.

                               ### Debugging
                               You can view variables in the Inspector (**Scripts > Manage > Console** and then click **Inspector**).
                               """,
                               comment: "Markdown help explaining expression bindings and showing a shell integration example"),
                exampleUserVar,
                exampleEnvironmentVar,
                exampleEnvironmentVar,
                exampleUserVar))
        return true
    }
}
