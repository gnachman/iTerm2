//
//  TypeaheadController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/6/22.
//

import Foundation

fileprivate struct Keypress {
    var string: String
}

fileprivate struct TypeaheadJournalEntry {
    enum Action {
        case keyPress(Keypress)
        case invalidate
        case append(String)
    }
    var action: Action
}

@objc
class TypeaheadController: NSObject {
    private var journal = [TypeaheadJournalEntry]()
    @objc private(set) var enabled = false
    
    @objc var string: String? {
        if hasInvalidate {
            return nil
        }
        return journal.compactMap {
            switch $0.action {
            case .keyPress(let keypress):
                return keypress.string
            default:
                return nil
            }
        }.joined(separator: "")
    }

    @objc
    func keyPress(_ char: screen_char_t) {
        guard let string = GetComplexCharRegistry().charToString(char) else {
            journal.append(TypeaheadJournalEntry(action: .invalidate))
            return
        }
        journal.append(TypeaheadJournalEntry(action: .keyPress(Keypress(string: string as String))))
    }

    @objc
    func didRead(_ string: String) {
        journal.append(TypeaheadJournalEntry(action: .append(string)))
    }

    @objc
    func controlKey() {
        journal.append(TypeaheadJournalEntry(action: .invalidate))
    }

    private var hasInvalidate: Bool {
        for entry in journal {
            if case .invalidate = entry.action {
                return true
            }
        }
        return false
    }

    // Self is the main thread instance and other is the mutation thread instance.
    @objc(sync:)
    func sync(_ other: TypeaheadController) {
        defer {
            other.enabled = !journal.isEmpty
        }
        if hasInvalidate || other.hasInvalidate {
            journal.removeAll()
            other.journal.removeAll()
            return
        }
        for entry in other.journal {
            switch entry.action {
            case .keyPress(_):
                fatalError()
            case .invalidate:
                journal.removeAll()
                other.journal.removeAll()
                return
            case .append(let string):
                if !consume(string) {
                    journal.removeAll()
                    other.journal.removeAll()
                    return
                }
            }
        }
        other.journal.removeAll()
    }

    private func consume(_ string: String) -> Bool {
        var remaining = string
        while let c = remaining.first,
                let entry = journal.first,
                case let .keyPress(keypress) = entry.action,
                keypress.string == String(c) {
            remaining.removeFirst()
            journal.removeFirst()
        }
        return remaining.isEmpty
    }
}
