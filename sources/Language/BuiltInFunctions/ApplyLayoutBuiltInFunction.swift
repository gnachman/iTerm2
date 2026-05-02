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
                    completion(nil, Self.error("Missing spec_json_b64 argument"))
                    return
                }
                guard let data = Data(base64Encoded: specB64),
                      let parsed = try? JSONSerialization.jsonObject(with: data),
                      let dict = parsed as? [String: Any] else {
                    completion(nil, Self.error("spec_json_b64 is not valid base64-encoded JSON"))
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
            return "Missing field '\(field)' at \(path)"
        case .wrongType(let path, let expected):
            return "Wrong type at \(path): expected \(expected)"
        case .unknownLeafKind(let path):
            return "Unknown leaf kind at \(path) (must be session_id, new_session, or splitter)"
        case .splitterTooFewChildren(let path, let count):
            return "Splitter at \(path) has \(count) children; must have at least 2"
        case .nestedSameOrientation(let path):
            return "Same-orientation splitter nesting at \(path) (vertical inside vertical or horizontal inside horizontal)"
        case .treeTooDeep(let path, let depth):
            return "Layout tree at \(path) is too deep (\(depth))"
        case .duplicateSessionID(let guid):
            return "Session GUID '\(guid)' appears more than once in the spec"
        }
    }

    private static func describe(_ error: LayoutResolverError) -> String {
        switch error {
        case .unknownSession(let guid):
            return "Unknown session: \(guid)"
        case .unknownTab(let guid):
            return "Unknown tab: \(guid)"
        case .unknownWindow(let guid):
            return "Unknown window: \(guid)"
        case .orphanedSession(let tabGUID, let sessionGUID):
            return "Session \(sessionGUID) in tab \(tabGUID) is unaccounted for; it must appear in the new layout or in close_sessions/close_tabs"
        case .tmuxTabNotSupported(let tabGUID):
            return "Tab \(tabGUID) is a tmux integration tab; layout application is not supported on tmux tabs"
        case .newTabsNotSupported:
            return "The 'new_tabs' field is not supported by apply_layout"
        case .newWindowsNotSupported:
            return "The 'new_windows' field is not supported by apply_layout"
        case .newSessionLeafNotSupported:
            return "'new_session' leaves are not supported by apply_layout"
        }
    }
}
