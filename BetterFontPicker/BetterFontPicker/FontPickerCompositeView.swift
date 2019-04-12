//
//  FontPickerCompositeView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/9/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

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
    var memberPicker: FontFamilyMemberPickerView? = FontFamilyMemberPickerView()
    var sizePicker: SizePickerView? = SizePickerView()
    @objc private(set) public var horizontalSpacing: SizePickerView? = nil
    @objc private(set) public var verticalSpacing: SizePickerView? = nil

    @objc(BFPCompositeViewMode)
    public enum Mode: Int {
        case normal
        case fixedPitch
    }
    @objc public var mode: Mode = .normal {
        didSet {
            switch mode {
            case .normal:
                affordance.vc.systemFontDataSources = [SystemFontsDataSource()]
            case .fixedPitch:
                affordance.vc.systemFontDataSources = [
                    SystemFontsDataSource(filter: .fixedPitch),
                    SystemFontsDataSource(filter: .variablePitch) ]
            }
        }
    }
    @objc public var font: NSFont? {
        set {
            let temp = delegate
            delegate = nil
            if let font = newValue, let familyName = font.familyName {
                affordance.familyName = familyName
                memberPicker?.set(member: font.fontName)
                sizePicker?.size = Int(font.pointSize)
            }
            delegate = temp
        }
        get {
            guard let memberPicker = memberPicker else {
                guard let familyName = affordance.familyName else {
                    return nil
                }
                return NSFont(name: familyName,
                              size: CGFloat(sizePicker?.size ?? 12))
            }
            guard let name = memberPicker.selectedFontName else {
                return nil
            }
            return NSFont(name: name,
                          size: CGFloat(sizePicker?.size ?? 12))
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
        memberPicker?.delegate = self
        sizePicker?.delegate = self
        addSubview(affordance)
        if let memberPicker = memberPicker {
            addSubview(memberPicker)
            affordance.memberPicker = memberPicker
        }
        if let sizePicker = sizePicker {
            addSubview(sizePicker)
        }
        layoutSubviews()
    }

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    @objc public func removeSizePicker() {
        if let sizePicker = sizePicker {
            sizePicker.removeFromSuperview()
            self.sizePicker = nil
            layoutSubviews()
        }
    }

    @objc public func removeMemberPicker() {
        if let memberPicker = memberPicker {
            memberPicker.removeFromSuperview()
            self.memberPicker?.delegate = nil
            self.memberPicker = nil
            layoutSubviews()
        }
    }

    @objc(addHorizontalSpacingAccessoryWithInitialValue:)
    public func addHorizontalSpacingAccessory(_ initialValue: Int) -> SizePickerView {
        let view = SizePickerView()
        horizontalSpacing = view
        view.size = initialValue
        let bundle = Bundle(for: FontPickerCompositeView.self)
        let imageView = NSImageView(image: bundle.image(forResource: NSImage.Name("HorizontalSpacingIcon"))!)
        if #available(macOS 10.14, *) {
            imageView.image?.isTemplate = true
            imageView.contentTintColor = NSColor.labelColor
        }
        add(accessory: imageView)
        add(accessory: view)
        return view
    }

    @objc(addVerticalSpacingAccessoryWithInitialValue:)
    public func addVerticalSpacingAccessory(_ initialValue: Int) -> SizePickerView {
        let view = SizePickerView()
        verticalSpacing = view
        view.size = initialValue
        let bundle = Bundle(for: FontPickerCompositeView.self)
        let imageView = NSImageView(image: bundle.image(forResource: NSImage.Name("VerticalSpacingIcon"))!)
        if #available(macOS 10.14, *) {
            imageView.image?.isTemplate = true
            imageView.contentTintColor = NSColor.labelColor
        }
        add(accessory: imageView)
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

        let sizePickerWidth: CGFloat = sizePicker == nil ? CGFloat(0) : CGFloat(54.0)
        var numViews = 1
        if sizePicker != nil {
            numViews += 1
        }
        if memberPicker != nil {
            numViews += 1
        }
        let memberPickerWidth: CGFloat = memberPicker == nil ? CGFloat(0) : CGFloat(125.0)
        let width: CGFloat = bounds.size.width

        // This would be a let constant but the Swift compiler can't type check it in a reasonable amount of time.
        var preferredWidth: CGFloat = width
        preferredWidth -= sizePickerWidth
        preferredWidth -= memberPickerWidth
        preferredWidth -= totalAccessoryWidth
        preferredWidth -= margin * CGFloat(numViews)

        let affordanceWidth = max(200.0, preferredWidth)
        var x = CGFloat(0)
        affordance.frame = NSRect(x: x, y: CGFloat(0), width: affordanceWidth, height: CGFloat(25))
        x += affordanceWidth + margin
        if let memberPicker = memberPicker {
            memberPicker.frame = NSRect(x: x, y: CGFloat(0), width: memberPickerWidth, height: CGFloat(25))
            x += memberPickerWidth + margin
        }
        if let sizePicker = sizePicker {
            sizePicker.frame =  NSRect(x: x, y: CGFloat(0), width: sizePickerWidth, height: CGFloat(27))
            x += sizePickerWidth + margin
        }

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
