//
//  iTermBrowserTriggerHandler.swift
//  iTerm2
//
//  Created by George Nachman on 8/2/25.
//

@MainActor
protocol iTermBrowserTriggerHandlerDelegate: AnyObject, BrowserTriggerDelegate {
    func triggerHandlerScope(_ sender: iTermBrowserTriggerHandler) -> iTermVariableScope?
    func triggerHandlerObject(_ sender: iTermBrowserTriggerHandler) -> iTermObject?
}

@MainActor
class iTermBrowserTriggerHandler: NSObject {
    private let profileObserver: iTermProfilePreferenceObserver
    private let sessionSecret: String
    static let messageHandlerName = "iTerm2Trigger"
    private var triggers: [String: (NSDictionary, BrowserTrigger)]!
    var delegate: iTermBrowserTriggerHandlerDelegate?
    var webView: iTermBrowserWebView?

    init?(profileObserver: iTermProfilePreferenceObserver) {
        guard let sessionSecret = String.makeSecureHexString() else {
            return nil
        }
        self.sessionSecret = sessionSecret
        self.profileObserver = profileObserver

        super.init()

        loadTriggersFromSettings()

        profileObserver.observeDictionary(key: KEY_TRIGGERS) { [weak self] _, _ in
            self?.triggersDidChange()
        }
    }
}

// MARK: - API

@MainActor
extension iTermBrowserTriggerHandler {
    var javascript: String {
        return iTermBrowserTemplateLoader.loadTemplate(named: "triggers",
                                                       type: "js",
                                                       substitutions: ["SECRET": sessionSecret])
    }

    // Message from javascript
    struct TriggerMatchEvent: Codable {
        struct Match: Codable {
            enum MatchType: String, Codable {
                case urlRegex
                case pageContent
            }
            var matchType: MatchType

            // The first capture in these is the entire matching range and subsequent values are
            // captured substrings, if any.
            var urlCaptures: [String]
            var contentCaptures: [String]?

            // Unique identifier of the trigger (the key in the dictionary of triggers)
            var identifier: String

            // Unique identifier for this match. Only for content matches.
            var matchID: String?
        }
        var matches: [Match]
    }

    func handleMessage(webView: iTermBrowserWebView, message: WKScriptMessage) async -> [BrowserTriggerAction] {
        guard let body = message.body as? [String: Any],
              let secret = body["sessionSecret"] as? String,
              secret == sessionSecret else {
            DLog("Bogus message or invalid session secret \(message)")
            return []
        }
        
        // Handle request for triggers
        if body["requestTriggers"] as? Bool == true {
            DLog("Browser requested triggers")
            self.webView = webView
            sendTriggersToWebView()
            return []
        }
        
        // Handle match event
        guard let string = body["matchEvent"] as? String,
              let event = try? JSONDecoder().decode(TriggerMatchEvent.self, from: string.lossyData) else {
            DLog("Bogus match event message \(message)")
            return []
        }
        return await handle(matchEvent: event)
    }
}

// Perform actions
extension iTermBrowserTriggerHandler {
    func highlightText(matchID: String, textColor: String?, backgroundColor: String?) {
        guard let webView else {
            return
        }
        Task {
            let jsonMatchID = try! JSONEncoder().encode(matchID).lossyString
            let jsonTextColor = if let textColor {
                (try? JSONEncoder().encode(textColor).lossyString) ?? "null"
            } else {
                "null"
            }
            let jsonBackgroundColor = if let backgroundColor {
                (try? JSONEncoder().encode(backgroundColor).lossyString) ?? "null"
            } else {
                "null"
            }
            let script = "window.iTerm2Triggers?.highlightText(\(jsonMatchID), \(jsonTextColor), \(jsonBackgroundColor));"
            _ = try? await webView.safelyEvaluateJavaScript(iife(script), contentWorld: .defaultClient)
        }
    }

    func makeHyperlink(matchID: String, url: String) {
        guard let webView else {
            return
        }
        Task {
            let jsonMatchID = try! JSONEncoder().encode(matchID).lossyString
            let jsonURL = try! JSONEncoder().encode(url).lossyString
            let script = "window.iTerm2Triggers?.makeHyperlink(\(jsonMatchID), \(jsonURL));"
            _ = try? await webView.safelyEvaluateJavaScript(iife(script), contentWorld: .defaultClient)
        }
    }
}

