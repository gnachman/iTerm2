//
//  WorkgroupMemberBuiltInFunction.swift
//  iTerm2
//
//  Sets a variable on the members of a session's workgroup that have a given name.
//

import Foundation

/// `iterm2.set_workgroup_member_variable(session_id:, name:, variable:, json_value:)`
/// sets `variable` on the members of `session_id`'s workgroup whose configured
/// name is `name`, compared case-insensitively. It is how
/// `it2 session set-var --peer-name` reaches a member without the caller
/// having to know any session IDs. `json_value` is parsed as the API's
/// variable requests parse values; `null` unsets.
///
/// Names should be unique within a workgroup, but older workgroups may repeat
/// one, so every match gets the value. A member that hasn't started yet gets
/// it when it does (see iTermWorkgroupInstance.setVariable). Finding no member
/// is an error that lists the names that do exist, since the message is what
/// an agent sees.
///
/// Returns a dictionary with how many members got the value now (`set`),
/// refused it (`failed`), and will get it when they start (`pending`).
@objc(iTermWorkgroupMemberBuiltInFunction)
class WorkgroupMemberBuiltInFunction: NSObject {
}

extension WorkgroupMemberBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static let errorDomain = "com.iterm2.set-workgroup-member-variable"
    private static let sessionIDArg = "session_id"
    private static let nameArg = "name"
    private static let variableArg = "variable"
    private static let jsonValueArg = "json_value"

    private static func error(_ message: String) -> NSError {
        return NSError(domain: errorDomain,
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "set_workgroup_member_variable",
            arguments: [sessionIDArg: NSString.self,
                        nameArg: NSString.self,
                        variableArg: NSString.self,
                        jsonValueArg: NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[set_workgroup_member_variable]") { parameters, completion in
                guard let sessionID = parameters[sessionIDArg] as? String,
                      let name = parameters[nameArg] as? String,
                      let variable = parameters[variableArg] as? String,
                      let jsonValue = parameters[jsonValueArg] as? String else {
                    completion(nil, error(String(localized: "WorkgroupMemberVariable.MissingArgument",
                                                 defaultValue: "Missing required argument",
                                                 comment: "Error when a required argument to set_workgroup_member_variable is absent")))
                    return
                }
                // Only user variables, as for the API's variable requests
                // (iTermAPIHelper -apiServerVariable:handler:), so this can't
                // change a session's own state; see isSettableName.
                guard isSettableName(variable) else {
                    completion(nil, error(String.localizedStringWithFormat(
                        String(localized: "WorkgroupMemberVariable.IllegalName",
                               defaultValue: "“%@” can’t be set. Only user variables named with letters, digits, and underscores, like user.browserURL, can.",
                               comment: "Error when asked to set a variable other than a user variable on a workgroup member. %@ is the variable name."),
                        variable)))
                    return
                }
                guard let session = iTermController.sharedInstance()?.anySession(withGUID: sessionID) else {
                    completion(nil, error(String(localized: "WorkgroupMemberVariable.NoSuchSession",
                                                 defaultValue: "No such session",
                                                 comment: "Error when set_workgroup_member_variable is given a session ID that matches no session")))
                    return
                }
                guard let instance = session.workgroupInstance else {
                    completion(nil, error(String(localized: "WorkgroupMemberIDs.NotInWorkgroup",
                                                 defaultValue: "This session isn’t in a workgroup.",
                                                 comment: "Error when looking up a workgroup member by name from a session that is not part of a workgroup")))
                    return
                }
                // As iTermAPIHelper -handleVariableSetsInRequest:scope: does.
                let value: Any? = jsonValue == "null" ? nil : (JSONSerialization.it_object(forJsonString: jsonValue) as Any?)
                let result = instance.setVariable(variable, value: value, onMembersNamed: name)
                guard result.set + result.failed + result.pending > 0 else {
                    completion(nil, error(noMemberMessage(name: name, existing: instance.liveMemberNames)))
                    return
                }
                completion(["set": result.set, "failed": result.failed, "pending": result.pending], nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }

    // Stricter than the API's rule (user.NAME with no further dot): NAME must
    // also be an identifier, as a URL template requires, or the value could
    // never reach a page.
    static func isSettableName(_ name: String) -> Bool {
        return WorkgroupBrowserURLBinding.Template.isUserVariablePath(name)
    }

    private static func noMemberMessage(name: String, existing names: [String]) -> String {
        if names.isEmpty {
            return String.localizedStringWithFormat(
                String(localized: "WorkgroupMemberIDs.NoMatchNoNames",
                       defaultValue: "This workgroup has no member named “%@”.",
                       comment: "Error when no workgroup member has the requested name. %@ is the requested name."),
                name)
        }
        return String.localizedStringWithFormat(
            String(localized: "WorkgroupMemberIDs.NoMatch",
                   defaultValue: "This workgroup has no member named “%1$@”. Its members are named: %2$@",
                   comment: "Error when no workgroup member has the requested name. %1$@ is the requested name; %2$@ is a comma-separated list of the names that exist."),
            name,
            ListFormatter.localizedString(byJoining: names))
    }
}
