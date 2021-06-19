//
//  FontFamilyMemberPickerView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/8/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa

@objc(BFPFontFamilyMemberPickerViewDelegate)
public protocol FontFamilyMemberPickerViewDelegate: NSObjectProtocol {
    func fontFamilyMemberPickerView(_ fontFamilyMemberPickerView: FontFamilyMemberPickerView,
                                    didSelectFontName name: String)
}

@objc(BFPFontFamilyMemberPickerView)
public class FontFamilyMemberPickerView: NSPopUpButton {
    @objc public weak var delegate: FontFamilyMemberPickerViewDelegate?

    struct Member {
        let postscriptName: String
        let displayName: String
        let weight: Int
        let traits: Int
        let tag: Int
    }

    private var selectedMember: Member? {
        let tag = selectedTag()
        if tag < 0 || tag >= members.count {
            return nil
        }
        return members[tag]
    }

    var selectedFontName: String? {
        return selectedMember?.postscriptName
    }

    var members: [Member] = []
    var familyName: String? {
        didSet {
            let oldMember = selectedMember

            menu?.removeAllItems()
            guard let familyName = familyName else {
                return
            }
            guard let arrayOfArrays = NSFontManager.shared.availableMembers(ofFontFamily: familyName) else {
                return
            }
            members = arrayOfArrays.enumerated().compactMap { (index: Int, array: [Any]) -> Member? in
                guard array.count >= 4 else {
                    return nil
                }
                guard let postscriptName = array[0] as? String else {
                    return nil
                }
                guard let displayName = array[1] as? String else {
                    return nil
                }
                guard let weight = array[2] as? NSNumber else {
                    return nil
                }
                guard let traits = array[3] as? NSNumber else {
                    return nil
                }
                return Member(postscriptName: postscriptName,
                              displayName: displayName,
                              weight: weight.intValue,
                              traits: traits.intValue,
                              tag: index)
            }
            for member in members {
                let menuItem = NSMenuItem(title: member.displayName, action: nil, keyEquivalent: "")
                menuItem.tag = member.tag
                menu?.addItem(menuItem)
            }
            if let oldWeight = oldMember?.weight, let oldTraits = oldMember?.traits {
                let candidates = members.filter({ $0.traits == oldTraits })
                if let memberWithClosestWeight = candidates.min(by: { (m1, m2) -> Bool in
                    let loss1 = abs(m1.weight - oldWeight)
                    let loss2 = abs(m2.weight - oldWeight)
                    return loss1 < loss2
                }) {
                    selectItem(withTag: memberWithClosestWeight.tag)
                }
            }
        }
    }

    override public init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: false)
        addItem(withTitle: "")
        postInit()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        postInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        postInit()
    }

    private func postInit() {
        target = self
        action = #selector(didChange(_:))
    }

    @objc public func didChange(_ sender: Any?) {
        if let name = selectedFontName {
            delegate?.fontFamilyMemberPickerView(self, didSelectFontName: name)
        }
    }

    func set(member name: String) {
        guard let menu = menu else {
            return
        }
        for (i, member) in members.enumerated() {
            if member.postscriptName == name {
                if i >= 0 && i < menu.items.count {
                    select(menu.items[i])
                }
                return
            }
        }
        delegate?.fontFamilyMemberPickerView(self, didSelectFontName: name)
    }
}

