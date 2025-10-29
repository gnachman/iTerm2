//
//  SettingPopupView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/29/25.
//

import Foundation
import SearchableComboListView

private extension SearchableComboViewGroup {
    static func fromSettings() -> [SearchableComboViewGroup] {
        let settings = PreferencePanel.sharedInstance().allSettings()
        var nextTag = 1
        let tagProvider = { () -> Int in
            defer {
                nextTag += 1
            }
            return nextTag
        }
        return groupsFromSettings(settings, ancestors: [], tagProvider: tagProvider)
    }

    private static func groupsFromSettings(_ settings: [iTermSetting],
                                            ancestors: [NSMenuItem],
                                            tagProvider: () -> (Int)) -> [SearchableComboViewGroup] {
        let groupsDict: [[String]: [iTermSetting]] = Dictionary(grouping: settings) { setting in
            setting.pathComponents
        }
        return groupsDict.keys.map { pathComponents in
            let settings = groupsDict[pathComponents]!
            let items = settings.compactMap { setting -> SearchableComboViewItem? in
                guard (setting.info.type == .checkbox || setting.info.type == .invertedCheckbox),
                        let button = setting.info.control as? NSButton,
                      !button.hiddenFromActions else {
                    return nil
                }
                let label = button.accessibilityLabel() ?? button.title
                let identifier = iTermKeyBindingAction.toggleSettingParameter(
                    forKey: setting.info.key,
                    isProfile: setting.isProfile,
                    label: label)
                return SearchableComboViewItem(label,
                                               tag: tagProvider(),
                                               identifier: identifier)
            }.sorted { lhs, rhs in
                lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return SearchableComboViewGroup(pathComponents.joined(separator: " > "),
                                            items: items)
        }.sorted { lhs, rhs in
            lhs.label < rhs.label
        }.filter { group in
            !group.items.isEmpty
        }
    }
}


@objc(iTermSettingPopupView)
class SettingPopupView: NSView {
    @objc private(set) var comboView: SearchableComboView? = nil
    @IBOutlet var delegate: SearchableComboViewDelegate? {
        set {
            comboView?.delegate = newValue
        }
        get {
            return comboView?.delegate
        }
    }

    init() {
        super.init(frame: NSRect.zero)
        reloadData()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        reloadData()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        reloadData()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        comboView?.frame = self.bounds
    }

    @objc func reloadData() {
        let identifier = selectedIdentifier
        comboView?.removeFromSuperview()
        let newComboView = SearchableComboView(SearchableComboViewGroup.fromSettings(),
                                               defaultTitle: "Select Setting…")
        newComboView.frame = self.bounds
        newComboView.delegate = comboView?.delegate
        addSubview(newComboView)
        comboView = newComboView
        if let identifier = identifier {
            _ = select(identifier: identifier)
        }
    }

    @objc var selectedTitle: String? {
        return comboView?.selectedItem?.title
    }

    @objc var selectedIdentifier: String? {
        return comboView?.selectedItem?.identifier.map { $0 as NSString as String }
    }

    @objc(selectItemWithTitle:) func select(title: String) {
        _ = comboView?.selectItem(withTitle: title)
    }

    @discardableResult
    @objc(selectItemWithIdentifier:) func select(identifier: String) -> Bool {
        return comboView?.selectItem(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) ?? false
    }
}
