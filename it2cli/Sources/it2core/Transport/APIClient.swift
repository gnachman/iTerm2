import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

/// High-level client for the iTerm2 API.
///
/// Transport-agnostic: it composes an `APIChannel` and layers on request-id
/// assignment, response matching, and the higher-level helpers used across
/// commands. The transport (socket vs. in-process) varies via the injected
/// channel, not via subclassing.
final class APIClient {
    /// Internal so a caller that runs several commands back to back can lend the same connection
    /// to each (see SharedAPIClientFactory).
    let channel: APIChannel
    private var requestId: Int64 = 0

    /// The iTerm2 session this invocation arrived over, for a remote call.
    ///
    /// A remote host has no way to name a session: TERM_SESSION_ID is never injected there, so
    /// "the current session" is not something the caller can know. The app does know, because
    /// the call came in over one conductor and a conductor belongs to exactly one session.
    ///
    /// Supplied by the host (IT2Embedded), never from arguments, for the same reason as
    /// IT2Context.originIdentifier: the remote controls its argv.
    ///
    /// Nil for a local call, which keeps the focused-session default.
    var originSessionID: String?

    /// The environment of whoever invoked it2: the local process's for a local call, the
    /// allowlisted slice that crossed the wire for a remote one. Used to work out which session
    /// the caller is in when it did not say.
    var callerEnvironment: [String: String] = [:]

    /// Which machine the caller is on, for pane addressing. See TmuxPaneLocator.
    var originIdentifier: String?

    init(channel: APIChannel) {
        self.channel = channel
    }

    /// Connect to a running iTerm2 over its local unix domain socket.
    static func connect() throws -> APIClient {
        return APIClient(channel: try SocketChannel.connect())
    }

    func nextId() -> Int64 {
        requestId += 1
        return requestId
    }

    func send(_ request: ITMClientOriginatedMessage) throws -> ITMServerOriginatedMessage {
        if request.id_p == 0 {
            request.id_p = nextId()
        }

        try channel.send(request)

        let expectedId = request.id_p
        while true {
            let response = try channel.receiveMessage()

            if response.submessageOneOfCase == .error {
                throw IT2Error.apiError("Server error: \(response.error ?? "unknown")")
            }

            if response.id_p == expectedId {
                return response
            }
        }
    }

    /// The pane this caller is in, from its environment, or nil when it is not in tmux or the
    /// address is malformed.
    static func paneAddressFromEnvironment(_ environment: [String: String]) -> TmuxAddress? {
        guard let tmux = environment["TMUX"], !tmux.isEmpty else {
            return nil
        }
        return TmuxAddress(tmux: tmux, pane: environment["TMUX_PANE"] ?? "")
    }

    /// The session this caller is in, from its environment alone, or nil.
    ///
    /// TERM_SESSION_ID is used ONLY outside tmux. A tmux pane inherits whatever the server had
    /// when it started, which is not this pane and need not even be an iTerm2 session: a tmux
    /// session created in another terminal emulator and later attached from iTerm2 hands its
    /// panes that app's value. Inside tmux the pane address is the only trustworthy signal, and
    /// when it does not resolve the caller falls through rather than guessing.
    static func sessionIdFromEnvironment(_ environment: [String: String]) -> String? {
        if let tmux = environment["TMUX"], !tmux.isEmpty {
            return nil
        }
        guard let raw = environment["TERM_SESSION_ID"],
              let colon = raw.firstIndex(of: ":") else {
            return nil
        }
        let guid = String(raw[raw.index(after: colon)...])
        return guid.isEmpty ? nil : guid
    }

