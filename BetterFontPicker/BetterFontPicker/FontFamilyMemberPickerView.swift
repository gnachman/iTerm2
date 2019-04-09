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
        var postscriptName: String
        var displayName: String
    }
    var selectedFontName: String? {
        let tag = selectedTag()
        if tag < 0 || tag >= members.count {
            return nil
        }
        let member = members[tag]
        return member.postscriptName
    }

    var members: [Member] = []
    var familyName: String? {
        didSet {
            menu?.removeAllItems()
            guard let familyName = familyName else {
                return
            }
            guard let arrayOfArrays = NSFontManager.shared.availableMembers(ofFontFamily: familyName) else {
                return
            }
            members = arrayOfArrays.map { (array: [Any]) -> Member in
                let first = array[0]
                let second = array[1]
                return Member(postscriptName: first as! String,
                              displayName: second as! String)
            }
            for (i, member) in members.enumerated() {
                let menuItem = NSMenuItem(title: member.displayName, action: nil, keyEquivalent: "")
                menuItem.tag = i
                menu?.addItem(menuItem)
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
                select(menu.items[i])
                return
            }
        }
        delegate?.fontFamilyMemberPickerView(self, didSelectFontName: name)
    }
}

