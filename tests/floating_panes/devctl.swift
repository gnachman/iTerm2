// devctl: drive a -suite development instance of iTerm2 for manual and automated testing.
//
// Build: swiftc -O devctl.swift -o devctl   (devapi.sh does this for you)
//
// Every command that sends input takes the target pid and refuses unless that pid is the frontmost
// app, so synthetic input never reaches another iTerm2 (the dev build and the main app share a
// name). Coordinates are global screen points with the origin at the top left, as CGEvent uses.
//
//   devctl devpid <suite>               pid of the dev instance launched with -suite <suite>
//   devctl frontmost                    pid of the frontmost app
//   devctl activate <pid>               bring <pid> to the front
//   devctl quit <pid>                   ask <pid> to quit and wait for it
//   devctl windows <pid> [all]          window number, x, y, width, height, title (all = any layer)
//   devctl capture <windowNumber> <png> capture one window, composited, Metal layers included
//   devctl cookie <pid>                 request a Python API cookie and key from <pid> by Apple Event
//   devctl move <pid> x y               move the pointer
//   devctl click <pid> x y [n] [mods]   click; n is the click count; mods is e.g. ctrl,opt,cmd,shift
//   devctl drag <pid> x0 y0 x1 y1 [steps] [mods]
//   devctl key <pid> keycode [mods]     a key press posted to <pid>
//   devctl type <pid> text              types text into <pid>; \n becomes Return

import AppKit
import ApplicationServices
import CoreGraphics

func die(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func frontmostPID() -> pid_t {
    return NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
}

func requireFrontmost(_ pid: pid_t) {
    let front = frontmostPID()
    if front != pid {
        die("REFUSED: frontmost pid is \(front), not \(pid)")
    }
}

func flags(_ spec: String?) -> CGEventFlags {
    var result = CGEventFlags()
    for name in (spec ?? "").split(separator: ",") {
        switch name {
        case "ctrl": result.insert(.maskControl)
        case "opt": result.insert(.maskAlternate)
        case "cmd": result.insert(.maskCommand)
        case "shift": result.insert(.maskShift)
        default: die("unknown modifier \(name)")
        }
    }
    return result
}

func fourCharCode(_ s: String) -> UInt32 {
    return s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

func mouse(_ type: CGEventType, _ point: CGPoint, _ modifiers: CGEventFlags, clickCount: Int64 = 1) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        die("could not create event")
    }
    event.flags = modifiers
    event.setIntegerValueField(.mouseEventClickState, value: clickCount)
    event.post(tap: .cghidEventTap)
}

func arg(_ args: [String], _ i: Int) -> String {
    guard i < args.count else {
        die("missing argument \(i + 1)")
    }
    return args[i]
}

func pidArg(_ args: [String], _ i: Int) -> pid_t {
    guard let pid = pid_t(arg(args, i)) else {
        die("bad pid")
    }
    return pid
}

func double(_ args: [String], _ i: Int) -> Double {
    guard let value = Double(arg(args, i)) else {
        die("bad number \(arg(args, i))")
    }
    return value
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    die("usage: devctl <command> ... (see the comment at the top of devctl.swift)")
}
let command = args.removeFirst()