// MARK: - Private

@MainActor
private extension iTermBrowserTriggerHandler {
    var currentTriggersJSON: String {
        let dicts = triggers.filter { $0.value.1.isEnabled }.mapValues(\.0).mapValues { dict in
            return dict.removingObject(forKey: kTriggerPerformanceKey)
        }

        return try! JSONSerialization.data(withJSONObject: dicts).lossyString
    }

    func triggersDidChange() {
        loadTriggersFromSettings()
        sendTriggersToWebView()
    }
    
    func sendTriggersToWebView() {
        let json = currentTriggersJSON
        let removeHighlightsScript = iTermBrowserTemplateLoader.loadTemplate(named: "trigger-remove-highlighted-text",
                                                                              type: "js",
                                                                              substitutions: [:])
        let call = """
        try {
            \(removeHighlightsScript)
            window.iTerm2Triggers.setTriggers(
                {sessionSecret: '\(sessionSecret)', 
                 triggers: \(json)
                });
        } catch(e) {
            console.error(e.toString());
            throw e;
        }
        """
        Task { @MainActor in
            do {
                _ = try await webView?.safelyEvaluateJavaScript(call, contentWorld: .defaultClient)
            } catch {
                DLog("\(call): \(error)")
            }
        }
    }

    func loadTriggersFromSettings() {
        triggers = [:]
        if let dicts: [[AnyHashable: Any]] = profileObserver.value(KEY_TRIGGERS) {
            for dict in dicts {
                if let trigger = Trigger(fromDict: Trigger.triggerNormalizedDictionary(dict)),
                   let browserTrigger = trigger as? BrowserTrigger {
                    triggers[UUID().uuidString] = (dict as NSDictionary, browserTrigger)
                }
            }
        }
    }

    func handle(matchEvent: TriggerMatchEvent) async -> [BrowserTriggerAction] {
        guard let delegate else {
            return []
        }
        guard let client = Client(delegate: delegate,
                                  sender: self,
                                  useInterpolation: profileObserver.value(KEY_TRIGGERS_USE_INTERPOLATED_STRINGS)) else {
            return []
        }
        var result = [BrowserTriggerAction]()
        for match in matchEvent.matches {
            let identifier = match.identifier
            guard let trigger = triggers[identifier]?.1 else {
                continue
            }
            let actions = await handle(match: match, in: trigger, url: true, client: client)
            result.append(contentsOf: actions)
            if actions.contains(.stop) {
                return result
            }
        }
        return result
    }

    struct RegexMatch {
        var capturedStrings: [String]
    }

    // A URL trigger fired.
    private func handle(match: TriggerMatchEvent.Match,
                        in trigger: BrowserTrigger,
                        url: Bool,
                        client: Client) async -> [BrowserTriggerAction] {
        if url {
            return await trigger.performBrowserAction(matchID: match.matchID,
                                                      urlCaptures: match.urlCaptures,
                                                      contentCaptures: match.contentCaptures,
                                                      in: client)
        } else {
            it_fatalError("Content matches not implemented yet")
        }
    }
}

// MARK: - Client

fileprivate class Client: NSObject {
    private let scope: iTermVariableScope
    private let object: iTermObject
    private let delegate: iTermBrowserTriggerHandlerDelegate

    let useInterpolation: Bool

    @MainActor
    init?(delegate: iTermBrowserTriggerHandlerDelegate,
         sender: iTermBrowserTriggerHandler,
         useInterpolation: Bool) {
        guard let scope = delegate.triggerHandlerScope(sender),
              let object = delegate.triggerHandlerObject(sender) else {
            return nil
        }
        self.scope = scope
        self.object = object
        self.useInterpolation = useInterpolation
        self.delegate = delegate

        super.init()
    }
}

extension Client: BrowserTriggerClient {
    var triggerDelegate: (any BrowserTriggerDelegate)? {
        delegate
    }
    
    var scopeProvider: any iTermTriggerScopeProvider { self }
}

extension Client: iTermTriggerScopeProvider {
    func performBlock(scope block: @escaping (iTermVariableScope, any iTermObject) -> Void) {
        block(scope, object)
    }

    func triggerCallbackScheduler() -> any iTermTriggerCallbackScheduler {
        self
    }
}

extension Client: iTermTriggerCallbackScheduler {
    func scheduleTriggerCallback(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}


