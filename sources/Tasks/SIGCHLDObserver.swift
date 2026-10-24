//
//  SIGCHLDObserver.swift
//  iTerm2
//
//  Observes SIGCHLD without installing a signal handler. A dispatch signal source learns of each
//  delivery through kqueue and runs its handler later on an ordinary queue, so the handler isn't
//  restricted to async-signal-safe calls, and the signal keeps its default disposition.
//

import Foundation

@objc(iTermSIGCHLDObserver)
final class SIGCHLDObserver: NSObject {
    private let source: DispatchSourceSignal

    // RLogs every SIGCHLD for the rest of the process's life, so debug logs show whether one
    // arrived while nothing handles it.
    @objc
    static func startLogging() {
        _ = logger
    }
    private static let logger = SIGCHLDObserver(queue: DispatchQueue(label: "com.iterm2.sigchld-logger")) { count in
        RLog("Received SIGCHLD x\(count)")
    }

    // `handler` runs on `queue` with the number of signals delivered since it last ran. Signals
    // delivered before `registered` runs on `queue` are missed.
    init(queue: DispatchQueue,
         registered: (() -> Void)? = nil,
         handler: @escaping (UInt) -> Void) {
        source = DispatchSource.makeSignalSource(signal: SIGCHLD, queue: queue)
        super.init()
        if let registered {
            source.setRegistrationHandler(handler: registered)
        }
        source.setEventHandler { [source] in
            handler(source.data)
        }
        source.activate()
    }

    deinit {
        source.cancel()
    }
}
