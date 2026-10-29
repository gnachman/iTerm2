// Manual test for the it2 AppleEvent guard (issue 13175).
//
// it2 gets an API cookie by sending iTerm2 a "request cookie" AppleEvent. On the receiving side,
// AE.framework asks tccd whether the sender may automate iTerm2 and blocks a serial queue until
// tccd answers. If tccd puts up a consent prompt nobody answers, every later AppleEvent strands a
// thread in iTerm2 until the dispatch thread pool is exhausted and the app hangs.
//
// The proposed guard: before sending, call AEDeterminePermissionToAutomateTarget with
// askUserIfNeeded=false and skip the send if it says consent would be required. This tool checks
// whether that precheck predicts what actually happens when the event is sent.
//
// Build:  swiftc -O -o aeguard aeguard.swift
// Usage:  aeguard [--bundle ID] [--ask] [--send | --guarded-send] [--timeout SECONDS]
//   (default)       Report how TCC sees this process and run the precheck only. Never prompts.
//   --ask           Run the precheck with askUserIfNeeded=true (may prompt).
//   --send          Send the real event regardless of the precheck.
//   --guarded-send  Send only if the precheck returns noErr. This is the proposed it2 behavior.
//   --timeout       AppleEvent reply timeout for sends, in seconds (default 5).

import Foundation
import CoreServices
import AppKit

func fourCC(_ s: String) -> OSType {
    return s.utf8.reduce(0) { ($0 << 8) | OSType($1) }
}

func describe(_ status: OSStatus) -> String {
    switch status {
    case noErr: return "noErr (permitted)"
    case -1744: return "errAEEventWouldRequireUserConsent (-1744)"
    case -1743: return "errAEEventNotPermitted (-1743)"
    case -1712: return "errAETimeout (-1712)"
    case -600: return "procNotFound (-600): target not running"
    case -609: return "connectionInvalid (-609)"
    default: return "OSStatus \(status)"
    }
}

func path(of pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? String(cString: buffer) : "?"
}

func parent(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
        return nil
    }
    return pid_t(info.pbi_ppid)
}

// Private SPI in libsystem; TCC attributes requests to this process.
func responsiblePID(for pid: pid_t) -> pid_t? {
    typealias Fn = @convention(c) (pid_t) -> pid_t
    guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
        return nil
    }
    return unsafeBitCast(sym, to: Fn.self)(pid)
}

func targetDescriptor(bundleID: String) -> AEAddressDesc {
    var desc = AEAddressDesc()
    let data = Array(bundleID.utf8)
    let err = AECreateDesc(typeApplicationBundleID, data, data.count, &desc)
    precondition(err == noErr, "AECreateDesc failed: \(err)")
    return desc
}

func now() -> Double {
    return ProcessInfo.processInfo.systemUptime
}

// MARK: - Arguments

var bundleID = "com.googlecode.iterm2"
var ask = false
var send = false
var guardedSend = false
var timeoutSeconds = 5.0

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--bundle": bundleID = args.next() ?? bundleID
    case "--ask": ask = true
    case "--send": send = true
    case "--guarded-send": guardedSend = true
    case "--timeout": timeoutSeconds = Double(args.next() ?? "") ?? timeoutSeconds
    default:
        FileHandle.standardError.write(Data("unknown argument \(arg)\n".utf8))
        exit(2)
    }
}

// MARK: - Who TCC thinks is asking

let me = getpid()
print("pid \(me): \(path(of: me))")
var chain = [String]()
var cursor = parent(of: me)
while let p = cursor, p > 1, chain.count < 20 {
    chain.append("\(p) \(URL(fileURLWithPath: path(of: p)).lastPathComponent)")
    cursor = parent(of: p)
}
print("ancestors: \(chain.joined(separator: " <- "))")
if let r = responsiblePID(for: me) {
    print("responsible pid \(r): \(path(of: r))")
} else {
    print("responsible pid: unavailable")
}
let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
print("target \(bundleID): \(running.map { "pid \($0.processIdentifier)" }.joined(separator: ", ").nonEmpty ?? "not running")")

extension String {
    var nonEmpty: String? { return isEmpty ? nil : self }
}

// MARK: - Precheck

var target = targetDescriptor(bundleID: bundleID)
let eventClass = fourCC("Itrm")
let eventID = fourCC("rqck")

let t0 = now()
let precheck = AEDeterminePermissionToAutomateTarget(&target, eventClass, eventID, ask)
print(String(format: "precheck (askUserIfNeeded=%@): %@ in %.3fs",
             ask ? "true" : "false", describe(precheck), now() - t0))

// MARK: - Send

if guardedSend && precheck != noErr {
    print("guarded send: skipped because the precheck did not return noErr")
} else if send || guardedSend {
    var event = AppleEvent()
    var err = OSStatus(AECreateAppleEvent(eventClass, eventID, &target,
                                 AEReturnID(kAutoGenerateReturnID), AETransactionID(kAnyTransactionID),
                                 &event))
    precondition(err == noErr, "AECreateAppleEvent failed: \(err)")
    let name = Array("aeguard".utf8)
    err = OSStatus(AEPutParamPtr(&event, fourCC("Rcsn"), typeUTF8Text, name, name.count))
    precondition(err == noErr, "AEPutParamPtr failed: \(err)")

    var reply = AppleEvent()
    let ticks = Int(timeoutSeconds * 60)
    let t1 = now()
    err = AESendMessage(&event, &reply, AESendMode(kAEWaitReply), ticks)
    let elapsed = now() - t1
    var result = ""
    var errorNumber: Int32 = 0
    if err == noErr {
        var desc = AEDesc()
        if AEGetParamDesc(&reply, keyDirectObject, typeUTF8Text, &desc) == noErr {
            let size = AEGetDescDataSize(&desc)
            var bytes = [UInt8](repeating: 0, count: size)
            AEGetDescData(&desc, &bytes, size)
            // Don't print the cookie itself, only that one came back.
            result = String(decoding: bytes, as: UTF8.self).isEmpty ? "empty reply" : "got a cookie"
            AEDisposeDesc(&desc)
        }
        var size = 0
        var type: DescType = 0
        AEGetParamPtr(&reply, keyErrorNumber, typeSInt32, &type, &errorNumber, MemoryLayout<Int32>.size, &size)
    }
    print(String(format: "send: %@ in %.3fs%@%@", describe(err), elapsed,
                 errorNumber != 0 ? ", reply error \(errorNumber)" : "",
                 result.isEmpty ? "" : ", \(result)"))
    AEDisposeDesc(&reply)
    AEDisposeDesc(&event)
}
AEDisposeDesc(&target)
