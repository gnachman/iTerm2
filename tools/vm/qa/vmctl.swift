// Input and accessibility driver for hands-on QA on a test VM. tools/vm/qa.sh builds it, copies
// it to the VM, and runs it there. See docs/vm-qa.md.
//
// Coordinates are global screen points with a top-left origin, as in CGEvent.
//
// Pointer
//   move X Y [STEPS]         glide the pointer to X,Y (STEPS intermediate moves, default 20)
//   click X Y / rclick X Y   glide there, then left or right click
//   down X Y / drag X Y [STEPS] / up X Y
//                            press, drag with the button held, release
//   flick DY                 a trackpad scroll with momentum, pointer still
//   pos                      print the pointer location
// Keyboard
//   key KEYCODE [MODS]       press a key; MODS is a comma-separated list of cmd,shift,opt,ctrl
//   chord KEYCODE            Control+key with real Control key events, which system hotkeys
//                            such as Control-arrow (switch Spaces) need
//   type TEXT                type ASCII text with key codes (US layout)
// Apps and windows (PID is the app's process id)
//   activate PID|BUNDLE-ID   bring an app to the front
//   front                    print the frontmost app
//   hideothers PID           hide every other regular app except Finder
//   wins PID                 list the app's windows: index, title, position, size
//   setframe PID INDEX|f X Y W H
//                            move and resize a window ("f" = the focused window)
//   menu PID TOP ITEM...     press a menu item by its titles, e.g. menu PID Shell "Split Vertically…"
//   windows                  list on-screen windows of every app
// Focus
//   f PID                    one-line summary of the focused window and element
//   focus PID                the focused element and its ancestors
//   watchfocus PID N         sample the focused element's x position N times, 50ms apart
// Other
//   shot FILE                screenshot (needs Screen Recording; run it through guirun.sh)
//   screen                   print the main screen's size in points
//   trusted                  print which permissions this process has
//   request                  ask for Accessibility, event posting and Screen Recording

import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: vmctl COMMAND [ARGS]; see the comment at the top of vmctl.swift")
    exit(2)
}

let src = CGEventSource(stateID: .hidSystemState)

func point(_ i: Int) -> CGPoint {
    return CGPoint(x: Double(args[i])!, y: Double(args[i + 1])!)
}

func pointerLocation() -> CGPoint {
    return CGEvent(source: nil)!.location
}

func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
        .post(tap: .cghidEventTap)
}

// Real users move through intermediate points, which tracking areas depend on.
func glide(to p: CGPoint, steps: Int, type: CGEventType) {
    let start = pointerLocation()
    let n = max(steps, 1)
    for i in 1...n {
        let t = Double(i) / Double(n)
        post(type, CGPoint(x: start.x + (p.x - start.x) * t, y: start.y + (p.y - start.y) * t))
        usleep(15000)
    }
}

func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!
    down.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(20000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!
    up.flags = flags
    up.post(tap: .cghidEventTap)
}

func app(_ i: Int) -> AXUIElement {
    return AXUIElementCreateApplication(pid_t(Int32(args[i])!))
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &result)
    return result
}

func axPoint(_ element: AXUIElement) -> CGPoint {
    var p = CGPoint.zero
    if let value = attribute(element, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &p)
    }
    return p
}

