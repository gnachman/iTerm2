//
//  ArchiveClippingsBuiltInFunction.swift
//  iTerm2SharedARC
//

import Foundation

@objc(iTermArchiveClippingsBuiltInFunction)
class ArchiveClippingsBuiltInFunction: NSObject {
    private static let argSession = "session"
}

extension ArchiveClippingsBuiltInFunction: iTermBuiltInFunctionProtocol {
    private static func error(message: String) -> NSError {
        return NSError(domain: "com.iterm2.archive-clippings",
                       code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "archive_clippings",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: [argSession: iTermVariableKeySessionID],
            context: .session,
            sideEffectsPlaceholder: "[archive_clippings]") { parameters, completion in
                guard let sessionID = parameters[argSession] as? String else {
                    completion(nil, error(message: "Missing session_id. This shouldn't happen so please report a bug."))
                    return
                }
                guard let session = iTermController.sharedInstance().anySession(withGUID: sessionID) else {
                    completion(nil, error(message: "No such session"))
                    return
                }
                // Mirror add_clipping's routing: a code-review workgroup peer
                // archives the leader's clippings, since that's where its
                // own add_clipping calls land.
                let target: PTYSession
                if session.workgroupSessionMode == .codeReview,
                   let leader = session.workgroupInstance?.mainSession {
                    target = leader
                } else {
                    target = session
                }
                target.archiveClippings()
                completion(nil, nil)
            }
        iTermBuiltInFunctions.sharedInstance().register(builtInFunction, namespace: "iterm2")
    }
}
