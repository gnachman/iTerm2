//
//  OptionsButtonController.swift
//  BetterFontPicker
//
//  Created by George Nachman on 8/6/22.
//  Copyright © 2022 George Nachman. All rights reserved.
//

import Foundation

protocol OptionsButtonControllerDelegate: AnyObject {
    func optionsDidChange(_ controller: OptionsButtonController)
}

class OptionsButtonController: NSObject {
    let optionsButton: MenuButton?
    private(set) var options = Set<Int>()
    private(set) var disableContextualAlternates = false
    weak var delegate: OptionsButtonControllerDelegate?

    override init() {
        optionsButton = OptionsButtonController.makeOptionsButton()
        super.init()
    }

    private static func makeOptionsButton() -> MenuButton? {
        if #available(macOS 11, *) {
            let optionsButton = MenuButton()
            optionsButton.image = NSImage(systemSymbolName: "ellipsis.circle",
                                          accessibilityDescription: "Choose font features")
            optionsButton.imagePosition = .imageOnly
            optionsButton.isHidden = true
            optionsButton.sizeToFit()
            return optionsButton
        }
        return nil
    }

    /// Feature settings dicts derived from the current selections, suitable for
    /// inclusion in `NSFontDescriptor.featureSettings`.
    var featureSettings: [[NSFontDescriptor.FeatureKey: Any]] {
        var result: [[NSFontDescriptor.FeatureKey: Any]] = []
        for selector in options {
            result.append([
                .typeIdentifier: kStylisticAlternativesType,
                .selectorIdentifier: selector
            ])
        }
        if disableContextualAlternates {
            result.append([
                .typeIdentifier: kContextualAlternatesType,
                .selectorIdentifier: kContextualAlternatesOffSelector
            ])
        }
        return result
    }

    // Returns whether the button should be shown.
    func set(familyName: String?) -> Bool {
        guard let optionsButton = optionsButton else {
            return false
        }
        options.removeAll()
        disableContextualAlternates = false
        guard familyName != nil else {
            optionsButton.isHidden = true
            return false
        }
        let stylisticAlts = stylisticAltOptions(familyName: familyName)
        let hasStylisticSets = (stylisticAlts?.isEmpty == false)

        // Always offer the calt toggle when a font is selected. CTFontCopyFeatures
        // only reflects the legacy AAT feature table, so OpenType fonts like
        // Monaspace, FiraCode, and Cascadia Code don't advertise their calt
        // table here even though they use it. Showing the toggle universally
        // lets users disable surprising calt substitutions on any font; for
        // fonts without a calt table the toggle is a harmless no-op.
        optionsButton.isHidden = false
        let menu = NSMenu()
        let caltItem = NSMenuItem(title: "Contextual Alternates",
                                  action: #selector(toggleContextualAlternates(_:)),
                                  keyEquivalent: "")
        caltItem.target = self
        menu.addItem(caltItem)
        if let alts = stylisticAlts, hasStylisticSets {
            menu.addItem(.separator())
            for option in alts {
                let item = NSMenuItem(title: option.name,
                                      action: #selector(selectStylisticAlt(_:)),
                                      keyEquivalent: "")
                item.tag = option.identifier
                item.target = self
                menu.addItem(item)
            }
        }
        optionsButton.menuForMenuButton = menu
        return true
    }

    func set(font: NSFont) {
        let settings = (font.fontDescriptor.fontAttributes[.featureSettings] as? [[NSFontDescriptor.FeatureKey: Any]]) ?? []
        options.removeAll()
        disableContextualAlternates = false
        // Stylistic-alt "Off" selectors (odd ids) and the "No Stylistic
        // Alternates" baseline (id 0) are AAT defaults and contribute no
        // visual change. We deliberately drop them here so options stays
        // canonical: the next round-trip will only emit "On" selectors.
        for setting in settings {
            guard let typeIdentifier = setting[.typeIdentifier] as? Int,
                  let selector = setting[.selectorIdentifier] as? Int else {
                continue
            }
            if typeIdentifier == kStylisticAlternativesType {
                if OptionsButtonController.isOnSelector(selector) {
                    options.insert(selector)
                }
            } else if typeIdentifier == kContextualAlternatesType,
                      selector == kContextualAlternatesOffSelector {
                disableContextualAlternates = true
            }
        }
    }

    /// AAT type-35 stylistic alt selectors come in pairs: even IDs >= 2 are
    /// the "On" half (e.g. kStylisticAltOneOnSelector = 2) and odd IDs >= 3
    /// are their "Off" mates. Selector 0 is "No Stylistic Alternates" and
    /// selector 1 isn't used. The picker only exposes the "On" halves; this
    /// is the canonical predicate used both when building the menu and when
    /// reading existing settings off a font.
    static func isOnSelector(_ identifier: Int) -> Bool {
        return identifier >= 2 && identifier.isMultiple(of: 2)
    }

    private struct Option {
        var identifier: Int
        var name: String
    }

    private func stylisticAltOptions(familyName: String?) -> [Option]? {
        guard let familyName = familyName else {
            return nil
        }
        guard let ctfont = NSFont(name: familyName, size: 10) as CTFont? else {
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
            // Show only the "On" halves of the type-35 selector pairs so each
            // stylistic set is one toggle rather than two.
            if !OptionsButtonController.isOnSelector(identifier) {
                return nil
            }
            return Option(identifier: identifier, name: selector)
        }
        return options.sorted { $0.name < $1.name }
    }

}

extension OptionsButtonController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleContextualAlternates(_:)) {
            menuItem.state = disableContextualAlternates ? .off : .on
            return true
        }
        if menuItem.action == #selector(selectStylisticAlt(_:)) {
            menuItem.state = options.contains(menuItem.tag) ? .on : .off
            return true
        }
        return false
    }

    @objc func selectStylisticAlt(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else {
            return
        }
        if options.contains(menuItem.tag) {
            options.remove(menuItem.tag)
        } else {
            options.insert(menuItem.tag)
        }
        delegate?.optionsDidChange(self)
    }

    @objc func toggleContextualAlternates(_ sender: Any?) {
        disableContextualAlternates.toggle()
        delegate?.optionsDidChange(self)
    }
}
