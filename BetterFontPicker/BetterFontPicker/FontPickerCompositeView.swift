//
//  FontPickerCompositeView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/9/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

@objc(BFPCompositeViewDelegate)
public protocol FontPickerCompositeViewDelegate: NSObjectProtocol {
    func fontPickerCompositeView(_ view: FontPickerCompositeView,
                                 didSelectFont font: NSFont)
}

@objc(BFPCompositeView)
public class FontPickerCompositeView: NSView, AffordanceDelegate, FontFamilyMemberPickerViewDelegate, SizePickerViewDelegate {
    @objc public weak var delegate: FontPickerCompositeViewDelegate?
    private var accessories: [NSView] = []
    @objc public let affordance = Affordance()
    let memberPicker = FontFamilyMemberPickerView()
    let sizePicker = SizePickerView()
    @objc private(set) public var horizontalSpacing: SizePickerView? = nil
    @objc private(set) public var verticalSpacing: SizePickerView? = nil

    @objc public var font: NSFont? {
        set {
            let temp = delegate
            delegate = nil
            if let font = newValue, let familyName = font.familyName {
                affordance.set(familyName: familyName)
                memberPicker.set(member: font.fontName)
                sizePicker.size = Int(font.pointSize)
            }
            delegate = temp
        }
        get {
            guard let name = memberPicker.selectedFontName else {
                return nil
            }
            return NSFont(name: name,
                          size: CGFloat(sizePicker.size))
        }
    }
    public init(font: NSFont) {
        super.init(frame: NSRect.zero)
        postInit()
        self.font = font
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
        affordance.delegate = self
        memberPicker.delegate = self
        sizePicker.delegate = self
        addSubview(affordance)
        addSubview(memberPicker)
        addSubview(sizePicker)
        affordance.memberPicker = memberPicker
        layoutSubviews()
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc(addHorizontalSpacingAccessoryWithInitialValue:)
    public func addHorizontalSpacingAccessory(_ initialValue: Int) -> SizePickerView {
        let view = SizePickerView()
        horizontalSpacing = view
        view.size = initialValue
        let bundle = Bundle(for: FontPickerCompositeView.self)
        add(accessory: NSImageView(image: bundle.image(forResource: NSImage.Name("HorizontalSpacingIcon"))!))
        add(accessory: view)
        return view
    }

    @objc(addVerticalSpacingAccessoryWithInitialValue:)
    public func addVerticalSpacingAccessory(_ initialValue: Int) -> SizePickerView {
        let view = SizePickerView()
        verticalSpacing = view
        view.size = initialValue
        let bundle = Bundle(for: FontPickerCompositeView.self)
        add(accessory: NSImageView(image: bundle.image(forResource: NSImage.Name("VerticalSpacingIcon"))!))
        add(accessory: view)
        return view
    }

    public func add(accessory view: NSView) {
        accessories.append(view)
        addSubview(view)
        layoutSubviews()
    }

    private func layoutSubviews() {
        let margin = CGFloat(3.0)
        var accessoryWidths: [CGFloat] = []
        var totalAccessoryWidth = CGFloat(0)
        var maxAccessoryHeight = CGFloat(0)
        for accessory in accessories {
            accessoryWidths.append(accessory.fittingSize.width)
            maxAccessoryHeight = max(maxAccessoryHeight, accessory.fittingSize.height)
            totalAccessoryWidth += accessory.fittingSize.width
        }
        totalAccessoryWidth += max(0.0, CGFloat(accessories.count - 1)) * margin

        let sizePickerWidth = CGFloat(54.0)
        let memberPickerWidth = CGFloat(125.0)
        let width = bounds.size.width
        let affordanceWidth = max(200.0, width - sizePickerWidth - memberPickerWidth - totalAccessoryWidth - margin * 2.0)
        var x = CGFloat(0)
        affordance.frame = NSRect(x: x, y: CGFloat(0), width: affordanceWidth, height: CGFloat(25))
        x += affordanceWidth + margin
        memberPicker.frame = NSRect(x: x, y: CGFloat(0), width: memberPickerWidth, height: CGFloat(25))
        x += memberPickerWidth + margin
        sizePicker.frame =  NSRect(x: x, y: CGFloat(0), width: sizePickerWidth, height: CGFloat(27))
        x += sizePickerWidth + margin

        for accessory in accessories {
            let size = accessory.fittingSize
            accessory.frame = NSRect(x: x, y: CGFloat(0), width: size.width, height: size.height)
            x += size.width + margin
        }
    }

    public func affordance(_ affordance: Affordance, didSelectFontFamily fontFamily: String) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    public func fontFamilyMemberPickerView(_ fontFamilyMemberPickerView: FontFamilyMemberPickerView,
                                           didSelectFontName name: String) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    public func sizePickerView(_ sizePickerView: SizePickerView,
                               didChangeSizeTo size: Int) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }
}
