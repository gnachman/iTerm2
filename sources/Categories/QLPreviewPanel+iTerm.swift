//
//  QLPreviewPanel+iTerm.swift
//  iTerm2
//
//  Created by Rony Fadel on 2/20/16.
//
//

import QuickLookUI

extension QLPreviewPanel {
    // Returns the shared QLPreviewPanel if one exists, or nil otherwise. It
    // never creates the shared panel.
    @objc(sharedPreviewPanelIfExists)
    class func sharedPreviewPanelIfExists() -> QLPreviewPanel? {
        return QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
    }
}
