//
//  FilterTextField.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/29/21.
//

import Foundation

@objc(iTermFilterTextField)
class FilterTextField: NSSearchField {
    private var iconSet = false

    @objc override func mouseUp(with event: NSEvent) {
        // See comment in iTermFocusReportingTextField.
    }

    @objc override func viewDidMoveToWindow() {
        if let searchFieldCell = self.cell as? NSSearchFieldCell,
           let cell = searchFieldCell.searchButtonCell, !iconSet {
            changeIcon(cell)
        }
    }

    private func changeIcon(_ cell: NSButtonCell) {
        guard #available(macOS 11, *) else {
            return
        }
        cell.setButtonType(.toggle)
        let filterImage = NSImage(systemSymbolName: "line.horizontal.3.decrease.circle",
                                  accessibilityDescription: "Filter")
        cell.image = filterImage
        cell.alternateImage = filterImage
    }
}
