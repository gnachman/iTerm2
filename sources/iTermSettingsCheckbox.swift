//
//  iTermSettingsCheckbox.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/25.
//

import Foundation

@objc(iTermSettingsCheckbox)
class SettingsCheckbox: NSButton, ExpressionBindableView {
    var textFieldDelegate: iTermFunctionCallTextFieldDelegate?
    @objc var bindingDidChange: ((String?) -> ())?
    @objc var expression: String? {
        didSet {
            if expression != oldValue {
                DLog("Change to \(expression ?? "(nil)")")
                updateIcon()
                if expression?.isEmpty == false {
                    title = "\u{2003}" + title
                } else {
                    title = String(title.trimmingLeadingCharacters(in: .whitespaces))
                }
            }
        }
    }
    @objc var typeHelp: String?
    var iconContainerView: ExpressionBindingIconView?

    override func rightMouseDown(with event: NSEvent) {
        handleRightMouseDown(with: event, view: self)
    }

    @objc
    func editBinding(_ sender: Any) {
        editBinding(example: "user.mySetting")
    }

    @objc
    func removeBinding(_ sender: Any) {
        removeBinding()
    }

    func iconOrigin(size: NSSize) -> NSPoint {
        return NSPoint(x: 17, y: 3)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateIcon()
    }
}

extension SettingsCheckbox: NSAlertDelegate {
    func alertShowHelp(_ sender: NSAlert) -> Bool {
        showHelp(alert: sender,
                 exampleUserVar: "user.mySetting",
                 exampleEnvironmentVar: "MY_SETTING")
    }
}