switch command {
case "devpid":
    let suite = arg(args, 0)
    let matches = NSWorkspace.shared.runningApplications.filter { app in
        guard app.executableURL?.lastPathComponent == "iTerm2" else {
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "command=", "-p", "\(app.processIdentifier)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let commandLine = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let words = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        return zip(words, words.dropFirst()).contains { $0 == "-suite" && $1 == suite }
    }
    guard let app = matches.first else {
        die("no instance with -suite \(suite)")
    }
    print(app.processIdentifier)

case "frontmost":
    print(frontmostPID())

case "activate":
    let pid = pidArg(args, 0)
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        die("no app with pid \(pid)")
    }
    app.activate(options: [.activateAllWindows])
    for _ in 0..<50 where frontmostPID() != pid {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    print(frontmostPID())

case "quit":
    let pid = pidArg(args, 0)
    guard let app = NSRunningApplication(processIdentifier: pid) else {
        die("no app with pid \(pid)")
    }
    _ = app.terminate()
    for _ in 0..<100 where !app.isTerminated {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    print(app.isTerminated ? "terminated" : "still running")

case "windows":
    let pid = pidArg(args, 0)
    let all = args.count > 1 && args[1] == "all"
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        if !all && layer != 0 {
            continue
        }
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let fields: [Any] = [window[kCGWindowNumber as String] ?? 0,
                             bounds["X"] ?? 0, bounds["Y"] ?? 0, bounds["Width"] ?? 0, bounds["Height"] ?? 0,
                             all ? "layer=\(layer)" : "",
                             window[kCGWindowName as String] ?? ""]
        print(fields.map { "\($0)" }.filter { !$0.isEmpty }.joined(separator: " "))
    }

case "capture":
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", arg(args, 0), arg(args, 1)]
    try? task.run()
    task.waitUntilExit()
    exit(task.terminationStatus)

case "cookie":
    // The Python client's own cookie request addresses the app by name, which could reach the
    // main iTerm2 instead of the dev build. This sends the same event to a pid.
    let pid = pidArg(args, 0)
    let event = NSAppleEventDescriptor(eventClass: fourCharCode("Itrm"),
                                       eventID: fourCharCode("rqck"),
                                       targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                       returnID: AEReturnID(kAutoGenerateReturnID),
                                       transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(NSAppleEventDescriptor(string: "devctl"), forKeyword: fourCharCode("Rcsn"))
    do {
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 120)
        guard let value = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue else {
            die("no cookie in reply: \(reply)")
        }
        print(value)
    } catch {
        die("cookie request failed: \(error)")
    }

case "move":
    let pid = pidArg(args, 0)
    requireFrontmost(pid)
    mouse(.mouseMoved, CGPoint(x: double(args, 1), y: double(args, 2)), [])

case "click":
    let pid = pidArg(args, 0)
    requireFrontmost(pid)
    let point = CGPoint(x: double(args, 1), y: double(args, 2))
    let count = args.count > 3 ? Int64(arg(args, 3)) ?? 1 : 1
    let modifiers = flags(args.count > 4 ? args[4] : nil)
    for n in 1...count {
        mouse(.leftMouseDown, point, modifiers, clickCount: n)
        usleep(30_000)
        mouse(.leftMouseUp, point, modifiers, clickCount: n)
        usleep(30_000)
    }

case "drag":
    let pid = pidArg(args, 0)
    requireFrontmost(pid)
    let start = CGPoint(x: double(args, 1), y: double(args, 2))
    let end = CGPoint(x: double(args, 3), y: double(args, 4))
    let steps = max(1, args.count > 5 ? Int(arg(args, 5)) ?? 20 : 20)
    let modifiers = flags(args.count > 6 ? args[6] : nil)
    mouse(.leftMouseDown, start, modifiers)
    usleep(50_000)
    for i in 1...steps {
        requireFrontmost(pid)
        let t = Double(i) / Double(steps)
        mouse(.leftMouseDragged,
              CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
              modifiers)
        usleep(16_000)
    }
    mouse(.leftMouseUp, end, modifiers)

case "key":
    let pid = pidArg(args, 0)
    requireFrontmost(pid)
    guard let code = CGKeyCode(arg(args, 1)) else {
        die("bad keycode")
    }
    let modifiers = flags(args.count > 2 ? args[2] : nil)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        event?.flags = modifiers
        event?.postToPid(pid)
        usleep(20_000)
    }

case "type":
    let pid = pidArg(args, 0)
    requireFrontmost(pid)
    let text = arg(args, 1).replacingOccurrences(of: "\\n", with: "\n")
    for character in text {
        if character == "\n" {
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: down)?.postToPid(pid)
                usleep(10_000)
            }
            continue
        }
        let utf16 = Array(String(character).utf16)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            event?.postToPid(pid)
            usleep(10_000)
        }
    }

default:
    die("unknown command \(command)")
}
