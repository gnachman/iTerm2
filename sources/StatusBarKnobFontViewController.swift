//
//  StatusBarKnobFontViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/26/21.
//

import Foundation
import BetterFontPicker

@objc(iTermStatusBarKnobFontViewController)
class StatusBarKnobFontViewController: NSViewController {
    @IBOutlet private var affordance: BetterFontPicker.FontPickerCompositeView! = nil
    @IBOutlet private var checkbox: NSButton! = nil
    private var font: NSFont? {
        get {
            if checkbox.state == .on {
                return affordance.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            }
            return nil
        }
        set {
            if let font = newValue {
                checkbox.state = .on
                affordance.font = font
                affordance.isHidden = false
            } else {
                checkbox.state = .off
                affordance.isHidden = true
            }
        }
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @IBAction func checkboxChanged(_ sender: NSButton) {
        if checkbox.state == .on {
            affordance.isHidden = false
        } else {
            affordance.isHidden = true
        }
    }
}

extension StatusBarKnobFontViewController: iTermStatusBarKnobViewController {
    func setDescription(_ description: String, placeholder _: String) {
        checkbox.title = description
        sizeToFit()
    }

    func controlOffset() -> CGFloat {
        return NSMinX(affordance.frame)
    }

    func sizeToFit() {
        checkbox.sizeToFit()
        let margin = CGFloat(8.0)
        view.frame = NSRect(x: view.frame.minX,
                            y: view.frame.minY,
                            width: checkbox.frame.width + margin + affordance.frame.width,
                            height: affordance.frame.height + CGFloat(2.0))
        checkbox.frame = NSRect(x: 0,
                                y: (affordance.frame.height - checkbox.frame.height) / CGFloat(2.0) + CGFloat(1.5),
                                width: checkbox.frame.width,
                                height: checkbox.frame.height)
        affordance.frame = NSRect(x: checkbox.frame.maxX + margin,
                                  y: 0,
                                  width: affordance.frame.width,
                                  height: affordance.frame.height)
    }

    func setHelp(_ url: URL) {
    }

    func value() -> Any {
        let theFont = font
        return theFont?.stringValue ?? ""
    }

    func setValue(_ value: Any) {
        if let stringValue = value as? String, !stringValue.isEmpty, let fontValue = stringValue.fontValue() {
            font = fontValue
            affordance.isHidden = false
            return
        }
        font = nil
    }
}
