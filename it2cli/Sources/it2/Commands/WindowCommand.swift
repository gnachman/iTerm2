import ArgumentParser
import Foundation
import ProtobufRuntime

struct Window: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "window",
        abstract: "Manage iTerm2 windows.",
        subcommands: [
            New.self,
            List.self,
            Close.self,
            Focus.self,
            Move.self,
            Resize.self,
            Fullscreen.self,
            Arrange.self,
        ]
    )
}

// MARK: - window new

extension Window {
    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "new",
            abstract: "Create new window."
        )

        @Option(name: .shortAndLong, help: "Profile to use.")
        var profile: String?

        @Option(name: .shortAndLong, help: "Command to run.")
        var command: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let createTab = ITMCreateTabRequest()
            if let profile = profile {
                createTab.profileName = profile
            }
            if let command = command {
                createTab.command = command // deprecated in proto but still functional
            }
            // No window_id = create in new window

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.createTabRequest = createTab

            let response = try client.send(request)
            guard response.submessageOneOfCase == .createTabResponse,
                  let tabResp = response.createTabResponse else {
                throw IT2Error.apiError("No create tab response")
            }
            guard tabResp.status == ITMCreateTabResponse_Status.ok else {
                throw IT2Error.apiError("Failed to create window: status \(tabResp.status.rawValue)")
            }

            print("Created new window: \(tabResp.windowId ?? "")")
        }
    }
}

// MARK: - window list

extension Window {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all windows."
        )

        @Flag(name: .long, help: "Output as JSON.")
        var json = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.listSessionsRequest = ITMListSessionsRequest()

            let response = try client.send(request)
            guard response.submessageOneOfCase == .listSessionsResponse,
                  let listResp = response.listSessionsResponse else {
                throw IT2Error.apiError("No list sessions response")
            }

            guard let windows = listResp.windowsArray as? [ITMListSessionsResponse_Window] else { return }

            // Query fullscreen state for each window.
            var fullscreenState: [String: Bool] = [:]
            for window in windows {
                guard let wid = window.windowId else { continue }
                let getReq = ITMGetPropertyRequest()
                getReq.windowId = wid
                getReq.name = "fullscreen"
                let getMsg = ITMClientOriginatedMessage()
                getMsg.id_p = client.nextId()
                getMsg.getPropertyRequest = getReq
                if let getResp = try? client.send(getMsg),
                   getResp.submessageOneOfCase == .getPropertyResponse,
                   let propResp = getResp.getPropertyResponse,
                   propResp.status == ITMGetPropertyResponse_Status.ok {
                    fullscreenState[wid] = propResp.jsonValue == "true"
                }
            }

            if json {
                var windowsData: [[String: Any]] = []
                for window in windows {
                    let wid = window.windowId ?? ""
                    var data: [String: Any] = [
                        "id": wid,
                        "tabs": Int(window.tabsArray_Count),
                        "is_fullscreen": fullscreenState[wid] ?? false,
                        "x": 0.0,
                        "y": 0.0,
                        "width": 0.0,
                        "height": 0.0,
                    ]
                    if window.hasFrame, let frame = window.frame {
                        if let origin = frame.origin {
                            data["x"] = Double(origin.x)
                            data["y"] = Double(origin.y)
                        }
                        if let size = frame.size {
                            data["width"] = Double(size.width)
                            data["height"] = Double(size.height)
                        }
                    }
                    windowsData.append(data)
                }
                if let jsonData = try? JSONSerialization.data(withJSONObject: windowsData, options: .prettyPrinted),
                   let str = String(data: jsonData, encoding: .utf8) {
                    print(str)
                }
            } else {
                for window in windows {
                    let wid = window.windowId ?? ""
                    let tabCount = window.tabsArray_Count
                    let fs = (fullscreenState[wid] == true) ? "\tFullscreen" : ""
                    var line = "\(wid)\t\(tabCount) tabs"
                    if window.hasFrame, let frame = window.frame,
                       let origin = frame.origin, let size = frame.size {
                        line += "\t(\(Int(origin.x)), \(Int(origin.y)))\t\(Int(size.width))x\(Int(size.height))"
                    }
                    line += fs
                    print(line)
                }
            }
        }
    }
}

// MARK: - window close

extension Window {
    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "Close window."
        )

        @Argument(help: "Window ID (default: current).")
        var windowId: String?

        @Flag(name: .shortAndLong, help: "Force close without confirmation.")
        var force = false

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try windowId ?? resolveCurrentWindowId(client: client)

            if !force {
                confirmAction("Close window \(id)?")
            }

            let closeReq = ITMCloseRequest()
            let closeWindows = ITMCloseRequest_CloseWindows()
            closeWindows.windowIdsArray.add(id)
            closeReq.windows = closeWindows

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.closeRequest = closeReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .closeResponse else {
                throw IT2Error.apiError("No close response")
            }
            print("Window closed")
        }
    }
}

