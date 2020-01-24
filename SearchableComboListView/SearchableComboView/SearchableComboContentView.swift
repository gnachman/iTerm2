//
//  SearchableComboContentView.swift
//  SearchableComboView
//
//  Created by George Nachman on 1/25/20.
//  Copyright © 2020 George Nachman. All rights reserved.
//

import AppKit

// A view that looks like a pull-down menu but features a search field and a
// two-level hierarchy of grouped items.
class SearchableComboContentView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public override func viewDidMoveToWindow() {
        if #available(macOS 10.14, *) {
            window?.backgroundColor = NSColor.clear
        }
        super.viewDidMoveToWindow()
    }
}
