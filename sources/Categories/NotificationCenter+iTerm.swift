//
//  NotificationCenter+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 4/26/25.
//

fileprivate var tokenStorage = MutableAtomicObject<[Int64: Any]>([Int64: Any]())
fileprivate var nextID = iTermAtomicInt64Create()

extension NotificationCenter {
    func addObserver(forName name: Notification.Name,
                     observer: AnyObject?,
                     object: Any?,
                     using closure: @escaping (Notification) -> ()) {
        let identifier = iTermAtomicInt64Add(nextID, 1)
        let token = addObserver(forName: name, object: object, queue: nil) { [weak observer] notification in
            if observer == nil {
                if let token = tokenStorage.value[identifier] {
                    self.removeObserver(token)
                    tokenStorage.mutate { dict in
                        var temp = dict
                        temp.removeValue(forKey: identifier)
                        return temp
                    }
                }
                return
            }
            closure(notification)
        }
        tokenStorage.mutate { dict in
            var temp = dict
            temp[identifier] = token
            return temp
        }
    }
}
