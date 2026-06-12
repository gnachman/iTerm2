//
//  iTermLayoutSpec.swift
//  iTerm2SharedARC
//
//  Typed-Swift representation of the JSON spec accepted by the
//  layout-application API. Lives between the JSON parsing layer and
//  the live-state resolver: errors here are pure structural problems
//  and do not require access to PTYTab / PTYSession state.
//

import Foundation

/// A leaf or splitter node in a tab's target layout. Mirrors the
/// `LayoutTreeNode` enum used by `iTermSplitTreeRebuilder`, but at the
/// "spec" stage the leaf identity is still a string (existing session
/// GUID or a new-session config), not yet resolved to live objects.
indirect enum LayoutNode {
    case splitter(vertical: Bool, children: [LayoutNode])
    case session(guid: String)
    case newSession(NewSessionInfo)
}

/// Configuration for creating a brand-new session as a leaf in the
/// target layout.
struct NewSessionInfo: Equatable {
    let profileGUID: String
    let command: String?
}

/// One existing tab whose layout should be replaced.
struct LayoutTabSpec {
    let tabID: String
    let root: LayoutNode
}

/// One brand-new tab to be created and populated with the given root
/// layout. The tab is created in the window identified by `windowID`,
/// inserted at `index` (or appended if nil).
struct LayoutNewTabSpec {
    let windowID: String
    let index: Int?
    let root: LayoutNode
}

/// One brand-new window. The window's first tab is populated with the
/// given root layout. The window adopts the named profile.
struct LayoutNewWindowSpec {
    let profileGUID: String
    let frame: NSRect?
    let root: LayoutNode
}

/// The full spec submitted by the API caller.
struct LayoutSpec {
    let tabs: [LayoutTabSpec]
    let newTabs: [LayoutNewTabSpec]
    let newWindows: [LayoutNewWindowSpec]
    let closeSessions: [String]
    let closeTabs: [String]
    let closeWindows: [String]
}

/// Errors thrown by `LayoutSpec.parse` and the structural validator.
/// Each carries a tree-path-prefixed message so the caller can pinpoint
/// the offending node.
enum LayoutSpecError: Error, Equatable {
    case missingField(path: String, field: String)
    case wrongType(path: String, expected: String)
    case unknownLeafKind(path: String)
    case splitterTooFewChildren(path: String, count: Int)
    case nestedSameOrientation(path: String)
    case treeTooDeep(path: String, depth: Int)
    case duplicateSessionID(guid: String)
}

extension LayoutSpec {

    /// Parses a JSON spec and runs structural validation in one step.
    /// Callers do not need to invoke `LayoutSpecValidator.validate`
    /// separately; doing so would re-run the same checks. The combined
    /// step makes it impossible to skip validation by accident.
    static func parse(_ json: [String: Any]) throws -> LayoutSpec {
        let tabs = try parseList(json["tabs"], path: "tabs", parser: parseTab)
        let newTabs = try parseList(json["new_tabs"], path: "new_tabs", parser: parseNewTab)
        let newWindows = try parseList(json["new_windows"], path: "new_windows", parser: parseNewWindow)
        let closeSessions = try parseStringList(json["close_sessions"], path: "close_sessions")
        let closeTabs = try parseStringList(json["close_tabs"], path: "close_tabs")
        let closeWindows = try parseStringList(json["close_windows"], path: "close_windows")

        let spec = LayoutSpec(tabs: tabs,
                              newTabs: newTabs,
                              newWindows: newWindows,
                              closeSessions: closeSessions,
                              closeTabs: closeTabs,
                              closeWindows: closeWindows)
        try LayoutSpecValidator.validate(spec)
        return spec
    }

    // MARK: - Parsers

