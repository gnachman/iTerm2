//
//  FontPickerPanel.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/8/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

public class FontPickerPanel: NSPanel {
    public override var canBecomeKey: Bool {
        return true
    }

    public override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    public override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}
