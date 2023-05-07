//
//  AppDelegate.swift
//  iTerm2ImportStatus
//
//  Created by George Nachman on 5/6/23.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func readFromStdin(callback: @escaping (String) -> Void) {
        let queue = DispatchQueue(label: "com.googlecode.iterm2.stdinReader", qos: .userInitiated)
        queue.async {
            while let line = readLine() {
                DispatchQueue.main.async {
                    callback(line)
                }
            }
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let importingWindowController = ImportingWindowController(windowNibName: "ImportingWindowController")
        NSApp.activate(ignoringOtherApps: true)
        importingWindowController.window?.makeKeyAndOrderFront(nil)
        importingWindowController.setStatus("Starting")
        importingWindowController.window?.center()

        readFromStdin { input in
            importingWindowController.setStatus(input.trimmingCharacters(in: .newlines))
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            importingWindowController.window?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}

