//
//  iTermBaseWKWebView.swift
//  iTerm2
//
//  Created by George Nachman on 7/29/25.
//

import WebKit

// The superclass of iTermBrowserWebView. It overrides two methods that
// WKWebView implements privately (declared in iTermBaseWKWebView.h) only to
// call super, so that its Swift subclass can call super on them.
@objc(iTermBaseWKWebView)
class iTermBaseWKWebView: WKWebView {
    override func insertText(_ insertString: Any!, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector!) {
        super.doCommand(by: selector)
    }
}
