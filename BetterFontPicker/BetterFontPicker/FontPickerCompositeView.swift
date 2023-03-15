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
public class FontPickerCompositeView: NSView, AffordanceDelegate, FontFamilyMemberPickerViewDelegate, SizePickerViewDelegate, OptionsButtonControllerDelegate {
    @objc public weak var delegate: FontPickerCompositeViewDelegate?
    private var accessories: [NSView] = []
    @objc public let affordance = Affordance()
    private var optionsButtonController: OptionsButtonController? = OptionsButtonController()
    var memberPicker: FontFamilyMemberPickerView? = FontFamilyMemberPickerView()
    var sizePicker: SizePickerView? = SizePickerView()
    @objc private(set) public var horizontalSpacing: SizePickerView? = nil
    @objc private(set) public var verticalSpacing: SizePickerView? = nil
    @objc var options: Set<Int> {
        return optionsButtonController?.options ?? Set()
    }

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
                sizePicker?.size = Double(font.pointSize)
                updateOptionsMenu()
                optionsButtonController?.set(font: font)
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
            if options.isEmpty {
                return NSFont(name: name,
                              size: CGFloat(sizePicker?.size ?? 12))
            }
            let size = CGFloat(sizePicker?.size ?? 12)
            var descriptor = NSFontDescriptor(name: name, size: size)
            let settings = Array(options).map {
                [NSFontDescriptor.FeatureKey.typeIdentifier: kStylisticAlternativesType,
                 NSFontDescriptor.FeatureKey.selectorIdentifier: $0]
            }
            descriptor = descriptor.addingAttributes([.featureSettings: settings])
            return NSFont(descriptor: descriptor, size: size)
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
        sizePicker?.clamp(min: 1, max: 256)
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

    @objc public func removeOptionsButton() {
        optionsButtonController = nil
    }

    private func temporarilyRemoveOptionsButton() {
        if let i = indexOfOptionsButton {
            accessories.remove(at: i)
            optionsButtonController?.delegate = nil
            layoutSubviews()
        }
    }

    private func imageViewForImage(withName name: String) -> NSImageView {
        let bundle = Bundle(for: FontPickerCompositeView.self)
        if let image = bundle.image(forResource: NSImage.Name(name)) {
            return NSImageView(image: image)
        } else {
            return NSImageView(image: NSImage(size: NSSize(width: 1, height: 1)))
        }
    }

    @objc(addHorizontalSpacingAccessoryWithInitialValue:)
    public func addHorizontalSpacingAccessory(_ initialValue: Double) -> SizePickerView {
        let view = SizePickerView()
        view.clamp(min: 1, max: 200)
        horizontalSpacing = view
        view.size = initialValue
        let imageView = imageViewForImage(withName: "HorizontalSpacingIcon")
        if #available(macOS 10.14, *) {
            imageView.image?.isTemplate = true
            imageView.contentTintColor = NSColor.labelColor
        }
        add(accessory: imageView)
        add(accessory: view)
        return view
    }

    @objc(addVerticalSpacingAccessoryWithInitialValue:)
    public func addVerticalSpacingAccessory(_ initialValue: Double) -> SizePickerView {
        let view = SizePickerView()
        view.clamp(min: 1, max: 200)
        verticalSpacing = view
        view.size = initialValue
        let imageView = imageViewForImage(withName: "VerticalSpacingIcon")
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
        ensureAccessoryOrder()
        addSubview(view)
        layoutSubviews()
    }

    private func ensureAccessoryOrder() {
        guard let i = indexOfOptionsButton, i != accessories.count - 1 else {
            return
        }
        // Move options button to end.
        let button = accessories[i]
        accessories.remove(at: i)
        accessories.append(button)
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
        let memberPickerWidth: CGFloat = memberPicker == nil ? CGFloat(0) : CGFloat(100.0)
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
        updateOptionsMenu()
    }

    private var indexOfOptionsButton: Int? {
        return accessories.firstIndex { view in
            (view as? AccessoryWrapper)?.subviews.first === optionsButtonController?.optionsButton
        }
    }

    private var haveAddedOptionsButton: Bool {
        return indexOfOptionsButton != nil
    }

    private func updateOptionsMenu() {
        guard let optionsButton = optionsButtonController?.optionsButton else {
            return
        }
        if let optionsButtonController, optionsButtonController.set(familyName: affordance.familyName) {
            if !haveAddedOptionsButton {
                optionsButton.sizeToFit()
                optionsButtonController.delegate = self
                let wrapper = AccessoryWrapper(optionsButton, height: bounds.height)
                add(accessory: wrapper)
            }
            return
        }
        temporarilyRemoveOptionsButton()
    }

    public func fontFamilyMemberPickerView(_ fontFamilyMemberPickerView: FontFamilyMemberPickerView,
                                           didSelectFontName name: String) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    public func sizePickerView(_ sizePickerView: SizePickerView,
                               didChangeSizeTo size: Double) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }

    func optionsDidChange(_ controller: OptionsButtonController, options: Set<Int>) {
        if let font = font {
            delegate?.fontPickerCompositeView(self, didSelectFont: font)
        }
    }
}

