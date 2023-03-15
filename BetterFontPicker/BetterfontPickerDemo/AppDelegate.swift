//
//  AppDelegate.swift
//  BetterfontPickerDemo
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Cocoa
import BetterFontPicker

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var affordance: Affordance!
    @IBOutlet weak var memberPicker: FontFamilyMemberPickerView?
    let compositeView = FontPickerCompositeView(font: NSFont.systemFont(ofSize: NSFont.systemFontSize))
    let stripped = FontPickerCompositeView(font: NSFont.systemFont(ofSize: 12))

    override func awakeFromNib() {
//        fontPickerPanel.contentView?.addSubview(vc.view)
//        vc.view.frame = window.contentView!.bounds
//        vc.delegate = affordance
//        affordance.set(familyName: "Courier")
        affordance.memberPicker = memberPicker
        window.contentView?.addSubview(compositeView)
        _ = compositeView.addHorizontalSpacingAccessory(2)
        _ = compositeView.addVerticalSpacingAccessory(1)
        compositeView.removeMemberPicker()
        compositeView.mode = .fixedPitch
        compositeView.frame = NSRect(x: 0, y: 0, width: 550, height: 27)

        stripped.mode = .fixedPitch
        stripped.removeMemberPicker()
        stripped.removeOptionsButton()
        stripped.removeSizePicker()
        stripped.frame = NSRect(x: 0, y: 50, width: 200, height: 27)
        window.contentView?.addSubview(stripped)
    }
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

