// Measures what the two menu-bar-hiding APIs actually do on this macOS, so we
// can decide whether hiding the menu bar has to cost us the dock.
//
// Experiment 1: +[NSMenu setMenuBarVisible:NO], the API iTerm2 used before
//   commit 4b6066281 (2011) coupled the menu bar to the dock. Does it still hide
//   the menu bar? Does it leave the dock alone? Is it implemented in terms of
//   presentation options under the hood?
//
// Experiment 2: NSApplicationPresentationAutoHideMenuBar with no dock bit. Old
//   AppKit headers said this needs AutoHideDock or HideDock alongside it. Is it
//   ignored, honored, or does it raise?
//
// Everything is measured from NSScreen insets, so no eyeballing is needed:
// visibleFrame shrinks at the top for the menu bar and at the bottom for the
// dock. Takes about six seconds and restores everything before it exits.
//
//   swiftc -O tests/menu_bar_api_probe.swift -o /tmp/mbprobe && /tmp/mbprobe

import Cocoa

func describe(_ o: NSApplication.PresentationOptions) -> String {
    let names: [(NSApplication.PresentationOptions, String)] = [
        (.autoHideDock, "AutoHideDock"), (.hideDock, "HideDock"),
        (.autoHideMenuBar, "AutoHideMenuBar"), (.hideMenuBar, "HideMenuBar"),
        (.fullScreen, "FullScreen"), (.autoHideToolbar, "AutoHideToolbar"),
        (.disableProcessSwitching, "DisableProcessSwitching"),
    ]
    let hit = names.filter { o.contains($0.0) }.map { $0.1 }
    return hit.isEmpty ? "(none)" : hit.joined(separator: "|")
}

struct Insets { let top: CGFloat; let bottom: CGFloat }

func insets() -> [String: Insets] {
    var result = [String: Insets]()
    for (i, s) in NSScreen.screens.enumerated() {
        let key = "screen\(i) \(Int(s.frame.width))x\(Int(s.frame.height))"
        result[key] = Insets(top: s.frame.maxY - s.visibleFrame.maxY,
                             bottom: s.visibleFrame.minY - s.frame.minY)
    }
    return result
}

func report(_ label: String, _ baseline: [String: Insets]) {
    let now = insets()
    print("\n--- \(label) ---")
    print("    presentationOptions: \(describe(NSApp.presentationOptions))")
    print("    menuBarVisible: \(NSMenu.menuBarVisible())")
    for key in now.keys.sorted() {
        guard let a = baseline[key], let b = now[key] else { continue }
        let dTop = b.top - a.top
        let dBottom = b.bottom - a.bottom
        let note = (dTop == 0 && dBottom == 0) ? "no change"
            : "top \(a.top)->\(b.top) (\(dTop >= 0 ? "+" : "")\(dTop)), bottom \(a.bottom)->\(b.bottom) (\(dBottom >= 0 ? "+" : "")\(dBottom))"
        print("    \(key): \(note)")
    }
}

final class Probe: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var baseline = [String: Insets]()

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "menu bar API probe"
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Give activation a moment to land; presentation options and the menu bar
        // only respond to the active app.
        step(after: 1.0) {
            self.baseline = insets()
            print("baseline:")
            for k in self.baseline.keys.sorted() {
                print("    \(k): top=\(self.baseline[k]!.top) bottom=\(self.baseline[k]!.bottom)")
            }
            print("    presentationOptions: \(describe(NSApp.presentationOptions))")
            print("    active: \(NSApp.isActive)")

            print("\n=== EXPERIMENT 1: +[NSMenu setMenuBarVisible:NO] ===")
            NSMenu.setMenuBarVisible(false)
            self.step(after: 1.5) {
                report("after setMenuBarVisible(false)", self.baseline)
                NSMenu.setMenuBarVisible(true)

                self.step(after: 1.0) {
                    report("after setMenuBarVisible(true) [restored]", self.baseline)

                    print("\n=== EXPERIMENT 2: AutoHideMenuBar with no dock bit ===")
                    print("    (if this raises, the combination is illegal rather than ignored)")
                    NSApp.presentationOptions = [.autoHideMenuBar]
                    self.step(after: 1.5) {
                        report("after presentationOptions = [.autoHideMenuBar]", self.baseline)

                        print("\n=== CONTROL: AutoHideMenuBar + AutoHideDock ===")
                        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]
                        self.step(after: 1.5) {
                            report("after presentationOptions = [.autoHideMenuBar, .autoHideDock]", self.baseline)
                            NSApp.presentationOptions = []
                            self.step(after: 0.5) {
                                report("after presentationOptions = [] [restored]", self.baseline)
                                print("\ndone")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func step(after delay: TimeInterval, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let probe = Probe()
app.delegate = probe
app.run()
