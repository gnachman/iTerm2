import Foundation
import ProtobufRuntime

/// High-level client for the iTerm2 API.
class APIClient {
    private let ws: WebSocketClient
    private var requestId: Int64 = 0

    private init(ws: WebSocketClient) {
        self.ws = ws
    }

    static func connect() throws -> APIClient {
        let socket = try SocketConnection.connect()
        let ws = WebSocketClient(socket: socket)

        let (cookie, key) = CookieAuth.getCredentials()

        do {
            try ws.handshake(cookie: cookie, key: key)
        } catch {
            socket.disconnect()
            throw error
        }

        return APIClient(ws: ws)
    }

    func nextId() -> Int64 {
        requestId += 1
        return requestId
    }

    func send(_ request: ITMClientOriginatedMessage) throws -> ITMServerOriginatedMessage {
        if request.id_p == 0 {
            request.id_p = nextId()
        }

        guard let data = request.data() else {
            throw IT2Error.apiError("Failed to serialize request")
        }

        try ws.sendBinary(data)

        let expectedId = request.id_p
        while true {
            let responseData = try ws.receiveBinary()
            let response = try ITMServerOriginatedMessage.parse(from: responseData)

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

    func receiveRaw() throws -> Data {
        return try ws.receiveBinary()
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
        ws.disconnect()
    }
}
