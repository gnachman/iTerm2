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
    private let channel: APIChannel
    private var requestId: Int64 = 0

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

    /// Resolve an optional session ID to a concrete UUID.
    /// If nil, queries iTerm2 for the currently focused session.
    func resolveSessionId(_ sessionId: String?) throws -> String {
        if let id = sessionId {
            return APIClient.normalizeSessionId(id)
        }

        // Use focus state to find the key window's selected tab, then find
        // the first session in that tab via ListSessions.
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
                        let ids = collectSessionIds(from: tab.root)
                        if let first = ids.first { return first }
                    }
                }
                if let firstTab = tabs.first {
                    let ids = collectSessionIds(from: firstTab.root)
                    if let first = ids.first { return first }
                }
            }
        }

        throw IT2Error.targetNotFound("No active session found")
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
