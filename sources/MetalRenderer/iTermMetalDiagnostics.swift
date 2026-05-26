//
//  iTermMetalDiagnostics.swift
//  iTerm2
//
//  Always-on, low-overhead ring buffer that records the Metal frame lifecycle
//  plus display-reconfiguration and sleep/wake events. Intended for diagnosing
//  bugs that only reproduce in the field (e.g., issue 7459: terminals go blank
//  with the GPU renderer after a display configuration change). When the problem
//  recurs the user invokes "Save Metal Diagnostics..." which dumps these rings to
//  a file so we can see what the pipeline did at and after the reconfiguration.
//
//  This is deliberately independent of the DLog firehose so it does not need to
//  be enabled ahead of time and imposes negligible overhead.
//

import AppKit
import CoreGraphics
import QuartzCore

@objc(iTermMetalDiagnostics)
public class iTermMetalDiagnostics: NSObject {
    @objc public class func sharedInstance() -> iTermMetalDiagnostics { return shared }
    private static let shared = iTermMetalDiagnostics()

    private struct Entry {
        let machTime: CFTimeInterval
        let date: Date
        let onMainThread: Bool
        let text: String
    }

    // A fixed-capacity ring with O(1) append.
    private struct Ring {
        private var buffer: [Entry?]
        private var next = 0
        private var filled = 0
        let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
            buffer = Array(repeating: nil, count: capacity)
        }

        mutating func append(_ entry: Entry) {
            buffer[next] = entry
            next = (next + 1) % capacity
            if filled < capacity {
                filled += 1
            }
        }