    /// Resolve an optional session ID to a concrete UUID.    /// Resolve an optional session ID to a concrete UUID.
    /// If nil, queries iTerm2 for the currently focused session.
    func resolveSessionId(_ sessionId: String?) throws -> String {
        if let id = sessionId {
            return APIClient.normalizeSessionId(id)
        }
        // The caller's own environment usually says exactly where it is, and that beats the
        // focused session, which is merely whatever the user happens to be looking at.
        if let address = APIClient.paneAddressFromEnvironment(callerEnvironment),
           let guid = (try? sessionIdForTmuxPane(address, origin: originIdentifier)) ?? nil,
           !guid.isEmpty {
            return guid
        }
        if let fromEnvironment = APIClient.sessionIdFromEnvironment(callerEnvironment) {
            return fromEnvironment
        }
        // A remote call defaults to the session it arrived on, not to whatever the user is
        // looking at. Falling through to focus state would let a command typed on a remote host
        // land on an unrelated local tab, which is the misdelivery this addressing exists to
        // prevent; and the remote has no way to name its own session to avoid it.
        if let originSessionID, !originSessionID.isEmpty {
            return APIClient.normalizeSessionId(originSessionID)
        }

        // Last resort: the caller is not in an iTerm2 session we can identify at all (cron, the
        // Finder, another terminal app), or its pane did not resolve. Use focus state to find
        // the key window's selected tab, then its active session via ListSessions. That can be a
        // floating pane, which is not in the tab's tree.
        let focus = try fetchFocusState(client: self)
        guard let keyWindowId = focus.keyWindowId else {
            throw IT2Error.targetNotFound("No key window found")
        }

        let windows = try fetchWindows(client: self)

        // The last selectedTabId in focus state corresponds to the key window.
        let selectedTabId = focus.selectedTabIds.last

        for win in windows {
            if win.windowId == keyWindowId,
               let tabs = win.tabsArray as? [ITMListSessionsResponse_Tab] {
                for tab in tabs {
                    if tab.tabId == selectedTabId {
                        if let active = tab.activeSessionId, !active.isEmpty { return active }
                        let ids = collectSessionIds(in: tab)
                        if let first = ids.first { return first }
                    }
                }
                if let firstTab = tabs.first {
                    if let active = firstTab.activeSessionId, !active.isEmpty { return active }
                    let ids = collectSessionIds(in: firstTab)
                    if let first = ids.first { return first }
                }
            }
        }

        throw IT2Error.targetNotFound("No active session found")
    }

    /// Invokes a built-in function and returns its JSON result, or "" when it
    /// returned nothing. With a session ID the function runs in that session's
    /// context; without one it runs in the app context and names its own
    /// target. `failure` prefixes the reason when the function itself reports
    /// an error, which throws `IT2Error.functionFailed`. Anything else, such as a
    /// dropped connection, throws as `send` does.
    func invoke(_ invocation: String, sessionID: String? = nil, failure: String) throws -> String {
        let invoke = ITMInvokeFunctionRequest()
        if let sessionID {
            let sessionContext = ITMInvokeFunctionRequest_Session()
            sessionContext.sessionId = sessionID
            invoke.session = sessionContext
        } else {
            invoke.app = ITMInvokeFunctionRequest_App()
        }
        invoke.invocation = invocation

        let request = ITMClientOriginatedMessage()
        request.id_p = nextId()
        request.invokeFunctionRequest = invoke

        let response = try send(request)
        guard response.submessageOneOfCase == .invokeFunctionResponse,
              let invokeResp = response.invokeFunctionResponse else {
            throw IT2Error.apiError("No invoke function response")
        }
        if invokeResp.dispositionOneOfCase == .error {
            let reason = invokeResp.error?.errorReason ?? "unknown"
            throw IT2Error.functionFailed("\(failure): \(reason)")
        }
        return invokeResp.success?.jsonResult ?? ""
    }

    /// Block until the next server message is available. Used by streaming
    /// (monitor) commands that receive an unbounded sequence of notifications.
    func receiveMessage() throws -> ITMServerOriginatedMessage {
        return try channel.receiveMessage()
    }

    static func normalizeSessionId(_ id: String) -> String {
        if id == "active" || id == "all" { return id }
        // Match wXtYpZ:UUID format (ITERM_SESSION_ID).
        if let colonRange = id.range(of: #"^w\d+t\d+p\d+:"#, options: .regularExpression) {
            return String(id[colonRange.upperBound...])
        }
        // Match wXtYpZ.UUID format (session.termid).
        if let dotRange = id.range(of: #"^w\d+t\d+p\d+\."#, options: .regularExpression) {
            return String(id[dotRange.upperBound...])
        }
        return id
    }

    func disconnect() {
        channel.disconnect()
    }
}
