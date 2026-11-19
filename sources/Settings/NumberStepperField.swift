//
//  NumberStepperField.swift
//  iTerm2SharedARC
//
//  A whole-number field with a stepper beside it, like the one next to the
//  Transparency slider, without the slider. Sends its action when the value
//  changes, from the stepper or from typing.
//

import AppKit

@objc(iTermNumberStepperField)
final class NumberStepperField: NSView {
    let textField = NSTextField()
    let stepper = NSStepper()
    let range: ClosedRange<Int>
    @objc weak var target: AnyObject?
    @objc var action: Selector?
    // Parses and shows numbers in this locale's digits. Not attached to the
    // field: a formatter refuses text it can't read and keeps the focus in
    // the field, where this puts the value back instead.
    private let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        return formatter
    }()
    // The value last set or sent. The stepper and field can get ahead of it
    // mid-click or mid-edit.
    private var committed: Int

    @objc var value: Int {
        get {
            return committed
        }
        set {
            committed = clamp(newValue)
            stepper.integerValue = committed
            textField.stringValue = formatter.string(from: NSNumber(value: committed)) ?? String(committed)
        }
    }

    @objc var isEnabled: Bool = true {
        didSet {
            textField.isEnabled = isEnabled
            stepper.isEnabled = isEnabled
        }
    }

    init(range: ClosedRange<Int>) {
        self.range = range
        self.committed = range.lowerBound
        super.init(frame: .zero)

        textField.alignment = .right
        textField.target = self
        textField.action = #selector(textFieldDidChange(_:))
        // Commit when editing ends by tabbing or clicking away, not just Return.
        textField.cell?.sendsActionOnEndEditing = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        // Room for the widest value in this locale's digits, plus the bezel.
        let widest = formatter.string(from: NSNumber(value: range.upperBound)) ?? String(range.upperBound)
        let digitsWidth = (widest + "0" as NSString).size(withAttributes: [.font: textField.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
        textField.widthAnchor.constraint(equalToConstant: ceil(digitsWidth) + 12).isActive = true

        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperDidChange(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [textField, stepper])
        stack.orientation = .horizontal
        stack.spacing = 2
        // As wide as the field and stepper, not stretched to whatever holds
        // it, which would leave its width ambiguous.
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        value = range.lowerBound
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override var firstBaselineOffsetFromTop: CGFloat {
        return textField.firstBaselineOffsetFromTop
    }

    override var lastBaselineOffsetFromBottom: CGFloat {
        return textField.lastBaselineOffsetFromBottom
    }

    private func clamp(_ number: Int) -> Int {
        return min(max(number, range.lowerBound), range.upperBound)
    }

    // The number in the field, which may be typed and not yet committed.
    private var typedNumber: Int? {
        let text = textField.stringValue.trimmingCharacters(in: .whitespaces)
        return formatter.number(from: text)?.intValue ?? Int(text)
    }

    // The stepper moved one step from the committed value. Step from what's
    // typed, if anything, so a click after typing doesn't lose it.
    @objc private func stepperDidChange(_ sender: NSStepper) {
        let step = sender.integerValue - committed
        // Clamp first: a huge typed number would overflow.
        commit(clamp(typedNumber ?? committed) + step)
    }

    @objc private func textFieldDidChange(_ sender: NSTextField) {
        guard let number = typedNumber else {
            value = committed
            return
        }
        commit(number)
    }

    private func commit(_ number: Int) {
        let old = committed
        value = number
        if committed != old, let action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }
}
