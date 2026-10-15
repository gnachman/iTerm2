//
//  iTermScriptCallCancellation.swift
//  iTerm2SharedARC
//
//  Tells a built-in method that the script call which invoked it stopped waiting for
//  the result (it timed out), so the method can skip work whose outcome nobody will
//  hear about. A method receives one by naming an argument `cancellation:`; it is
//  injected like `connectionKey:` and is not part of the method's public signature.
//  Main thread only.
//

import Foundation

@objc(iTermScriptCallCancellation)
class iTermScriptCallCancellation: NSObject {
    @objc private(set) var isCancelled = false

    @objc func cancel() {
        DLog("Script call cancelled")
        isCancelled = true
    }
}