switch args[1] {
case "move":
    glide(to: point(2), steps: args.count > 4 ? Int(args[4])! : 20, type: .mouseMoved)
case "click":
    let p = point(2)
    glide(to: p, steps: 10, type: .mouseMoved)
    post(.leftMouseDown, p)
    usleep(50000)
    post(.leftMouseUp, p)
case "rclick":
    let p = point(2)
    glide(to: p, steps: 10, type: .mouseMoved)
    post(.rightMouseDown, p, .right)
    usleep(50000)
    post(.rightMouseUp, p, .right)
case "down":
    let p = point(2)
    glide(to: p, steps: 10, type: .mouseMoved)
    post(.leftMouseDown, p)
case "drag":
    glide(to: point(2), steps: args.count > 4 ? Int(args[4])! : 20, type: .leftMouseDragged)
case "up":
    post(.leftMouseUp, point(2))
case "flick":
    let dy = Int32(args[2])!
    func scroll(_ delta: Int32, phase: Int64, momentum: Int64) {
        let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1,
                        wheel1: delta, wheel2: 0, wheel3: 0)!
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        e.post(tap: .cghidEventTap)
        usleep(16000)
    }
    // Scroll phases: 1 began, 2 changed, 4 ended. Momentum phases: 1 begin, 2 continue, 3 end.
    scroll(dy, phase: 1, momentum: 0)
    for _ in 0..<5 {
        scroll(dy, phase: 2, momentum: 0)
    }
    scroll(0, phase: 4, momentum: 0)
    var v = dy
    scroll(v, phase: 0, momentum: 1)
    for _ in 0..<60 {
        v = v * 9 / 10
        scroll(v, phase: 0, momentum: 2)
    }
    scroll(0, phase: 0, momentum: 3)
case "pos":
    print(pointerLocation())
case "key":
    var flags: CGEventFlags = []
    if args.count > 3 {
        for modifier in args[3].split(separator: ",") {
            switch modifier {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default:
                print("unknown modifier \(modifier)")
                exit(2)
            }
        }
    }
    postKey(CGKeyCode(Int(args[2])!), flags: flags)
case "chord":
    let control: CGKeyCode = 59
    let code = CGKeyCode(Int(args[2])!)
    let controlDown = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: true)!
    controlDown.flags = .maskControl
    controlDown.post(tap: .cghidEventTap)
    usleep(30000)
    // Arrow keys carry the function and numeric pad flags on real keyboards.
    postKey(code, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
    usleep(30000)
    let controlUp = CGEvent(keyboardEventSource: src, virtualKey: control, keyDown: false)!
    controlUp.flags = []
    controlUp.post(tap: .cghidEventTap)
case "type":
    // Typing with key codes works where posting Unicode strings doesn't reach the terminal.
    let plain: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, " ": 49, "`": 50]
    let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9",
        ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'",
        "<": ",", ">": ".", "?": "/", "~": "`"]
    for ch in args[2] {
        var base = ch
        var shift = false
        if ch.isUppercase {
            base = Character(ch.lowercased())
            shift = true
        }
        if let unshifted = shifted[ch] {
            base = unshifted
            shift = true
        }
        guard let code = plain[base] else {
            print("can't type \(ch)")
            continue
        }
        postKey(code, flags: shift ? .maskShift : [])
        usleep(30000)
    }
case "activate":
    if let pid = Int32(args[2]) {
        NSRunningApplication(processIdentifier: pid)?.activate()
    } else {
        NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first?.activate()
    }
case "front":
    print(NSWorkspace.shared.frontmostApplication.map {
        "\($0.localizedName ?? "") \($0.processIdentifier)"
    } ?? "none")
case "hideothers":
    let keep = pid_t(Int32(args[2])!)
    for other in NSWorkspace.shared.runningApplications
    where other.processIdentifier != keep &&
        other.activationPolicy == .regular &&
        other.bundleIdentifier != "com.apple.finder" {
        other.hide()
    }
