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
    private static let errorDomain = "com.iterm2.archive-clippings"

    static func register() {
        let builtInFunction = iTermBuiltInFunction(
            name: "archive_clippings",
            arguments: [:],
            optionalArguments: Set(),
            defaultValues: [argSession: iTermVariableKeySessionID],
            context: .session,
            // Localization unneeded
            sideEffectsPlaceholder: "[archive_clippings]") { parameters, completion in
                guard let session = iTermBuiltInFunction.session(for: parameters,
                                                                 key: argSession,
                                                                 errorDomain: errorDomain,
                                                                 completion: completion) else {
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
