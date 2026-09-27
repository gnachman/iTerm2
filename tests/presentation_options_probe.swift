// Standalone probe for issue 12993: cmd-tab out of a non-native fullscreen
// window flashes the other app and bounces back.
//
// The theory under test is that macOS transiently adds bits to
// NSApp.presentationOptions that the app never set (notably
// DisableProcessSwitching, which disables cmd-tab but not mouse switching),
// and that iTermPresentationController's read-modify-write latches them.
//
// This app mimics iTerm2's non-native fullscreen: a borderless window covering
// the whole screen, with auto-hide dock + auto-hide menu bar set while active
// and cleared while inactive. It samples NSApp.presentationOptions 20x/sec and
// logs every change, so you can see whether a bit nobody asked for shows up.
//
// By default it only ever WRITES bits it owns, so it cannot latch anything and
// cannot break your cmd-tab. Pass --latch to make it do the read-modify-write
// exactly the way iTermPresentationController does, which is what should
// actually reproduce the bug.
//
// Build and run:
//   swiftc -O tests/presentation_options_probe.swift -o /tmp/poprobe && /tmp/poprobe
//   swiftc -O tests/presentation_options_probe.swift -o /tmp/poprobe && /tmp/poprobe --latch
//
// Then cmd-tab away and back a dozen times. Escape or cmd-Q quits. A transcript
// is written to $PROBE_LOG (default /tmp/presentation_options_probe.log).
//
// If cmd-tab stops working in --latch mode, click another app with the mouse:
// presentation options only apply while this app is active, so switching away
// by any means releases them, and quitting clears them for good.

import Cocoa

let allOptions: [(NSApplication.PresentationOptions, String)] = [
    (.autoHideDock, "AutoHideDock"),
    (.hideDock, "HideDock"),
    (.autoHideMenuBar, "AutoHideMenuBar"),
    (.hideMenuBar, "HideMenuBar"),
    (.disableAppleMenu, "DisableAppleMenu"),
    (.disableProcessSwitching, "DisableProcessSwitching"),
    (.disableForceQuit, "DisableForceQuit"),
    (.disableSessionTermination, "DisableSessionTermination"),
    (.disableHideApplication, "DisableHideApplication"),
    (.disableMenuBarTransparency, "DisableMenuBarTransparency"),
    (.fullScreen, "FullScreen"),
    (.autoHideToolbar, "AutoHideToolbar"),
    (.disableCursorLocationAssistance, "DisableCursorLocationAssistance"),
]

func describe(_ options: NSApplication.PresentationOptions) -> String {
    if options.isEmpty {
        return "(none)"
    }
    let names = allOptions.filter { options.contains($0.0) }.map { $0.1 }
    return "\(names.joined(separator: "|")) [0x\(String(options.rawValue, radix: 16))]"
}

// The two bits this probe (like iTerm2) actually manages.
let managed: NSApplication.PresentationOptions = [.autoHideMenuBar, .autoHideDock]

// Bits that are only legal when the dock is hidden. Setting them otherwise
// raises, so we skip the write and say so rather than crashing.
let requiresHiddenDock: NSApplication.PresentationOptions =
    [.disableForceQuit, .disableMenuBarTransparency, .disableProcessSwitching, .disableSessionTermination]
let dockHidden: NSApplication.PresentationOptions = [.autoHideDock, .hideDock]

final class Probe: NSObject, NSApplicationDelegate {
    private let latch = CommandLine.arguments.contains("--latch")
    private let logURL = URL(fileURLWithPath:
        ProcessInfo.processInfo.environment["PROBE_LOG"] ?? "/tmp/presentation_options_probe.log")
    private var window: NSWindow!
    private var textView: NSTextView!
    private var lastSeen: NSApplication.PresentationOptions?
    private var lastSystem: NSApplication.PresentationOptions?
    private var sawUnrequestedBit = false
    private let start = Date()

    func applicationDidFinishLaunching(_ note: Notification) {
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        buildMenu()
        buildWindow()

        log("probe started, mode=\(latch ? "LATCH (mimics iTerm2 read-modify-write)" : "SAFE (writes only owned bits)")")
        log("cmd-tab away and back repeatedly. escape or cmd-Q quits.")

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activationChanged(active: true)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activationChanged(active: false)
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }

        // 20 Hz is fast enough to catch a bit that only exists for the length of
        // an animation, and cheap enough not to perturb what we are measuring.
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        activationChanged(active: true)
    }

    private func activationChanged(active: Bool) {
        // The read-back BEFORE we write is the value iTerm2 feeds into its
        // `& ~mask`, so it is the interesting one.
        let before = NSApp.presentationOptions
        log("app \(active ? "became active" : "resigned active"); presentationOptions before write: \(describe(before))")
        setOptions(hide: active)
    }

    private func setOptions(hide: Bool) {
        var desired: NSApplication.PresentationOptions
        if latch {
            // Exactly what -[iTermPresentationController
            // setApplicationPresentationFlagsWithHiddenDock:menuBar:...] does:
            // keep every bit outside the two-bit mask, whatever it is.
            desired = NSApp.presentationOptions.subtracting(managed)
        } else {
            desired = []
        }
        if hide {
            desired.formUnion(managed)
        }
        if NSApp.presentationOptions == desired {
            return
        }
        if !desired.isDisjoint(with: requiresHiddenDock) && desired.isDisjoint(with: dockHidden) {
            log("SKIP write of \(describe(desired)): illegal without a hidden dock, AppKit would raise")
            return
        }
        log("write presentationOptions \(describe(NSApp.presentationOptions)) -> \(describe(desired))")
        NSApp.presentationOptions = desired
    }

    private func sample() {
        let now = NSApp.presentationOptions
        if now != lastSeen {
            lastSeen = now
            let unrequested = now.subtracting(managed).subtracting([.fullScreen, .autoHideToolbar])
            var line = "presentationOptions is now \(describe(now))"
            if !unrequested.isEmpty {
                sawUnrequestedBit = true
                line += "   <<< UNREQUESTED: \(describe(unrequested))"
            }
            if now.contains(.disableProcessSwitching) {
                line += "   <<< CMD-TAB IS DISABLED RIGHT NOW"
            }
            log(line)
        }
        let system = NSApp.currentSystemPresentationOptions
        if system != lastSystem {
            lastSystem = system
            log("currentSystemPresentationOptions is now \(describe(system))")
        }
    }

    func applicationWillTerminate(_ note: Notification) {
        NSApp.presentationOptions = []
        log(sawUnrequestedBit
            ? "RESULT: saw at least one presentation option this app never set."
            : "RESULT: never saw a presentation option this app did not set.")
        log("transcript: \(logURL.path)")
    }

    private func log(_ message: String) {
        let line = String(format: "%7.3f  %@", Date().timeIntervalSince(start), message)
        print(line)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            try? handle.close()
        }
        guard let textView else {
            return
        }
        textView.textStorage?.append(NSAttributedString(
            string: line + "\n",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                         .foregroundColor: NSColor.white]))
        textView.scrollToEndOfDocument(nil)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // A second menu makes the revealed menu bar easier to see.
        let dummy = NSMenuItem()
        dummy.submenu = NSMenu(title: "Probe")
        main.addItem(dummy)
        NSApp.mainMenu = main
    }

    private func buildWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false,
                          screen: screen)
        window.setFrame(screen.frame, display: true)
        window.backgroundColor = .black
        window.isOpaque = true

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: screen.frame.size))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]
        textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.drawsBackground = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 40, height: 60)
        scroll.documentView = textView
        window.contentView = scroll
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let probe = Probe()
app.delegate = probe
app.run()
