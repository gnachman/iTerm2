//
//  SizePickerView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/8/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

@objc(BFPSizePickerViewDelegate)
public protocol SizePickerViewDelegate: NSObjectProtocol {
    func sizePickerView(_ sizePickerView: SizePickerView,
                        didChangeSizeTo size: Double)
}

@objc(BFPSizePickerView)
public class SizePickerView: NSView, NSTextFieldDelegate {
    @objc public weak var delegate: SizePickerViewDelegate?
    private var internalSize = 12.0
    @objc public var size: Double {
        set {
            internalSet(newValue, withSideEffects: false, updateTextField: true)
        }
        get {
            return internalSize
        }
    }
    public override var fittingSize: NSSize {
        return NSSize(width: 54.0, height: 27.0)
    }
    @objc public let textField = NSTextField()
    let stepper = NSStepper()

    @objc
    public func clamp(min: Int, max: Int) {
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postInit()
    }

    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
        postInit()
    }

    private func postInit() {
        addSubview(textField)
        textField.delegate = self
        textField.isEditable = true
        textField.isSelectable = true
        textField.usesSingleLineMode = true
        textField.doubleValue = size
        stepper.doubleValue = size
        addSubview(stepper)
        stepper.target = self
        stepper.action = #selector(stepper(_:))
        stepper.valueWraps = false
        layoutSubviews()
    }

    private func internalSet(_ newValue: Double,
                             withSideEffects: Bool,
                             updateTextField: Bool) {
        if newValue <= 0 {
            return
        }
        if newValue == internalSize {
            return
        }
        internalSize = newValue
        if updateTextField {
            textField.stringValue = String(format: "%g", newValue)
        }
        stepper.doubleValue = internalSize
        if withSideEffects {
            delegate?.sizePickerView(self, didChangeSizeTo: internalSize)
        }
    }

    private func layoutSubviews() {
        textField.sizeToFit()
        stepper.sizeToFit()

        let margin = CGFloat(0)
        let stepperHeight = stepper.frame.size.height
        stepper.frame = CGRect(x: NSMaxX(bounds) - stepper.frame.size.width,
                               y: 0,
                               width: stepper.frame.size.width,
                               height: stepperHeight)
        let textFieldHeight = CGFloat(21)
        textField.frame = CGRect(x: 0,
                                 y: (stepperHeight - textFieldHeight) / 2,
                                 width: bounds.size.width - NSWidth(stepper.frame) - margin,
                                 height: textFieldHeight)
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc(stepper:)
    public func stepper(_ sender: Any?) {
        let stepper = sender as! NSStepper
        if stepper.doubleValue < 1 {
            stepper.doubleValue = 1
        }
        internalSet(stepper.doubleValue, withSideEffects: true, updateTextField: true)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        let value = min(stepper.maxValue, max(stepper.minValue, textField.doubleValue))
        textField.doubleValue = value
        if value > 0 {
            internalSet(value, withSideEffects: true, updateTextField: true)
        } else {
            textField.doubleValue = internalSize
        }
    }

    public func controlTextDidChange(_ obj: Notification) {
        let value = textField.doubleValue
        if value > 0 {
            // Notify client only if the value is in the legal range. Otherwise let the user edit
            // in peace until they end editing.
            internalSet(value,
                        withSideEffects: value >= stepper.minValue && value <= stepper.maxValue,
                        updateTextField: false)
        }
    }
}
