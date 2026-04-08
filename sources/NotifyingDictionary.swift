import Foundation

enum NotifyingDictionaryChange {
    case added
    case removed
    case updated
}

typealias NotifyingDictionaryObserver<Key: Hashable, Value> = (Key, Value?, NotifyingDictionaryChange) -> Void

class NotifyingDictionaryObserverToken {
    private let removal: () -> Void

    fileprivate init(_ removal: @escaping () -> Void) {
        self.removal = removal
    }

    deinit {
        removal()
    }
}

class NotifyingDictionary<Key: Hashable, Value>: ExpressibleByDictionaryLiteral {
    private var storage: [Key: Value] = [:]
    private var observers: [UUID: NotifyingDictionaryObserver<Key, Value>] = [:]

    init() {}

    init(_ dictionary: [Key: Value]) {
        storage = dictionary
    }

    // MARK: - Dictionary API

    var keys: Dictionary<Key, Value>.Keys { storage.keys }
    var values: Dictionary<Key, Value>.Values { storage.values }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                updateValue(newValue, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get { storage[key] ?? defaultValue() }
        set { self[key] = newValue }
    }

    required init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements {
            storage[key] = value
        }
    }

    @discardableResult
    func removeValue(forKey key: Key) -> Value? {
        guard let value = storage.removeValue(forKey: key) else {
            return nil
        }
        notify(key: key, value: value, change: .removed)
        return value
    }

    func removeAll() {
        let snapshot = storage
        storage.removeAll()
        for (key, value) in snapshot {
            notify(key: key, value: value, change: .removed)
        }
    }

    @discardableResult
    func updateValue(_ value: Value, forKey key: Key) -> Value? {
        let old = storage.updateValue(value, forKey: key)
        if old != nil {
            notify(key: key, value: value, change: .updated)
        } else {
            notify(key: key, value: value, change: .added)
        }
        return old
    }

    func contains(where predicate: ((key: Key, value: Value)) throws -> Bool) rethrows -> Bool {
        try storage.contains(where: predicate)
    }

    // MARK: - Observers

    /// Register an observer. The observer is automatically removed when the returned token is deallocated.
    func addObserver(_ observer: @escaping NotifyingDictionaryObserver<Key, Value>) -> NotifyingDictionaryObserverToken {
        let uuid = UUID()
        observers[uuid] = observer
        return NotifyingDictionaryObserverToken { [weak self] in
            self?.observers.removeValue(forKey: uuid)
        }
    }

    private func notify(key: Key, value: Value?, change: NotifyingDictionaryChange) {
        for observer in observers.values {
            observer(key, value, change)
        }
    }
}

// MARK: - Collection

extension NotifyingDictionary: Collection {
    typealias Index = Dictionary<Key, Value>.Index
    typealias Element = Dictionary<Key, Value>.Element

    var startIndex: Index { storage.startIndex }
    var endIndex: Index { storage.endIndex }

    subscript(position: Index) -> Element {
        storage[position]
    }

    func index(after i: Index) -> Index {
        storage.index(after: i)
    }
}

// MARK: - Equatable

extension NotifyingDictionary: Equatable where Value: Equatable {
    static func == (lhs: NotifyingDictionary, rhs: NotifyingDictionary) -> Bool {
        lhs.storage == rhs.storage
    }
}

// MARK: - CustomStringConvertible

extension NotifyingDictionary: CustomStringConvertible {
    var description: String { storage.description }
}

// MARK: - CustomDebugStringConvertible

extension NotifyingDictionary: CustomDebugStringConvertible {
    var debugDescription: String { storage.debugDescription }
}
