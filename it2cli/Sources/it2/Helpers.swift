import Foundation
import ProtobufRuntime

// MARK: - Split Tree Walking

/// Walk an ITMSplitTreeNode and call the visitor for each session found.
func walkSplitTree(_ node: ITMSplitTreeNode?, visitor: (ITMSessionSummary) -> Void) {
    guard let node = node else { return }
    guard let links = node.linksArray as? [ITMSplitTreeNode_SplitTreeLink] else { return }
    for link in links {
        if link.childOneOfCase == .session, let s = link.session {
            visitor(s)
        }
        if link.childOneOfCase == .node {
            walkSplitTree(link.node, visitor: visitor)
        }
    }
}

/// Collect all session UUIDs from a split tree.
func collectSessionIds(from node: ITMSplitTreeNode?) -> [String] {
    var ids: [String] = []
    walkSplitTree(node) { s in
        if let id = s.uniqueIdentifier { ids.append(id) }
    }
    return ids
}

// MARK: - Hex Color Parsing

/// Parse a hex color string (e.g., "#FF0000") into 0.0-1.0 RGB components.
func parseHexColor(_ hex: String) throws -> (r: Double, g: Double, b: Double) {
    var str = hex
    if str.hasPrefix("#") { str = String(str.dropFirst()) }
    guard str.count == 6 else {
        throw IT2Error.invalidArgument("Invalid color format: \(hex). Use 6-digit hex like #FF0000.")
    }
    let scanner = Scanner(string: str)
    var rgb: UInt64 = 0
    guard scanner.scanHexInt64(&rgb) else {
        throw IT2Error.invalidArgument("Invalid hex color: \(hex)")
    }
    let r = Double((rgb >> 16) & 0xFF) / 255.0
    let g = Double((rgb >> 8) & 0xFF) / 255.0
    let b = Double(rgb & 0xFF) / 255.0
    return (r, g, b)
}

/// Convert a hex color string to iTerm2's JSON color format.
func colorToJSON(_ hex: String) throws -> String {
    let (r, g, b) = try parseHexColor(hex)
    return "{\"Red Component\": \(r), \"Green Component\": \(g), \"Blue Component\": \(b), \"Color Space\": \"sRGB\"}"
}

// MARK: - Confirmation Prompt

/// Show a confirmation prompt on stderr. Returns true if user confirms.
/// On decline, prints "Aborted!" to stderr and exits with code 1.
@discardableResult
func confirmAction(_ prompt: String) -> Bool {
    FileHandle.standardError.write(Data("\(prompt) [y/N] ".utf8))
    if let line = Swift.readLine(), line.lowercased().hasPrefix("y") {
        return true
    }
    FileHandle.standardError.write(Data("Aborted!\n".utf8))
    Foundation.exit(1)
}

// MARK: - JSON Output

/// Serialize to pretty-printed JSON and print to stdout.
func printJSON(_ object: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}

// MARK: - JSON String Helpers

/// Trim surrounding quote characters from a JSON-encoded string value.
func trimJSONQuotes(_ s: String?) -> String {
    guard let s = s else { return "" }
    return s.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}

/// Wrap a string as a JSON string value.
/// Uses JSONEncoder (doesn't escape `/`) rather than JSONSerialization (which does).
func jsonString(_ s: String) -> String {
    if let data = try? JSONEncoder().encode(s),
       let result = String(data: data, encoding: .utf8) {
        return result
    }
    // Fallback for edge cases where JSONEncoder fails:
    let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

// MARK: - Focus State

/// Parsed focus state from a FocusResponse.
struct FocusState {
    var keyWindowId: String?
    var selectedTabIds: [String] = []
    var sessionIds: [String] = []
}

/// Send a FocusRequest and parse the response into structured state.
func fetchFocusState(client: APIClient) throws -> FocusState {
    let focusReq = ITMClientOriginatedMessage()
    focusReq.id_p = client.nextId()
    focusReq.focusRequest = ITMFocusRequest()

    let focusResp = try client.send(focusReq)
    guard focusResp.submessageOneOfCase == .focusResponse,
          let focus = focusResp.focusResponse,
          let notifications = focus.notificationsArray as? [ITMFocusChangedNotification] else {
        throw IT2Error.apiError("Could not get focus state")
    }

    var state = FocusState()
    for notification in notifications {
        switch notification.eventOneOfCase {
        case .window:
            if let w = notification.window,
               w.windowStatus == .terminalWindowBecameKey {
                state.keyWindowId = w.windowId
            }
        case .selectedTab:
            state.selectedTabIds.append(notification.selectedTab ?? "")
        case .session:
            state.sessionIds.append(notification.session ?? "")
        default:
            break
        }
    }
    return state
}

// MARK: - List Sessions

/// Fetch all windows from ListSessionsRequest.
func fetchWindows(client: APIClient) throws -> [ITMListSessionsResponse_Window] {
    let request = ITMClientOriginatedMessage()
    request.id_p = client.nextId()
    request.listSessionsRequest = ITMListSessionsRequest()

    let response = try client.send(request)
    guard response.submessageOneOfCase == .listSessionsResponse,
          let listResp = response.listSessionsResponse,
          let windows = listResp.windowsArray as? [ITMListSessionsResponse_Window] else {
        throw IT2Error.apiError("Could not list sessions")
    }
    return windows
}
