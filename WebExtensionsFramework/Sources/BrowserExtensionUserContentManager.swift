//
//  BrowserExtensionUserContentManager.swift
//  WebExtensionsFramework
//
//  Created by George Nachman on 7/8/25.
//


import WebKit

@MainActor
public class BrowserExtensionUserContentManager {
    weak var webView: BrowserExtensionWKWebView?
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

    init(webView: BrowserExtensionWKWebView,
         userScriptFactory: BrowserExtensionUserScriptFactoryProtocol) {
        self.webView = webView
        self.userScriptFactory = userScriptFactory
    }

    func add(userScript: UserScript) {
        journal.append(.addUserScript(userScript))
        update()
    }

    func remove(userScriptIdentifier identifier: String) {
        journal.append(.removeUserScript(identifier))
        update()
    }

    func performAtomicUpdate<T>(_ closure: () throws -> T) rethrows -> T {
        atomicUpdatesInProgress += 1
        defer {
            atomicUpdatesInProgress -= 1
            update()
        }
        return try closure()
    }

    func performAtomicUpdate<T>(_ closure: () async throws -> T) async rethrows -> T {
        atomicUpdatesInProgress += 1
        defer {
            atomicUpdatesInProgress -= 1
            update()
        }
        return try await closure()
    }

    private func update() {
        guard let webView, atomicUpdatesInProgress == 0 else {
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
                webView.be_configuration.be_userContentController.be_removeAllUserScripts()
                for userScript in installedUserScripts {
                    _ = install(userScript, except: [])
                }
            }
        }
    }

    private func install(_ userScript: UserScript, except worldsToExclude: [WKContentWorld]) -> [WKContentWorld] {
        guard let webView else {
            return []
        }
        var added = [WKContentWorld]()
        for world in userScript.worlds {
            if worldsToExclude.contains(world) || added.contains(world) {
                continue
            }
            webView.be_configuration.be_userContentController.be_addUserScript(
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
