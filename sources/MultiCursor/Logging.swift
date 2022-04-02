//
//  Logging.swift
//  MultiCursor
//
//  Created by George Nachman on 3/31/22.
//

import Foundation

// This exists to be overridden with an application-provided logger.
@objc
public class MultiCursorTextViewLogging: NSObject {
    @objc var enabled: Bool {
        return false
    }
    @objc func log(_ message: String) {
        if enabled {
            print(message)
        }
    }
}
