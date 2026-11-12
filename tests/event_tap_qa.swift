// Manual QA helper for keyboard event taps (issue 12645). Run on a test VM, not your own Mac.
//
//   swiftc -O tests/event_tap_qa.swift -o /tmp/event_tap_qa
//   event_tap_qa taps [NAME]          list keyboard event taps, optionally only those owned by
//                                     processes whose name contains NAME
//   event_tap_qa chord MOD KEYCODE    press and release a modifier around a key, with the real
//                                     modifier key events and device-dependent flag bits
//   event_tap_qa hold MOD KEYCODE COUNT
//                                     hold a modifier and press a key COUNT times, 150ms apart,
//                                     e.g. hold lcmd 48 2 to Cmd-Tab two apps back
//   event_tap_qa doubletap MOD        press and release a modifier twice, 80ms apart
//   event_tap_qa activate-type BUNDLE MOD KEYCODE [GAP_US]
//                                     activate an app and send a chord immediately, before it
//                                     has finished activating, GAP_US microseconds between key
//                                     events (default 30000; 0 makes the keys arrive before
//                                     the app has finished activating)
//
//   event_tap_qa interrupted MOD KEYCODE
//                                     modifier, key, modifier in quick succession, which must not
//                                     count as a double tap
//   event_tap_qa flags                print the modifier flags the system thinks are down, to catch
//                                     a stuck modifier
//
// MOD is one of lcmd, rcmd, lctrl, rctrl, lopt, ropt, lshift, fn.

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)

struct Modifier {
    var keyCode: CGKeyCode
    var flags: CGEventFlags
}

// Device-dependent bits from IOLLEvent.h.
func modifier(_ name: String) -> Modifier {
    switch name {
    case "lctrl": return Modifier(keyCode: 59, flags: [.maskControl, CGEventFlags(rawValue: 0x1)])
    case "rctrl": return Modifier(keyCode: 62, flags: [.maskControl, CGEventFlags(rawValue: 0x2000)])
    case "lshift": return Modifier(keyCode: 56, flags: [.maskShift, CGEventFlags(rawValue: 0x2)])
    case "lcmd": return Modifier(keyCode: 55, flags: [.maskCommand, CGEventFlags(rawValue: 0x8)])
    case "rcmd": return Modifier(keyCode: 54, flags: [.maskCommand, CGEventFlags(rawValue: 0x10)])
    case "lopt": return Modifier(keyCode: 58, flags: [.maskAlternate, CGEventFlags(rawValue: 0x20)])
    case "ropt": return Modifier(keyCode: 61, flags: [.maskAlternate, CGEventFlags(rawValue: 0x40)])
    case "fn": return Modifier(keyCode: 63, flags: [.maskSecondaryFn])
    default:
        print("unknown modifier \(name)")
        exit(2)
    }
}

func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

func chord(_ mod: Modifier, _ keyCode: CGKeyCode, gap: useconds_t = 30000) {
    post(mod.keyCode, down: true, flags: mod.flags)
    usleep(gap)
    post(keyCode, down: true, flags: mod.flags)
    usleep(gap)
    post(keyCode, down: false, flags: mod.flags)
    usleep(gap)
    post(mod.keyCode, down: false, flags: [])
}

func processName(_ pid: pid_t) -> String {
    return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
}

func listTaps(_ filter: String?) {
    var count: UInt32 = 0
    CGGetEventTapList(0, nil, &count)
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    CGGetEventTapList(count, &taps, &count)
    let keyboardMask: UInt64 = (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)
    for tap in taps.prefix(Int(count)) where tap.eventsOfInterest & keyboardMask != 0 {
        let owner = processName(tap.tappingProcess)
        if let filter, !owner.localizedCaseInsensitiveContains(filter) {
            continue
        }
        let kind = tap.options == .listenOnly ? "listen" : "FILTER"
        var events = [String]()
        if tap.eventsOfInterest & (1 << CGEventType.keyDown.rawValue) != 0 { events.append("keyDown") }
        if tap.eventsOfInterest & (1 << CGEventType.keyUp.rawValue) != 0 { events.append("keyUp") }
        if tap.eventsOfInterest & (1 << CGEventType.flagsChanged.rawValue) != 0 { events.append("flags") }
        print("id=\(tap.eventTapID) \(kind) owner=\(owner) enabled=\(tap.enabled) point=\(tap.tapPoint.rawValue) " +
              "events=\(events.joined(separator: ",")) latency(us) avg=\(tap.avgUsecLatency) max=\(tap.maxUsecLatency)")
    }
}

guard args.count > 1 else {
    print("see the comment at the top of event_tap_qa.swift")
    exit(2)
}
switch args[1] {
case "taps":
    listTaps(args.count > 2 ? args[2] : nil)
case "chord":
    chord(modifier(args[2]), CGKeyCode(Int(args[3])!))
case "hold":
    let mod = modifier(args[2])
    let keyCode = CGKeyCode(Int(args[3])!)
    post(mod.keyCode, down: true, flags: mod.flags)
    usleep(150000)
    for _ in 0..<Int(args[4])! {
        post(keyCode, down: true, flags: mod.flags)
        usleep(50000)
        post(keyCode, down: false, flags: mod.flags)
        usleep(150000)
    }
    post(mod.keyCode, down: false, flags: [])
case "interrupted":
    let mod = modifier(args[2])
    let keyCode = CGKeyCode(Int(args[3])!)
    post(mod.keyCode, down: true, flags: mod.flags)
    usleep(40000)
    post(mod.keyCode, down: false, flags: [])
    usleep(40000)
    post(keyCode, down: true, flags: [])
    usleep(40000)
    post(keyCode, down: false, flags: [])
    usleep(40000)
    post(mod.keyCode, down: true, flags: mod.flags)
    usleep(40000)
    post(mod.keyCode, down: false, flags: [])
case "flags":
    let hid = CGEventSource.flagsState(.hidSystemState).rawValue
    let session = CGEventSource.flagsState(.combinedSessionState).rawValue
    print(String(format: "hid=0x%llx session=0x%llx", hid, session))
case "doubletap":
    let mod = modifier(args[2])
    for _ in 0..<2 {
        post(mod.keyCode, down: true, flags: mod.flags)
        usleep(80000)
        post(mod.keyCode, down: false, flags: [])
        usleep(80000)
    }
case "activate-type":
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else {
        print("\(args[2]) isn't running")
        exit(1)
    }
    app.activate()
    chord(modifier(args[3]), CGKeyCode(Int(args[4])!), gap: args.count > 5 ? useconds_t(args[5])! : 30000)
default:
    print("unknown command \(args[1])")
    exit(2)
}
