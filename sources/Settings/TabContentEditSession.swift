//
//  TabContentEditSession.swift
//  iTerm2SharedARC
//
//  Applies the tab content editor's values to a profile as they change, so
//  open windows show them right away, and puts the profile back on Cancel.
//  It reads and writes stored values through closures, so it doesn't know
//  where the profile lives.
//

import Foundation

@objc(iTermTabContentEditSession)
final class TabContentEditSession: NSObject {
    // read gives a key's stored value, or nil when it isn't set.
    typealias Read = (String) -> Any?
    // write sets changes and removes removals, all at once, so windows
    // following the profile reconfigure once.
    typealias Write = ([String: Any], [String]) -> Void

    private let editor: TabContentEditorWindowController
    private let read: Read
    private let write: Write
    // Stored values when editing began. A key that wasn't set is missing.
    private let originals: [String: Any]
    // What the editor showed when editing began, to tell what it changed.
    private let initialOverrides: NSDictionary
    private let initialSubtitle: String

    private static let keys = [KEY_TAB_CONTENT_LINES,
                               KEY_TAB_CONTENT_LAYOUT,
                               KEY_TAB_CONTENT_MAXIMUM_LINES,
                               KEY_SUBTITLE]

    @objc init(editor: TabContentEditorWindowController,
               read: @escaping Read,
               write: @escaping Write) {
        self.editor = editor
        self.read = read
        self.write = write
        var originals = [String: Any]()
        for key in Self.keys {
            originals[key] = read(key)
        }
        self.originals = originals
        initialOverrides = editor.overrides as NSDictionary
        initialSubtitle = editor.subtitleFormat
    }

    // Stores the editor's values. One the editor hasn't changed keeps what
    // was stored, rather than storing a copy, so a key that wasn't set still
    // isn't and follows the default.
    @objc func apply() {
        var desired = originals
        if !(editor.overrides as NSDictionary).isEqual(initialOverrides) {
            desired[KEY_TAB_CONTENT_LINES] = editor.overrides
        }
        if editor.layoutChanged {
            desired[KEY_TAB_CONTENT_LAYOUT] = editor.layoutPropertyList
        }
        if editor.lineLimitChanged {
            desired[KEY_TAB_CONTENT_MAXIMUM_LINES] = editor.lineLimit
        }
        if editor.subtitleFormat != initialSubtitle {
            desired[KEY_SUBTITLE] = editor.subtitleFormat
        }
        store(desired)
    }

    // Puts back what was stored when editing began.
    @objc func revert() {
        store(originals)
    }

    private func store(_ desired: [String: Any]) {
        var changes = [String: Any]()
        var removals = [String]()
        for key in Self.keys {
            let current = read(key)
            if let value = desired[key] {
                if !Self.same(current, value) {
                    changes[key] = value
                }
            } else if current != nil {
                removals.append(key)
            }
        }
        guard !changes.isEmpty || !removals.isEmpty else {
            return
        }
        DLog("Storing tab content changes \(changes), removing \(removals)")
        write(changes, removals)
    }

    private static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return (lhs as AnyObject).isEqual(rhs)
        default:
            return false
        }
    }
}
