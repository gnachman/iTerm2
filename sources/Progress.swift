//
//  Progress.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/28/23.
//

import Foundation

// Like NSProgress but simpler and swifty.
@objc(iTermProgress)
class Progress: NSObject {
    private struct Observer {
        weak var owner: AnyObject?
        var closure: (Double) -> ()
        var queue: DispatchQueue
    }
    private var _value = MutableAtomicObject<Double>(0.0)
    private var _observers = MutableAtomicObject<[Observer]>([])
    @objc var transform: (Double) -> (Double) = { $0 }

    @objc var fraction: Double {
        get {
            _value.value
        }
        set {
            _value.set(transform(newValue))
            _observers.mutableAccess { observers in
                observers.removeAll { observer in
                    observer.owner == nil
                }
            }
            for observer in _observers.value {
                observer.queue.async {
                    if let owner = observer.owner, self.haveObservers(for: owner) {
                        observer.closure(newValue)
                    }
                }
            }
        }
    }

    func addObserver(owner: AnyObject, queue: DispatchQueue, closure: @escaping (Double) -> ()) {
        _observers.mutableAccess { observers in
            observers.append(Observer(owner: owner,
                                       closure: closure,
                                       queue: queue))
        }
        weak var weakOwner: AnyObject? = owner
        queue.async { [weak self] in
            if let self, weakOwner != nil {
                closure(self._value.value)
            }
        }
    }

    func removeObservers(for owner: AnyObject) {
        _observers.mutableAccess { observers in
            observers.removeAll { observer in
                observer.owner === owner
            }
        }
    }

    func haveObservers(for owner: AnyObject) -> Bool {
        return _observers.access { observers in
            return observers.anySatisfies { observer in
                observer.owner === owner
            }
        }
    }
}
