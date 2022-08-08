//
//  OptionsButtonController.swift
//  BetterFontPicker
//
//  Created by George Nachman on 8/6/22.
//  Copyright © 2022 George Nachman. All rights reserved.
//

import Foundation

protocol OptionsButtonControllerDelegate: AnyObject {
    func optionsDidChange(_ controller: OptionsButtonController, options: Set<Int>)
}

class OptionsButtonController: NSObject {
    let optionsButton: MenuButton?
    private(set) var options = Set<Int>()
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
                item.tag = option.identifier
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
            if let typeIdentifier = setting[.typeIdentifier],
               typeIdentifier as? Int == kStylisticAlternativesType,
               let selector = setting[.selectorIdentifier] as? Int {
                options.insert(selector)
            }
        }
    }

    private struct Option {
        var identifier: Int
        var name: String
    }

    private func optionList(familyName: String?) -> [Option]? {
        guard let optionsButton = optionsButton else {
            return nil
        }
        guard let familyName = familyName else {
            optionsButton.isHidden = true
            return nil
        }
        guard let ctfont = NSFont(name: familyName, size: 10) as CTFont? else {
            optionsButton.isHidden = true
            return nil
        }
        guard let features = CTFontCopyFeatures(ctfont) else {
            return nil
        }
        guard let dicts = features as? [Dictionary<String, Any>] else {
            return nil
        }
        guard let ass = dicts.first(where: { $0[kCTFontFeatureTypeNameKey as String] as? String == "Alternative Stylistic Sets" }) else {
            return nil
        }
        guard let selectors = ass[kCTFontFeatureTypeSelectorsKey as String] as? [Dictionary<String, Any>] else {
            return nil
        }
        let options = selectors.compactMap { dict -> Option? in
            guard let identifier = dict[kCTFontFeatureSelectorIdentifierKey as String] as? Int,
                  let selector = dict[kCTFontFeatureSelectorNameKey as String] as? String else {
                return nil
            }
            return Option(identifier: identifier, name: selector)
        }
        return options.sorted { $0.name < $1.name }
    }
}

extension OptionsButtonController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(selectOption(_:)) {
            menuItem.state = (options.contains(menuItem.tag)) ? .on : .off
            return true
        }
        return false
    }

    @objc func selectOption(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        if options.contains(menuItem.tag) {
            options.remove(menuItem.tag)
        } else {
            options.insert(menuItem.tag)
        }
        delegate?.optionsDidChange(self, options: options)
    }
}
