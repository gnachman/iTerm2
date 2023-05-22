//
//  NamedMarksDidChangeNotification.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/23.
//

import Foundation

@objc(iTermNamedMarksDidChangeNotification)
class NamedMarksDidChangeNotification: iTermBaseNotification {
    @objc var sessionGuid: String

    @objc init(sessionGuid: String) {
        self.sessionGuid = sessionGuid
        super.init(private: ())
    }

    @objc static func subscribe(owner: NSObject, block: @escaping (NamedMarksDidChangeNotification) -> Void) {
        internalSubscribe(owner) { notif in
            block(notif as! NamedMarksDidChangeNotification)
        }
    }
}
