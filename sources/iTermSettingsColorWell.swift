//
//  iTermSettingsColorWell.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/25.
//

import Foundation
import ColorPicker

@objc(iTermSettingsColorWell)
class SettingsColorWell: CPKColorWell, ExpressionBindableView {
    var textFieldDelegate: iTermFunctionCallTextFieldDelegate?
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
    var iconContainerView: ExpressionBindingIconView?

    override func rightMouseDown(with event: NSEvent) {
        handleRightMouseDown(with: event, view: self)
    }

    @objc
    func editBinding(_ sender: Any) {
        editBinding(example: "bgColor")
    }

    @objc
    func removeBinding(_ sender: Any) {
        removeBinding()
    }

    func iconOrigin(size: NSSize) -> NSPoint {
        return NSPoint(x: 32 - size.width - 2, y: 2)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateIcon()
    }
}

extension SettingsColorWell: NSAlertDelegate {
    func alertShowHelp(_ sender: NSAlert) -> Bool {
        showHelp(alert: sender,
                 exampleUserVar: "bgColor",
                 exampleEnvironmentVar: "BACKGROUND_COLOR")
    }
}
