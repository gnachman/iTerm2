//
//  OptionsButtonController.swift
//  BetterFontPicker
//
//  Created by George Nachman on 8/6/22.
//  Copyright © 2022 George Nachman. All rights reserved.
//

import Foundation
import CoreText

protocol OptionsButtonControllerDelegate: AnyObject {
    func optionsDidChange(_ controller: OptionsButtonController, options: Set<OptionsButtonController.Flag>)
}

class OptionsButtonController: NSObject {
    let optionsButton: MenuButton?
    private(set) var options = Set<Flag>()
    weak var delegate: OptionsButtonControllerDelegate?

    override init() {
        optionsButton = OptionsButtonController.makeOptionsButton()
        super.init()
    }

    private static func makeOptionsButton() -> MenuButton? {
        if #available(macOS 11, *) {
            let optionsButton = MenuButton()
            optionsButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                          accessibilityDescription: "Choose stylistic alternatives")
            optionsButton.imagePosition = .imageOnly
            optionsButton.isHidden = true
            optionsButton.sizeToFit()
            return optionsButton
        }
        return nil
    }

    // Returns whether the button should be shown.
    func set(familyName: String?) -> Bool {
        guard let optionsButton = optionsButton else {
            return false
        }
        options.removeAll()
        if let options = self.optionList(familyName: familyName) {
            optionsButton.isHidden = false
            let menu = NSMenu()
            for option in options {
                let item = NSMenuItem(title: option.name, action: nil, keyEquivalent: "")
                item.representedObject = Flag(option)
                item.target = self
                item.action = #selector(selectOption(_:))
                menu.addItem(item)
            }
            optionsButton.menuForMenuButton = menu
            return true
        }
        optionsButton.isHidden = true
        return false
    }

    func set(font: NSFont) {
        let settings = (font.fontDescriptor.fontAttributes[.featureSettings] as? [[NSFontDescriptor.FeatureKey: Any]]) ?? []
        options.removeAll()
        for setting in settings {
            guard let typeIdentifier = setting[.typeIdentifier] else {
                continue
            }
            switch typeIdentifier as? Int {
            case .none:
                break
            case kStylisticAlternativesType:
                if let identifier = setting[.selectorIdentifier] as? Int {
                    options.insert(.stylisticSet(identifier: identifier))
                }
            case kCharacterAlternativesType:
                if let tag = setting[.selectorIdentifier] as? String {
                    options.insert(.glyphVariant(tag: tag, value: 0))  // todo
                }
            default:
                break
            }

        }
    }

    enum Flag: Hashable, Encodable {
        case stylisticSet(identifier: Int)
        case glyphVariant(tag: String, value: Int)

        init(_ option: Option) {
            switch option {
            case .stylisticSet(let value):
                self = .stylisticSet(identifier: value.identifier)
            case .glyphVariants(let value):
                switch value {
                case .boolean(let bgv):
                    self = .glyphVariant(tag: bgv.tag, value: 1)
                }
            }
        }

        var data: Data {
            return try! JSONEncoder().encode(self)
        }

        var isEnabled: Bool {
            switch self {
            case .stylisticSet(identifier: _):
                return true
            case .glyphVariant(tag: _, value: let value):
                return value != 0
            }
        }
    }

    enum Option: Equatable {
        case stylisticSet(StylisticSet)
        case glyphVariants(GlyphVariants)

        var name: String {
            switch self {
            case .stylisticSet(let value):
                return value.name
            case .glyphVariants(let value):
                return value.name
            }
        }
    }

    struct StylisticSet: Equatable {
        var identifier: Int
        var name: String
    }

    enum GlyphVariants: Equatable {
        case boolean(BooleanGlyphVariants)

        var name: String {
            switch self {
            case .boolean(let boolean):
                return boolean.name
            }
        }

        init?(_ general: GeneralGlyphVariants) {
            if let boolean = general.boolean {
                self = .boolean(boolean)
            } else {
                return nil
            }
        }
    }

    struct GeneralGlyphVariants: Equatable {
        struct Selector: Equatable {
            var value: Int
            var name: String
            var isDefault: Bool
        }
        var selectors: [Selector]
        var name: String
        var tag: String

        var boolean: BooleanGlyphVariants? {
            if selectors.count == 2,
                let onSelector = selectors.first(where: { $0.value == 1 }),
               let offSelector = selectors.first(where: { $0.value == 0 }) {
                return BooleanGlyphVariants(on: onSelector, off: offSelector, name: name, tag: tag)
            }
            return nil
        }
    }

    struct BooleanGlyphVariants: Equatable {
        let on: GeneralGlyphVariants.Selector
        let off: GeneralGlyphVariants.Selector
        let name: String
        let tag: String
    }

    private func optionList(familyName: String?) -> [Option]? {
        print("Family name is \(familyName ?? "(nil)")")
        guard let optionsButton = optionsButton else {
            return nil
        }
        guard let familyName = familyName else {
            optionsButton.isHidden = true
            return nil
        }
        guard let nsfont = NSFont(name: familyName, size: 10) else {
            optionsButton.isHidden = true
            return nil
        }
        return optionList(nsfont)
    }

    private func optionList(_ nsfont: NSFont) -> [Option]? {
        guard let optionsButton = optionsButton else {
            return nil
        }
        guard let ctfont = nsfont as CTFont? else {
            optionsButton.isHidden = true
            return nil
        }
        guard let features = CTFontCopyFeatures(ctfont) else {
            return nil
        }
        guard let dicts = features as? [Dictionary<String, Any>] else {
            return nil
        }
        for dict in dicts {
            print("Begin dict")
            print("Feature name is \(dict[kCTFontFeatureTypeNameKey as String] as? String ?? "(nil)")")
            print(dict)
        }
        guard let ass = dicts.first(where: { $0[kCTFontFeatureTypeNameKey as String] as? String == "Alternative Stylistic Sets" }) else {
            return nil
        }
        guard let assSelectors = ass[kCTFontFeatureTypeSelectorsKey as String] as? [Dictionary<String, Any>] else {
            return nil
        }
        let assOptions = assSelectors.compactMap { dict -> Option? in
            guard let identifier = dict[kCTFontFeatureSelectorIdentifierKey as String] as? Int,
                  let selector = dict[kCTFontFeatureSelectorNameKey as String] as? String else {
                return nil
            }
            return .stylisticSet(StylisticSet(identifier: identifier, name: selector))
        }
        let variantDicts = dicts.filter {
            guard let name = $0[kCTFontFeatureTypeNameKey as String] as? String else {
                return false
            }
            return name.hasPrefix("Character Variant")
        }
        let variantOptions = variantDicts.compactMap { dict -> Option? in
            guard let selectors = dict[kCTFontFeatureTypeSelectorsKey as String] as? [Dictionary<String, Any>],
                  let featureName = dict[kCTFontFeatureTypeNameKey as String] as? String,
                  let tag = dict[kCTFontOpenTypeFeatureTag as String] as? String else {
                return nil
            }
            let generalSelectors = selectors.compactMap { selector -> GeneralGlyphVariants.Selector? in
                guard let value = selector[kCTFontOpenTypeFeatureValue as String] as? Int,
                      let name = selector[kCTFontFeatureSelectorNameKey as String] as? String else {
                    return nil
                }
                return GeneralGlyphVariants.Selector(value: value,
                                              name: name,
                                              isDefault: selector[kCTFontFeatureSelectorDefaultKey as String] as? Bool ?? false)
            }
            let ggv = GeneralGlyphVariants(selectors: generalSelectors, name: featureName, tag: tag)
            guard let gv = GlyphVariants(ggv) else {
                return nil
            }
            return .glyphVariants(gv)
        }
        return assOptions.sorted {
            String.compareForNumericSuffix($0.name, $1.name)
        } + variantOptions.sorted {
            String.compareForNumericSuffix($0.name, $1.name)
        }
    }
}

fileprivate extension String {
    static func compareForNumericSuffix(_ lhs: String, _ rhs: String) -> Bool {
        let prefix = lhs.commonPrefix(with: rhs)
        let lhsSuffix = lhs.dropFirst(prefix.count)
        let rhsSuffix = rhs.dropFirst(prefix.count)
        if let lnum = Int(lhsSuffix), let rnum = Int(rhsSuffix) {
            return lnum < rnum
        }
        return lhs < rhs
    }
}

extension OptionsButtonController: NSMenuItemValidation {
    private func optionsContainsFlag(_ flag: Flag?) -> Bool {
        guard let flag = flag else {
            return false
        }
        return options.contains(flag)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectOption(_:)) {
            menuItem.state = optionsContainsFlag(menuItem.representedObject as? Flag) ? NSControl.StateValue.on : NSControl.StateValue.off
            return true
        }
        return false
    }

    @objc func selectOption(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }

        guard let itemFlag = menuItem.representedObject as? Flag else {
            return
        }
        if options.contains(itemFlag) {
            options.remove(itemFlag)
        } else {
            options.insert(itemFlag)
        }
        delegate?.optionsDidChange(self, options: options)
    }
}
