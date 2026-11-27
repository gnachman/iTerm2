//
//  iTermSetFindStringNotification.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/19.
//

import Foundation

// Posted when a view outside the terminal, such as the notes tool, is asked
// to use its selection as the find string.
@objc(iTermSetFindStringNotification)
class iTermSetFindStringNotification: iTermBaseNotification {
    @objc let string: String

    @objc(notificationWithString:)
    class func notification(string: String) -> Self {
        return self.init(string: string)
    }

    @objc(subscribe:block:)
    class func subscribe(_ owner: NSObject,
                         block: @escaping (iTermSetFindStringNotification) -> Void) {
        internalSubscribe(owner) { object in
            // The base class delivers only the instance that was posted, and
            // only to subscriptions made through that instance's own class,
            // which is this class or a subclass of it, so the cast succeeds.
            guard let notification = object as? iTermSetFindStringNotification else {
                it_betaAssert(false, "Expected an iTermSetFindStringNotification but got \(object)")
                return
            }
            block(notification)
        }
    }

    @objc(initWithString:)
    required init(string: String) {
        self.string = string
        super.init(private: ())
    }
}
