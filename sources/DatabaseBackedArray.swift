//
//  DatabaseBackedArray.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

protocol DatabaseBackedArrayDelegate<Element>: AnyObject where Element: iTermDatabaseElement {
    associatedtype Element: iTermDatabaseElement
    func databaseBackedArray(didModifyElement: Element, oldValue: Element)
    func databaseBackedArray(didInsertElement: Element)
    func databaseBackedArray(didRemoveElement: Element)
}

class DatabaseBackedArray<Element> where Element: iTermDatabaseElement {
    private var elements = [Element]()
    private let db: iTermDatabase
    weak var delegate: (any DatabaseBackedArrayDelegate<Element>)?

    var count: Int {
        elements.count
    }
    var isEmpty: Bool { count == 0 }

    convenience init(db: iTermDatabase, query: String) throws {
        try self.init(db: db, query: query, args: [])
    }

    init(db: iTermDatabase, query: String, args: [Any?]) throws {
        self.db = db
        if let resultSet = try db.executeQuery(query, withArguments: args) {
            while resultSet.next() {
                if let element = Element(dbResultSet: resultSet) {
                    elements.append(element)
                }
            }
            resultSet.close()
        }
    }

    subscript(_ i: Int) -> Element {
        get {
            elements[i]
        }
    }

    func modify(at i: Int, closure: (inout Element) -> ()) throws {
        var value = elements[i]
        closure(&value)
        try set(at: i, value)
    }

    func set(at i: Int, _ newValue: Element) throws {
        let oldValue = elements[i]
        elements[i] = newValue
        let (query, args) = newValue.updateQuery()
        try? db.executeUpdate(query, withArguments: args)
        delegate?.databaseBackedArray(didModifyElement: newValue, oldValue: oldValue)
    }

    func append(_ element: Element) throws {
        try insert(element, atIndex: elements.count)
    }

    func prepend(_ element: Element) throws {
        try insert(element, atIndex: 0)
    }

    func remove(at i: Int) throws {
        let element = elements[i]
        let (query, args) = element.removeQuery()
        try db.executeUpdate(query, withArguments: args)
        elements.remove(at: i)
        delegate?.databaseBackedArray(didRemoveElement: element)
    }

    @discardableResult
    func removeAll(where closure: (Element) throws -> Bool) rethrows -> IndexSet {
        var i = 0
        var j = 0
        var indexes = IndexSet()
        while i < elements.count {
            if try closure(elements[i]) {
                try? self.remove(at: i)
                indexes.insert(j)
            } else {
                i += 1
            }
            j += 1
        }
        return indexes
    }

    func insert(_ element: Element, atIndex i: Int) throws {
        let (query, args) = element.appendQuery()
        try db.executeUpdate(query, withArguments: args)
        elements.insert(element, at: i)
        delegate?.databaseBackedArray(didInsertElement: element)
    }

    func firstIndex(where test: (Element) -> Bool) -> Int? {
        return elements.firstIndex(where: test)
    }

    func first(where test: (Element) -> Bool) -> Element? {
        return elements.first(where: test)
    }
    func last(where test: (Element) -> Bool) -> Element? {
        return elements.last(where: test)
    }
}

extension DatabaseBackedArray: Sequence {
    func makeIterator() -> IndexingIterator<[Element]> {
        return elements.makeIterator()
    }
}