        func ordered() -> [Entry] {
            var result = [Entry]()
            result.reserveCapacity(filled)
            let start = (filled < capacity) ? 0 : next
            for i in 0..<filled {
                if let entry = buffer[(start + i) % capacity] {
                    result.append(entry)
                }
            }
            return result
        }
    }

    private let lock = NSLock()
    private var globalRing = Ring(capacity: 512)
    private var sessionRings = [String: Ring]()
    private let sessionCapacity = 1024
    private var started = false

    // MARK: - Lifecycle

    @objc public func startIfNeeded() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else {
            return
        }

        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(screenParametersChanged(_:)),
                           name: NSApplication.didChangeScreenParametersNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(windowChangedScreen(_:)),
                           name: NSWindow.didChangeScreenNotification,
                           object: nil)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self,
                                   selector: #selector(willSleep(_:)),
                                   name: NSWorkspace.willSleepNotification,
                                   object: nil)
        workspaceCenter.addObserver(self,
                                   selector: #selector(didWake(_:)),
                                   name: NSWorkspace.didWakeNotification,
                                   object: nil)
        workspaceCenter.addObserver(self,
                                   selector: #selector(screensDidSleep(_:)),
                                   name: NSWorkspace.screensDidSleepNotification,
                                   object: nil)
        workspaceCenter.addObserver(self,
                                   selector: #selector(screensDidWake(_:)),
                                   name: NSWorkspace.screensDidWakeNotification,
                                   object: nil)

        CGDisplayRegisterReconfigurationCallback(iTermMetalDiagnosticsDisplayReconfigurationCallback, nil)
        recordGlobalEvent("Diagnostics started. \(Self.screensDescription())")
    }

    // MARK: - Recording (callable from any thread)

    @objc public func recordGlobalEvent(_ text: String) {
        let entry = makeEntry(text)
        lock.lock()
        globalRing.append(entry)
        lock.unlock()
    }

    @objc(recordSessionEvent:text:)
    public func recordSessionEvent(_ session: String, _ text: String) {
        let entry = makeEntry(text)
        lock.lock()
        if sessionRings[session] == nil {
            sessionRings[session] = Ring(capacity: sessionCapacity)
        }
        sessionRings[session]?.append(entry)
        lock.unlock()
    }

    private func makeEntry(_ text: String) -> Entry {
        return Entry(machTime: CACurrentMediaTime(),
                     date: Date(),
                     onMainThread: Thread.isMainThread,
                     text: text)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Dump

    @objc public func dump() -> String {
        let now = CACurrentMediaTime()
        lock.lock()
        let global = globalRing.ordered()
        let sessionKeys = sessionRings.keys.sorted()
        let sessions = sessionKeys.map { ($0, sessionRings[$0]!.ordered()) }
        lock.unlock()

        var lines = [String]()
        lines.append("==== iTerm2 Metal Diagnostics ====")
        lines.append("Dumped at \(Date())")
        lines.append("")
        lines.append("---- Current screens ----")
        lines.append(Self.screensDescription())
        lines.append("")
        lines.append("---- Most recent state per session ----")
        if sessions.isEmpty {
            lines.append("(none)")
        }
        for (key, entries) in sessions {
            let lastState = entries.last(where: { $0.text.contains("VIEWSTATE") })
            let lastEvent = entries.last
            lines.append("\(key):")
            lines.append("  last state: \(lastState.map { format($0, now: now) } ?? "(no VIEWSTATE recorded)")")
            lines.append("  last event: \(lastEvent.map { format($0, now: now) } ?? "(none)")")
        }
        lines.append("")
        lines.append("---- Global events (oldest first; abs time then t = seconds before dump) ----")
        if global.isEmpty {
            lines.append("(none)")
        } else {
            lines.append(contentsOf: global.sorted { $0.machTime < $1.machTime }.map { format($0, now: now) })
        }
        lines.append("")
        for (key, entries) in sessions {
            lines.append("---- Session \(key) (oldest first; abs time then t = seconds before dump) ----")
            if entries.isEmpty {
                lines.append("(none)")
            } else {
                lines.append(contentsOf: entries.sorted { $0.machTime < $1.machTime }.map { format($0, now: now) })
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func format(_ entry: Entry, now: CFTimeInterval) -> String {
        let ago = now - entry.machTime
        let thread = entry.onMainThread ? "main" : "bg  "
        let absolute = Self.timeFormatter.string(from: entry.date)
        return String(format: "%@ t-%7.3f [%@] %@", absolute, ago, thread, entry.text)
    }

    // MARK: - Event handlers

    @objc private func screenParametersChanged(_ notification: Notification) {
        recordGlobalEvent("NSApplicationDidChangeScreenParameters. \(Self.screensDescription())")
    }

    @objc private func windowChangedScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        let screen = Self.describe(window.screen)
        recordGlobalEvent("NSWindowDidChangeScreen window=\(ObjectIdentifier(window)) title=\(window.title) screen=\(screen)")
    }

    @objc private func willSleep(_ notification: Notification) {
        recordGlobalEvent("NSWorkspaceWillSleep")
    }

    @objc private func didWake(_ notification: Notification) {
        recordGlobalEvent("NSWorkspaceDidWake. \(Self.screensDescription())")
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        recordGlobalEvent("NSWorkspaceScreensDidSleep")
    }

    @objc private func screensDidWake(_ notification: Notification) {
        recordGlobalEvent("NSWorkspaceScreensDidWake. \(Self.screensDescription())")
    }

    // MARK: - Screen description

    fileprivate static func screensDescription() -> String {
        let main = CGMainDisplayID()
        let parts = NSScreen.screens.map { screen -> String in
            return describe(screen, mainDisplayID: main)
        }
        return "screens=[\(parts.joined(separator: ", "))]"
    }

    fileprivate static func describe(_ screen: NSScreen?, mainDisplayID: CGDirectDisplayID = CGMainDisplayID()) -> String {
        guard let screen else {
            return "nil"
        }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let frame = screen.frame
        let isMain = (displayID == mainDisplayID) ? " main" : ""
        return String(format: "{id=%u scale=%.1f fps=%ld frame=(%.0f,%.0f %.0fx%.0f)%@}",
                      displayID,
                      screen.backingScaleFactor,
                      screen.maximumFramesPerSecond,
                      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                      isMain)
    }

    fileprivate func recordDisplayReconfiguration(display: CGDirectDisplayID,
                                                  flags: CGDisplayChangeSummaryFlags) {
        recordGlobalEvent("CGDisplayReconfiguration display=\(display) flags=[\(Self.describe(flags))]")
    }

    private static func describe(_ flags: CGDisplayChangeSummaryFlags) -> String {
        var names = [String]()
        let table: [(CGDisplayChangeSummaryFlags, String)] = [
            (.beginConfigurationFlag, "begin"),
            (.movedFlag, "moved"),
            (.setMainFlag, "setMain"),
            (.setModeFlag, "setMode"),
            (.addFlag, "added"),
            (.removeFlag, "removed"),
            (.enabledFlag, "enabled"),
            (.disabledFlag, "disabled"),
            (.mirrorFlag, "mirror"),
            (.unMirrorFlag, "unmirror"),
            (.desktopShapeChangedFlag, "desktopShapeChanged")
        ]
        for (flag, name) in table where flags.contains(flag) {
            names.append(name)
        }
        return names.isEmpty ? "none" : names.joined(separator: "|")
    }
}

private func iTermMetalDiagnosticsDisplayReconfigurationCallback(display: CGDirectDisplayID,
                                                                 flags: CGDisplayChangeSummaryFlags,
                                                                 userInfo: UnsafeMutableRawPointer?) {
    iTermMetalDiagnostics.sharedInstance().recordDisplayReconfiguration(display: display, flags: flags)
}
