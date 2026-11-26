//
//  iTermShellIntegrationFinishedViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/22/19.
//

import Cocoa

// The shell integration installer's last page. iTermShellIntegrationWindowController.xib
// instantiates it by its Objective-C name and connects only its view.
@objc(iTermShellIntegrationFinishedViewController)
class iTermShellIntegrationFinishedViewController: NSViewController, iTermShellIntegrationInstallerViewController {
    @objc(setBusy:)
    func setBusy(_ busy: Bool) {
    }
}
