//
//  Cancellation.swift
//  iTerm2
//
//  Created by George Nachman on 6/9/25.
//

// A Cancellation provides a way to cancel an asynchronous operation. The function to implement
// cancellation can be provided after creation.
// It safe to use concurrently.
// It guarantees that the code to perform cancellation is executed exactly once if canceled.
@objc
class Cancellation: NSObject {
    private var lock = Mutex()
    private var _impl: (() -> ())?
    private var _canceled = false

    // Set this to a closure that implements cancellation. You can reassign to this as needed.
    // If this was canceled prior to setting impl for the first time, the setter may run the
    // closure synchronously.
    @objc var impl: (() -> ())? {
        set {
            lock.sync {
                if let f = newValue, _impl == nil, _canceled {
                    // Canceled before the first impl was set so cancel immediately.
                    DLog("already canceled")
                    f()
                } else {
                    _impl = newValue
                }
            }
        }
        get {
            lock.sync { _impl }
        }
    }

    // Has cancel() ever been called?
    @objc var canceled: Bool {
        lock.sync { _canceled }
    }

    // Idempotent. Runs the cancellation handler eventually.
    @objc func cancel() {
        DLog("cancel")
        lock.sync {
            guard !_canceled else {
                return
            }
            _canceled = true
            let f = _impl
            _impl = nil
            f?()
        }
    }
}
