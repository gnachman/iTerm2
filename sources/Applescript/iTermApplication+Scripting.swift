//
//  iTermApplication+Scripting.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/26/14.
//

import AppKit

// Methods exposed through iTerm2.sdef.
extension iTermApplication {
    // Any key-value lookup on the application whose key nothing answers gets
    // an empty array instead of NSUnknownKeyException. The key is ignored.
    // A caller that passes a key that is not a string raises before this
    // method runs, when the key is bridged to String.
    public override func value(forUndefinedKey key: String) -> Any? {
        return NSArray()
    }

    // iTerm2.sdef, class application, property “current window” (cocoa key
    // currentScriptingWindow). Reached by Cocoa Scripting through key-value
    // coding.
    @objc(currentScriptingWindow) dynamic func currentScriptingWindow() -> Any? {
        it_betaAssert(Thread.isMainThread, "-[iTermApplication currentScriptingWindow] runs on the main thread only")
        // The shared controller is nil after +releaseSharedInstance at
        // termination, and there may be no current terminal.
        let terminal: NSWindowController? = iTermController.sharedInstance()?.currentTerminal
        return iTermScriptingWindow(window: terminal?.window)
    }
}