    private static func parseList<T>(_ value: Any?,
                                     path: String,
                                     parser: ([String: Any], String) throws -> T) throws -> [T] {
        guard let raw = value else { return [] }
        guard let array = raw as? [[String: Any]] else {
            throw LayoutSpecError.wrongType(path: path, expected: "array of objects")
        }
        var result: [T] = []
        for (i, dict) in array.enumerated() {
            result.append(try parser(dict, "\(path)[\(i)]"))
        }
        return result
    }

    private static func parseStringList(_ value: Any?, path: String) throws -> [String] {
        guard let raw = value else { return [] }
        guard let array = raw as? [String] else {
            throw LayoutSpecError.wrongType(path: path, expected: "array of strings")
        }
        return array
    }

    private static func parseTab(_ dict: [String: Any], path: String) throws -> LayoutTabSpec {
        guard let tabID = dict["tab_id"] as? String else {
            throw LayoutSpecError.missingField(path: path, field: "tab_id")
        }
        guard let rootDict = dict["root"] as? [String: Any] else {
            throw LayoutSpecError.missingField(path: path, field: "root")
        }
        let root = try parseNode(rootDict, path: "\(path).root")
        return LayoutTabSpec(tabID: tabID, root: root)
    }

    private static func parseNewTab(_ dict: [String: Any], path: String) throws -> LayoutNewTabSpec {
        guard let windowID = dict["window_id"] as? String else {
            throw LayoutSpecError.missingField(path: path, field: "window_id")
        }
        guard let rootDict = dict["root"] as? [String: Any] else {
            throw LayoutSpecError.missingField(path: path, field: "root")
        }
        let index = (dict["index"] as? NSNumber)?.intValue
        let root = try parseNode(rootDict, path: "\(path).root")
        return LayoutNewTabSpec(windowID: windowID, index: index, root: root)
    }

    private static func parseNewWindow(_ dict: [String: Any], path: String) throws -> LayoutNewWindowSpec {
        guard let profileGUID = dict["profile"] as? String else {
            throw LayoutSpecError.missingField(path: path, field: "profile")
        }
        guard let rootDict = dict["root"] as? [String: Any] else {
            throw LayoutSpecError.missingField(path: path, field: "root")
        }
        let frame: NSRect?
        if let frameValue = dict["frame"] {
            guard let array = frameValue as? [Double], array.count == 4 else {
                throw LayoutSpecError.wrongType(path: "\(path).frame", expected: "[x, y, w, h]")
            }
            frame = NSRect(x: array[0], y: array[1], width: array[2], height: array[3])
        } else {
            frame = nil
        }
        let root = try parseNode(rootDict, path: "\(path).root")
        return LayoutNewWindowSpec(profileGUID: profileGUID, frame: frame, root: root)
    }

    private static func parseNode(_ dict: [String: Any], path: String) throws -> LayoutNode {
        if let sessionID = dict["session_id"] as? String {
            return .session(guid: sessionID)
        }
        if let newDict = dict["new_session"] as? [String: Any] {
            guard let profile = newDict["profile"] as? String else {
                throw LayoutSpecError.missingField(path: "\(path).new_session", field: "profile")
            }
            let command = newDict["command"] as? String
            return .newSession(NewSessionInfo(profileGUID: profile, command: command))
        }
        if dict["children"] != nil || dict["vertical"] != nil {
            guard let childrenAny = dict["children"] as? [[String: Any]] else {
                throw LayoutSpecError.missingField(path: path, field: "children")
            }
            // `vertical` must be explicit. Defaulting to false silently
            // would let a misspelled key slide through.
            guard let verticalNum = dict["vertical"] as? NSNumber else {
                throw LayoutSpecError.missingField(path: path, field: "vertical")
            }
            let vertical = verticalNum.boolValue
            var children: [LayoutNode] = []
            for (i, childDict) in childrenAny.enumerated() {
                children.append(try parseNode(childDict, path: "\(path).children[\(i)]"))
            }
            return .splitter(vertical: vertical, children: children)
        }
        throw LayoutSpecError.unknownLeafKind(path: path)
    }
}
