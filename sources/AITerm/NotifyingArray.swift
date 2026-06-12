//
//  NotifyingArray.swift
//  iTerm2
//
//  Created by George Nachman on 2/24/25.
//

class NotifyingArray<Element> {
    private var storage = [Element]()

    var didInsert: ((Int) -> ())?
    var didRemove: ((Range<Int>) -> ())?
    var didModify: ((Int) -> ())?

    func append(_ element: Element) {
        storage.append(element)
        DLog("Insert \(element)")
        didInsert?(storage.count - 1)
    }

    @discardableResult
    func removeLast(_ n: Int = 1) -> [Element] {
        DLog("Remove \(String(describing: storage.last))")
        let count = storage.count
        let removed = Array(storage[(storage.count - n)...])
        storage.removeLast(n)
        didRemove?((count - n)..<count)
        return removed
    }

    var last: Element? {
        storage.last
    }

    func firstIndex(where test: (Element) -> Bool) -> Int? {
        return storage.firstIndex(where: test)
    }

    func last(where closure: (Element) throws -> Bool) rethrows -> Element? {
        return try storage.last(where: closure)
    }

    subscript(_ index: Int) -> Element {
        get {
            storage[index]
        }
        set {
            storage[index] = newValue
            DLog("didModify \(newValue)")
            didModify?(index)
        }
    }

    var count: Int {
        storage.count
    }
}

