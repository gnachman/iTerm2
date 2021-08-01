//
//  GitAgentGateway.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/21. 
//

import Foundation

@objc(iTermGitAgentGateway)
public class GitAgentGateway: NSObject {
    @objc public static var instance = GitAgentGateway()

    private struct GitStateHandler: Equatable {
        static func == (lhs: GitAgentGateway.GitStateHandler, rhs: GitAgentGateway.GitStateHandler) -> Bool {
            return lhs.identifier == rhs.identifier
        }

        let identifier: Int
        let closure: (iTermGitState?) -> Void
        static private var nextIdentifier = 0

        init(closure: @escaping (iTermGitState?) -> Void) {
            self.identifier = Self.nextIdentifier
            Self.nextIdentifier += 1
            self.closure = closure
        }
    }

    private struct RecentBranchesHandler: Equatable {
        static func ==(lhs: GitAgentGateway.RecentBranchesHandler, rhs: GitAgentGateway.RecentBranchesHandler) -> Bool {
            return lhs.identifier == rhs.identifier
        }

        let identifier: Int
        let closure: ([String]?) -> Void
        static private var nextIdentifier = 0

        init(closure: @escaping ([String]?) -> Void) {
            self.identifier = Self.nextIdentifier
            Self.nextIdentifier += 1
            self.closure = closure
        }
    }

    private var connection: NSXPCConnection? = nil
    private var gitStateHandlers: [GitStateHandler] = []
    private var recentBranchFetchCallbacks: [RecentBranchesHandler] = []
    private var ready = false
    private let queue = DispatchQueue(label: "com.iterm2.git-agent-gateway")
    private var nextRequestID = 1

    private var proxy: iTerm2GitAgentProtocol? {
        return connection?.remoteObjectProxy as? iTerm2GitAgentProtocol
    }

    override init() {
        super.init()
        connect()
        proxy?.handshake { [weak self] in
            self?.ready = true
        }
    }

    private func connect() {
        connection = NSXPCConnection(serviceName: "com.iterm2.iTerm2GitAgent")
        guard let connection = connection else {
            return
        }
        connection.remoteObjectInterface = NSXPCInterface(with: iTerm2GitAgentProtocol.self)
        connection.resume()
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.didInvalidateConnection()
            }
        }
        connection.interruptionHandler = { [weak self] in
            self?.didInterrupt()
        }
    }

    private func didInterrupt() {
        invokeAllGitStateHandlers()
        invokeAllRecentBranchesHandlers()
    }

    private func invokeAllGitStateHandlers() {
        var handlers: [GitStateHandler]!
        queue.sync {
            handlers = gitStateHandlers
            gitStateHandlers = []
        }
        handlers.forEach {
            $0.closure(nil)
        }
    }

    private func invokeAllRecentBranchesHandlers() {
        var handlers: [RecentBranchesHandler]!
        queue.sync {
            handlers = recentBranchFetchCallbacks
            recentBranchFetchCallbacks = []
        }
        handlers.forEach {
            $0.closure(nil)
        }
    }

    private func didInvalidateConnection() {
        ready = false
        connect()
    }

    private func nextReqid() -> Int {
        return queue.sync {
            let result = nextRequestID
            nextRequestID += 1
            return result
        }
    }

    @objc(requestGitStateForPath:completion:) public func requestGitState(path: String, completion: @escaping (iTermGitState?) -> Void) {
        let handler = GitStateHandler(closure: completion)
        queue.sync {
            gitStateHandlers.append(handler)
        }
        let timeout = Int32(ceil(iTermAdvancedSettingsModel.gitTimeout()))
        proxy?.requestGitState(forPath: path, timeout: timeout) { [weak self] state in
            self?.didFetch(gitState: state, handler: handler)
        }
    }

    private func didFetch(gitState: iTermGitState?, handler: GitStateHandler) {
        let shouldCall = queue.sync { () -> Bool in
            guard let i = gitStateHandlers.firstIndex(of: handler) else {
                return false
            }
            gitStateHandlers.remove(at: i)
            return true
        }
        if shouldCall {
            handler.closure(gitState)
        }
    }

    @objc(fetchRecentBranchesAt:count:completion:) func fetchRecentBranches(at path: String,
                                                                            maxCount: Int,
                                                                            completion: @escaping ([String]?) -> Void) {
        let handler = RecentBranchesHandler(closure: completion)
        queue.sync {
            recentBranchFetchCallbacks.append(handler)
        }
        proxy?.fetchRecentBranches(at: path, count: maxCount) { [weak self] branches in
            self?.didFetch(recentBranches: branches, handler: handler)
        }
    }

    private func didFetch(recentBranches: [String]?, handler: RecentBranchesHandler) {
        let shouldCall = queue.sync { () -> Bool in
            guard let i = recentBranchFetchCallbacks.firstIndex(of: handler) else {
                return false
            }
            recentBranchFetchCallbacks.remove(at: i)
            return true
        }
        if shouldCall {
            handler.closure(recentBranches)
        }
    }
}
