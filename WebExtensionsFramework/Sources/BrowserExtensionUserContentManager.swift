//
//  BrowserExtensionUserContentManager.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/8/25.
//


import WebKit

@MainActor
public class BrowserExtensionUserContentManager: @preconcurrency CustomDebugStringConvertible {
    public var debugDescription: String {
        "BrowserExtensionUserContentManager\nJournal:\(journal)\nAlready installed:\(installedUserScripts)"
    }
    public weak var userContentController: BrowserExtensionWKUserContentController? {
        didSet {
            update()
        }
    }
    private var journal = [JournalEntry]()
    private var atomicUpdatesInProgress = 0
    private var installedUserScripts = [UserScript]()
    private let userScriptFactory: BrowserExtensionUserScriptFactoryProtocol

    public struct UserScript {
        var code: String
        var injectionTime: WKUserScriptInjectionTime
        var forMainFrameOnly: Bool
        var worlds: [WKContentWorld]
        var identifier: String

        public init(code: String,
                    injectionTime: WKUserScriptInjectionTime,
                    forMainFrameOnly: Bool,
                    worlds: [WKContentWorld],
                    identifier: String) {
            self.code = code
            self.injectionTime = injectionTime
            self.forMainFrameOnly = forMainFrameOnly
            self.worlds = worlds
            self.identifier = identifier
        }

        fileprivate func removingWorlds() -> UserScript {
            var temp = self
            temp.worlds = []
            return temp
        }
    }

    private enum JournalEntry {
        case addUserScript(UserScript)
        case removeUserScript(String)
    }

    public init(userContentController: BrowserExtensionWKUserContentController,
                userScriptFactory: BrowserExtensionUserScriptFactoryProtocol) {
        self.userContentController = userContentController
        self.userScriptFactory = userScriptFactory
    }

    public func add(userScript: UserScript) {
        journal.append(.addUserScript(userScript))
        update()
    }

    public func remove(userScriptIdentifier identifier: String) {
        journal.append(.removeUserScript(identifier))
        update()
    }

    public func performAtomicUpdate<T>(_ closure: () throws -> T) rethrows -> T {
        atomicUpdatesInProgress += 1
        defer {
            atomicUpdatesInProgress -= 1
            update()
        }
        return try closure()
    }

    public func performAtomicUpdate<T>(_ closure: () async throws -> T) async rethrows -> T {
        atomicUpdatesInProgress += 1
        defer {
            atomicUpdatesInProgress -= 1
            update()
        }
        return try await closure()
    }

    private func update() {
        guard let userContentController, atomicUpdatesInProgress == 0 else {
            return
        }

        let entries = journal
        journal = []
        for entry in entries {
            switch entry {
            case .addUserScript(let userScript):
                let i = installedUserScripts.firstIndex { $0.identifier == userScript.identifier }
                var current = if let i {
                    installedUserScripts[i]
                } else {
                    userScript.removingWorlds()
                }

                current.worlds.append(contentsOf: install(userScript, except: current.worlds))

                if let i {
                    installedUserScripts[i] = current
                } else {
                    installedUserScripts.append(current)
                }

            case .removeUserScript(let id):
                guard let i = installedUserScripts.firstIndex(where: { $0.identifier == id }) else {
                    return
                }
                installedUserScripts.remove(at: i)
                userContentController.be_removeAllUserScripts()
                for userScript in installedUserScripts {
                    _ = install(userScript, except: [])
                }
            }
        }
    }

    private func name(of world: WKContentWorld) -> String {
        if let value = world.name  {
            return value
        }
        if world === WKContentWorld.page {
            return "page"
        }
        if world === WKContentWorld.defaultClient {
            return "default client"
        }
        return "Unknown@\(world)"
    }

    private func install(_ userScript: UserScript, except worldsToExclude: [WKContentWorld]) -> [WKContentWorld] {
        guard let userContentController else {
            return []
        }
        var added = [WKContentWorld]()
        for world in userScript.worlds {
            if worldsToExclude.contains(world) || added.contains(world) {
                continue
            }
            userContentController.be_addUserScript(
                userScriptFactory.createUserScript(
                    source: userScript.code,
                    injectionTime: userScript.injectionTime,
                    forMainFrameOnly: userScript.forMainFrameOnly,
                    in: world))
            added.append(world)
        }
        return added
    }
}
