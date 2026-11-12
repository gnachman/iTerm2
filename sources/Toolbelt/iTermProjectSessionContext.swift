import Foundation

/// A snapshot of a live pane. No native terminal objects are retained.
@objcMembers final class iTermProjectSessionContext: NSObject {
    let sessionIdentifier: String
    let tabIdentifier: String
    let projectIdentifier: String?
    let exited: Bool

    init(sessionIdentifier: String, tabIdentifier: String, projectIdentifier: String?, exited: Bool = false) {
        self.sessionIdentifier = sessionIdentifier
        self.tabIdentifier = tabIdentifier
        self.projectIdentifier = projectIdentifier
        self.exited = exited
        super.init()
    }
}

@objcMembers final class iTermProjectTerminalLaunchResult: NSObject {
    let sessionIdentifier: String
    let tabIdentifier: String
    let windowIdentifier: String

    init(sessionIdentifier: String, tabIdentifier: String, windowIdentifier: String) {
        self.sessionIdentifier = sessionIdentifier
        self.tabIdentifier = tabIdentifier
        self.windowIdentifier = windowIdentifier
        super.init()
    }
}

/// Session arrangement ownership is an opaque project ID. Absence inherits legacy tab ownership;
/// an empty string is an explicit override that leaves a pane unassigned.
@objcMembers final class iTermProjectSessionOwnership: NSObject {
    static let arrangementKey = "Session Project Identifier"

    static func identifier(fromArrangement arrangement: [AnyHashable: Any]) -> String? {
        arrangement[arrangementKey] as? String
    }

    static func arrangementFields(projectIdentifier: String?) -> [String: String] {
        projectIdentifier.map { [arrangementKey: $0] } ?? [:]
    }

    static func effectiveIdentifier(_ session: String?, inheriting tab: String?) -> String? {
        session ?? tab
    }
}
