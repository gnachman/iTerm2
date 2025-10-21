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
    @objc var maxCount = 100

    @objc(log:)
    func log(_ message: String) {
        messages.append(message)
        if messages.count > maxCount {
            messages.removeFirst(messages.count - maxCount)
        }
    }

    @objc
    func fatalError() -> Never {
        iTermFatalError(compressed)  // This won't return.
    }

    private var value: String {
        return messages.joined(separator: "\n")
    }

    private var compressed: String {
        if let data = (value.lossyData as NSData).it_compressed() {
            return (data as NSData).stringWithBase64Encoding(withLineBreak: "")
        } else {
            return value
        }
    }
}
