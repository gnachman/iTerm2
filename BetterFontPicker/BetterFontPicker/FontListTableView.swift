//
//  FontListTableView.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

@objc(BFPFontListTableView)
protocol FontListTableViewDelegate: NSObjectProtocol {
    func fontListTableView(_ fontListTableView: FontListTableView,
                           didToggleFavoriteForRow row: Int)
}

@objc(BFPFontListTableView)
public class FontListTableView: NSTableView {
    weak var fontListDelegate: FontListTableViewDelegate?
    @objc(keyDown:)
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == NSUpArrowFunctionKey || event.keyCode == NSDownArrowFunctionKey {
            return
        }
        super.keyDown(with: event)
    }

    @objc(mouseDown:)
    public override func mouseDown(with event: NSEvent) {
        if !tryMouseDown(with: event) {
            super.mouseDown(with: event)
        }
    }

    private func tryMouseDown(with event: NSEvent) -> Bool {
        guard event.clickCount == 1 else {
            return false
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        let row = self.row(at: localPoint)

        guard row >= 0 else {
            return false
        }

        guard let view = self.view(atColumn: 2, row: row, makeIfNecessary: false) else {
            return false
        }

        guard let starSuperview = view.superview else {
            return false
        }

        let pointInSuperView = starSuperview.convert(localPoint, from: self)
        let result = view.hitTest(pointInSuperView)
        if result == nil {
            return false
        }
        fontListDelegate?.fontListTableView(self, didToggleFavoriteForRow: row)
        return true
    }
}