case "wins":
    let windows = (attribute(app(2), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    for (i, window) in windows.enumerated() {
        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
        var size = CGSize.zero
        if let value = attribute(window, kAXSizeAttribute) {
            AXValueGetValue(value as! AXValue, .cgSize, &size)
        }
        let p = axPoint(window)
        print("\(i) \(title) @\(Int(p.x)),\(Int(p.y)) \(Int(size.width))x\(Int(size.height))")
    }
case "setframe":
    let application = app(2)
    let window: AXUIElement
    if args[3] == "f" {
        window = attribute(application, kAXFocusedWindowAttribute) as! AXUIElement
    } else {
        window = (attribute(application, kAXWindowsAttribute) as! [AXUIElement])[Int(args[3])!]
    }
    var origin = CGPoint(x: Double(args[4])!, y: Double(args[5])!)
    var size = CGSize(width: Double(args[6])!, height: Double(args[7])!)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString,
                                 AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString,
                                 AXValueCreate(.cgSize, &size)!)
case "menu":
    func children(_ e: AXUIElement) -> [AXUIElement] {
        return (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
    var current = attribute(app(2), kAXMenuBarAttribute) as! AXUIElement
    for (i, name) in args[3...].enumerated() {
        var container = current
        if i > 0, let menu = children(current).first {
            container = menu
        }
        guard let item = children(container).first(where: {
            attribute($0, kAXTitleAttribute) as? String == name
        }) else {
            print("not found: \(name)")
            exit(1)
        }
        current = item
    }
    print("press:", AXUIElementPerformAction(current, kAXPressAction as CFString).rawValue)
case "windows":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w["kCGWindowLayer"] as? Int) == 0 {
        print(w["kCGWindowOwnerName"] ?? "", w["kCGWindowName"] ?? "",
              w["kCGWindowBounds"] ?? "", w["kCGWindowOwnerPID"] ?? "")
    }
case "f":
    // The tag is the last QA marker (PANE_ followed by letters or digits) in the element's
    // value, so echoing a marker in each pane tells panes apart.
    let application = app(2)
    var out = ""
    if let window = attribute(application, kAXFocusedWindowAttribute) {
        out += "win=\(attribute(window as! AXUIElement, kAXTitleAttribute) as? String ?? "")"
    }
    if let focused = attribute(application, kAXFocusedUIElementAttribute) {
        let element = focused as! AXUIElement
        let value = attribute(element, kAXValueAttribute) as? String ?? ""
        let tag = value.range(of: "PANE_[A-Z0-9]+", options: [.regularExpression, .backwards])
            .map { String(value[$0]) } ?? ""
        let p = axPoint(element)
        out += " | \(attribute(element, kAXRoleAttribute) as? String ?? "")"
        out += " desc=\(attribute(element, kAXDescriptionAttribute) as? String ?? "")"
        out += " tag=\(tag) @\(Int(p.x)),\(Int(p.y))"
    } else {
        out += " | none"
    }
    print(out)
case "focus":
    var element = attribute(app(2), kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
    var depth = 0
    while let e = element, depth < 12 {
        func describe(_ name: String) -> String {
            return attribute(e, name).map { "\($0)" } ?? "-"
        }
        print(String(repeating: "  ", count: depth) +
              "\(describe("AXRole")) id=\(describe("AXIdentifier")) " +
              "desc=\(describe("AXDescription")) title=\(describe("AXTitle")) " +
              "value=\(describe("AXValue").prefix(60))")
        element = attribute(e, kAXParentAttribute).map { $0 as! AXUIElement }
        depth += 1
    }
case "watchfocus":
    let application = app(2)
    var seen = [String]()
    for _ in 0..<Int(args[3])! {
        let x = attribute(application, kAXFocusedUIElementAttribute)
            .map { "\(Int(axPoint($0 as! AXUIElement).x))" } ?? "none"
        if seen.last != x {
            seen.append(x)
        }
        usleep(50000)
    }
    print("focus x sequence:", seen.joined(separator: " -> "))
case "shot":
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", args[2]]
    try! task.run()
    task.waitUntilExit()
case "screen":
    let frame = NSScreen.screens.first?.frame ?? .zero
    print("\(Int(frame.width))x\(Int(frame.height))")
case "trusted":
    print("accessibility: \(AXIsProcessTrusted()) postEvent: \(CGPreflightPostEventAccess()) " +
          "screenRecording: \(CGPreflightScreenCaptureAccess())")
case "request":
    print("postEvent:", CGRequestPostEventAccess())
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    print("accessibility:", AXIsProcessTrustedWithOptions(options))
    print("screenRecording:", CGRequestScreenCaptureAccess())
default:
    print("unknown command \(args[1])")
    exit(2)
}
// Let posted events drain before the process exits.
usleep(100000)
