//
//  iTermCyclicLog.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/21/25.
//

import Foundation

@objc(iTermCyclicLog)
class CyclicLog: NSObject {
    private var messages = [String]()
    private let mutex = Mutex()
    @objc var maxCount = 100

    @objc(log:)
    func log(_ message: String) {
        mutex.sync {
            messages.append(message)
            if messages.count > maxCount {
                messages.removeFirst(messages.count - maxCount)
            }
        }
    }

    @objc
    func fatalError() -> Never {
        iTermFatalError(compressed)  // This won't return.
    }

    @objc var value: String {
        return mutex.sync {
            messages.joined(separator: "\n")
        }
    }

    @objc var compressed: String {
        if let data = (value.lossyData as NSData).it_compressed() {
            return (data as NSData).stringWithBase64Encoding(withLineBreak: "")
        } else {
            return value
        }
    }
}
