//
//  TerminalModeEnclosure.swift
//  iTerm2
//
//  Created by George Nachman on 6/21/25.
//

@objc(iTermModalEnclosure)
class ModalEnclosure: NSView {}

@objc(iTermTerminalModeEnclosure)
class TerminalModeEnclosure: ModalEnclosure {}

@objc(iTermBrowserModeEnclosure)
class BrowserModeEnclosure: ModalEnclosure {}

@objc(iTermHiddenModeEnclosure)
class HiddenModeEnclosure: ModalEnclosure {}
