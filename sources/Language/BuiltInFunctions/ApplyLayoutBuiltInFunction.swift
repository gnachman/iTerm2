//
//  ApplyLayoutBuiltInFunction.swift
//  iTerm2SharedARC
//
//  Registers `iterm2.apply_layout(spec_json)` as a built-in function
//  callable from the Python API. The Python wrapper
//  `App.async_apply_layout` serializes the user-supplied spec dict to
//  JSON and invokes this function.
//

import Foundation

class ApplyLayoutBuiltInFunction: iTermBuiltInFunction {
    @objc static func registerBuiltInFunction() {
        let f = iTermBuiltInFunction(
            name: "apply_layout",
            arguments: ["spec_json_b64": NSString.self],
            optionalArguments: Set(),
            defaultValues: [:],
            context: .app,
            sideEffectsPlaceholder: "[apply_layout]") { parameters, completion in
                // The spec is a JSON object containing arbitrary GUIDs and
                // user-controlled strings. Sending it as a literal expression-
                // level string would require backslash-escaping every `"`,
                // but the iTerm expression parser does not decode `\"` back
                // to `"`. Base64 sidesteps that entirely.
                guard let specB64 = parameters["spec_json_b64"] as? String else {
                    completion(nil, Self.error(String(localized: "ApplyLayout.MissingSpecArg", defaultValue: "Missing spec_json_b64 argument", comment: "Error shown when the apply_layout spec_json_b64 argument is missing")))
                    return
                }
                guard let data = Data(base64Encoded: specB64),
                      let parsed = try? JSONSerialization.jsonObject(with: data),
                      let dict = parsed as? [String: Any] else {
                    completion(nil, Self.error(String(localized: "ApplyLayout.InvalidSpecJSON", defaultValue: "spec_json_b64 is not valid base64-encoded JSON", comment: "Error shown when the apply_layout spec argument is not valid base64-encoded JSON")))
                    return
                }

                do {
                    let spec = try LayoutSpec.parse(dict)

                    let environment = iTermLayoutEnvironment()
                    let plan = try LayoutResolver.resolve(spec, environment: environment)

                    let mutator = iTermLayoutMutator()
                    try LayoutTransaction.execute(plan: plan, mutator: mutator)

                    // Pass nil (not NSNull) so the wire response carries
                    // the literal string "null" — `it_jsonStringForObject`
                    // returns nil for NSNull, which would result in an
                    // empty json_result and a JSONDecodeError in the
                    // Python helper.
                    completion(nil, nil)
                } catch let error as LayoutSpecError {
                    completion(nil, Self.error(Self.describe(error)))
                } catch let error as LayoutResolverError {
                    completion(nil, Self.error(Self.describe(error)))
                } catch let error as LayoutMutatorError {
                    completion(nil, Self.error(error.localizedDescription))
                } catch {
                    completion(nil, Self.error("\(type(of: error)): \(error)"))
                }
            }
        iTermBuiltInFunctions.sharedInstance().register(f, namespace: "iterm2")
    }

    private static func error(_ message: String) -> NSError {
        return NSError(domain: "com.iterm2.apply-layout",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func describe(_ error: LayoutSpecError) -> String {
        switch error {
        case .missingField(let path, let field):
            return String(localized: "ApplyLayout.MissingField", defaultValue: "Missing field '\(field)' at \(path)", comment: "Error shown when a required field is missing from an apply_layout spec")
        case .wrongType(let path, let expected):
            return String(localized: "ApplyLayout.WrongType", defaultValue: "Wrong type at \(path): expected \(expected)", comment: "Error shown when a field in an apply_layout spec has the wrong type")
        case .unknownLeafKind(let path):
            return String(localized: "ApplyLayout.UnknownLeafKind", defaultValue: "Unknown leaf kind at \(path) (must be session_id, new_session, or splitter)", comment: "Error shown when an apply_layout spec has a leaf node of an unrecognized kind")
        case .splitterTooFewChildren(let path, let count):
            return String(localized: "ApplyLayout.SplitterTooFewChildren", defaultValue: "Splitter at \(path) has \(count) children; must have at least 2", comment: "apply_layout error when a splitter has too few children; first placeholder is the path, second is the child count")
        case .nestedSameOrientation(let path):
            return String(localized: "ApplyLayout.NestedSameOrientation", defaultValue: "Same-orientation splitter nesting at \(path) (vertical inside vertical or horizontal inside horizontal)", comment: "Error shown when an apply_layout spec nests splitters of the same orientation")
        case .treeTooDeep(let path, let depth):
            return String(localized: "ApplyLayout.TreeTooDeep", defaultValue: "Layout tree at \(path) is too deep (\(depth))", comment: "Error shown when an apply_layout spec nests splitters too deeply")
        case .duplicateSessionID(let guid):
            return String(localized: "ApplyLayout.DuplicateSessionID", defaultValue: "Session GUID '\(guid)' appears more than once in the spec", comment: "Error shown when a session GUID appears more than once in an apply_layout spec")
        }
    }

    private static func describe(_ error: LayoutResolverError) -> String {
        switch error {
        case .unknownSession(let guid):
            return String(localized: "ApplyLayout.UnknownSession", defaultValue: "Unknown session: \(guid)", comment: "Error shown when a session GUID in an apply_layout spec does not exist")
        case .unknownTab(let guid):
            return String(localized: "ApplyLayout.UnknownTab", defaultValue: "Unknown tab: \(guid)", comment: "Error shown when a tab GUID in an apply_layout spec does not exist")
        case .unknownWindow(let guid):
            return String(localized: "ApplyLayout.UnknownWindow", defaultValue: "Unknown window: \(guid)", comment: "Error shown when a window GUID in an apply_layout spec does not exist")
        case .orphanedSession(let tabGUID, let sessionGUID):
            return String(localized: "ApplyLayout.OrphanedSession", defaultValue: "Session \(sessionGUID) in tab \(tabGUID) is unaccounted for; it must appear in the new layout or in close_sessions/close_tabs", comment: "Error shown when a session is left unaccounted for by an apply_layout spec")
        case .tmuxTabNotSupported(let tabGUID):
            return String(localized: "ApplyLayout.TmuxTabNotSupported", defaultValue: "Tab \(tabGUID) is a tmux integration tab; layout application is not supported on tmux tabs", comment: "Error shown when apply_layout targets a tmux integration tab")
        case .newTabsNotSupported:
            return String(localized: "ApplyLayout.NewTabsNotSupported", defaultValue: "The 'new_tabs' field is not supported by apply_layout", comment: "Error shown when an apply_layout spec uses the unsupported new_tabs field")
        case .newWindowsNotSupported:
            return String(localized: "ApplyLayout.NewWindowsNotSupported", defaultValue: "The 'new_windows' field is not supported by apply_layout", comment: "Error shown when an apply_layout spec uses the unsupported new_windows field")
        case .unknownProfile(let guid):
            return String(localized: "ApplyLayout.UnknownProfile", defaultValue: "Unknown profile: \(guid)", comment: "Error shown when a profile GUID in an apply_layout spec does not exist")
        }
    }
}
