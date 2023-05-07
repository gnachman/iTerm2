//
//  ImportingWindowController.swift
//  iTerm2ImportStatus
//
//  Created by George Nachman on 5/6/23.
//

import AppKit

@objc
class ImportingWindowController: NSWindowController {
    @IBOutlet var status: NSTextField!
    @IBOutlet var progressIndicator: NSProgressIndicator!

    var cancelCallback: (() -> ())?

    override func awakeFromNib() {
        progressIndicator.startAnimation(nil)
    }
    
    func setStatus(_ string: String) {
        status.stringValue = string
    }
}