// MARK: - window focus

extension Window {
    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "focus",
            abstract: "Focus a specific window."
        )

        @Argument(help: "Window ID.")
        var windowId: String

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let activate = ITMActivateRequest()
            activate.windowId = windowId
            activate.orderWindowFront = true

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.activateRequest = activate

            let response = try client.send(request)
            guard response.submessageOneOfCase == .activateResponse,
                  let activateResp = response.activateResponse else {
                throw IT2Error.apiError("No activate response")
            }
            guard activateResp.status == ITMActivateResponse_Status.ok else {
                throw IT2Error.targetNotFound("Window '\(windowId)' not found")
            }
            print("Focused window: \(windowId)")
        }
    }
}

// MARK: - window move

extension Window {
    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "move",
            abstract: "Move window to position."
        )

        @Argument(help: "X coordinate.")
        var x: Int

        @Argument(help: "Y coordinate.")
        var y: Int

        @Argument(help: "Window ID (default: current).")
        var windowId: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try windowId ?? resolveCurrentWindowId(client: client)

            // Get current frame first.
            let getReq = ITMGetPropertyRequest()
            getReq.windowId = id
            getReq.name = "frame"

            let getMsg = ITMClientOriginatedMessage()
            getMsg.id_p = client.nextId()
            getMsg.getPropertyRequest = getReq

            let getResp = try client.send(getMsg)
            guard getResp.submessageOneOfCase == .getPropertyResponse,
                  let propResp = getResp.getPropertyResponse,
                  propResp.status == ITMGetPropertyResponse_Status.ok,
                  let jsonStr = propResp.jsonValue,
                  let data = jsonStr.data(using: .utf8),
                  let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let size = frame["size"] as? [String: Any],
                  let w = size["width"] as? Double,
                  let h = size["height"] as? Double else {
                throw IT2Error.apiError("Could not get window frame")
            }

            // Set new frame with updated origin.
            let setReq = ITMSetPropertyRequest()
            setReq.windowId = id
            setReq.name = "frame"
            setReq.jsonValue = "{\"origin\":{\"x\":\(x),\"y\":\(y)},\"size\":{\"width\":\(Int(w)),\"height\":\(Int(h))}}"

            let setMsg = ITMClientOriginatedMessage()
            setMsg.id_p = client.nextId()
            setMsg.setPropertyRequest = setReq

            let setResp = try client.send(setMsg)
            guard setResp.submessageOneOfCase == .setPropertyResponse,
                  let setPropResp = setResp.setPropertyResponse,
                  setPropResp.status == ITMSetPropertyResponse_Status.ok else {
                throw IT2Error.apiError("Failed to move window")
            }
            print("Moved window to (\(x), \(y))")
        }
    }
}

// MARK: - window resize

extension Window {
    struct Resize: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "resize",
            abstract: "Resize window."
        )

        @Argument(help: "Width.")
        var width: Int

        @Argument(help: "Height.")
        var height: Int

        @Argument(help: "Window ID (default: current).")
        var windowId: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try windowId ?? resolveCurrentWindowId(client: client)

            let getReq = ITMGetPropertyRequest()
            getReq.windowId = id
            getReq.name = "frame"

            let getMsg = ITMClientOriginatedMessage()
            getMsg.id_p = client.nextId()
            getMsg.getPropertyRequest = getReq

            let getResp = try client.send(getMsg)
            guard getResp.submessageOneOfCase == .getPropertyResponse,
                  let propResp = getResp.getPropertyResponse,
                  propResp.status == ITMGetPropertyResponse_Status.ok,
                  let jsonStr = propResp.jsonValue,
                  let data = jsonStr.data(using: .utf8),
                  let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let origin = frame["origin"] as? [String: Any],
                  let ox = origin["x"] as? Double,
                  let oy = origin["y"] as? Double else {
                throw IT2Error.apiError("Could not get window frame")
            }

            let setReq = ITMSetPropertyRequest()
            setReq.windowId = id
            setReq.name = "frame"
            setReq.jsonValue = "{\"origin\":{\"x\":\(Int(ox)),\"y\":\(Int(oy))},\"size\":{\"width\":\(width),\"height\":\(height)}}"

            let setMsg = ITMClientOriginatedMessage()
            setMsg.id_p = client.nextId()
            setMsg.setPropertyRequest = setReq

            let setResp = try client.send(setMsg)
            guard setResp.submessageOneOfCase == .setPropertyResponse,
                  let setPropResp = setResp.setPropertyResponse,
                  setPropResp.status == ITMSetPropertyResponse_Status.ok else {
                throw IT2Error.apiError("Failed to resize window")
            }
            print("Resized window to \(width)x\(height)")
        }
    }
}

// MARK: - window fullscreen

extension Window {
    struct Fullscreen: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fullscreen",
            abstract: "Toggle fullscreen mode."
        )

        @Argument(help: "State: on, off, or toggle.")
        var state: FullscreenState

        enum FullscreenState: String, ExpressibleByArgument {
            case on, off, toggle
        }

        @Argument(help: "Window ID (default: current).")
        var windowId: String?

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let id = try windowId ?? resolveCurrentWindowId(client: client)

            // Get current fullscreen state.
            let getReq = ITMGetPropertyRequest()
            getReq.windowId = id
            getReq.name = "fullscreen"

            let getMsg = ITMClientOriginatedMessage()
            getMsg.id_p = client.nextId()
            getMsg.getPropertyRequest = getReq

            let getResp = try client.send(getMsg)
            guard getResp.submessageOneOfCase == .getPropertyResponse,
                  let propResp = getResp.getPropertyResponse,
                  propResp.status == ITMGetPropertyResponse_Status.ok else {
                throw IT2Error.apiError("Could not get fullscreen state")
            }

            let isFullscreen = propResp.jsonValue == "true"
            let newState: Bool
            switch state {
            case .on: newState = true
            case .off: newState = false
            case .toggle: newState = !isFullscreen
            }

            guard newState != isFullscreen else {
                print("Fullscreen already \(isFullscreen ? "enabled" : "disabled")")
                return
            }

            let setReq = ITMSetPropertyRequest()
            setReq.windowId = id
            setReq.name = "fullscreen"
            setReq.jsonValue = newState ? "true" : "false"

            let setMsg = ITMClientOriginatedMessage()
            setMsg.id_p = client.nextId()
            setMsg.setPropertyRequest = setReq

            let _ = try client.send(setMsg)
            print("Fullscreen \(newState ? "enabled" : "disabled")")
        }
    }
}

// MARK: - window arrange

extension Window {
    struct Arrange: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "arrange",
            abstract: "Window arrangement commands.",
            subcommands: [
                Save.self,
                Restore.self,
                List.self,
            ]
        )
    }
}

extension Window.Arrange {
    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "save",
            abstract: "Save current window arrangement."
        )

        @Argument(help: "Arrangement name.")
        var name: String

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let arrReq = ITMSavedArrangementRequest()
            arrReq.name = name
            arrReq.action = .save

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.savedArrangementRequest = arrReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .savedArrangementResponse,
                  let arrResp = response.savedArrangementResponse else {
                throw IT2Error.apiError("No saved arrangement response")
            }
            guard arrResp.status == ITMSavedArrangementResponse_Status.ok else {
                throw IT2Error.apiError("Save arrangement failed with status \(arrResp.status.rawValue)")
            }
            print("Saved arrangement: \(name)")
        }
    }

    struct Restore: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "restore",
            abstract: "Restore window arrangement."
        )

        @Argument(help: "Arrangement name.")
        var name: String

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let arrReq = ITMSavedArrangementRequest()
            arrReq.name = name
            arrReq.action = .restore

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.savedArrangementRequest = arrReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .savedArrangementResponse,
                  let arrResp = response.savedArrangementResponse else {
                throw IT2Error.apiError("No saved arrangement response")
            }
            guard arrResp.status == ITMSavedArrangementResponse_Status.ok else {
                if arrResp.status == ITMSavedArrangementResponse_Status.arrangementNotFound {
                    throw IT2Error.targetNotFound("Arrangement '\(name)' not found")
                }
                throw IT2Error.apiError("Restore arrangement failed with status \(arrResp.status.rawValue)")
            }
            print("Restored arrangement: \(name)")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List saved window arrangements."
        )

        func run() throws {
            let client = try APIClient.connect()
            defer { client.disconnect() }

            let arrReq = ITMSavedArrangementRequest()
            arrReq.action = .list

            let request = ITMClientOriginatedMessage()
            request.id_p = client.nextId()
            request.savedArrangementRequest = arrReq

            let response = try client.send(request)
            guard response.submessageOneOfCase == .savedArrangementResponse,
                  let arrResp = response.savedArrangementResponse else {
                throw IT2Error.apiError("No saved arrangement response")
            }

            if arrResp.namesArray_Count == 0 {
                print("No saved arrangements")
            } else {
                print("Saved arrangements:")
                for i in 0..<Int(arrResp.namesArray_Count) {
                    if let name = arrResp.namesArray.object(at: i) as? String {
                        print("  - \(name)")
                    }
                }
            }
        }
    }
}

// MARK: - Helpers

func resolveCurrentWindowId(client: APIClient) throws -> String {
    let focus = try fetchFocusState(client: client)
    if let id = focus.keyWindowId {
        return id
    }
    throw IT2Error.targetNotFound("No current window")
}
