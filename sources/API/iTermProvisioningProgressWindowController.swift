//
//  iTermProvisioningProgressWindowController.swift
//  iTerm2SharedARC
//
//  A minimal, self-contained indeterminate progress window shown while uv provisions a
//  full-environment script (create-new and Dependency Editor upgrade). The uv binary
//  download shows its own progress window; this covers the otherwise-silent venv build
//  and pip install that follow. Frame-based layout (no auto layout) on purpose.
//

import AppKit

@objc(iTermProvisioningProgressWindowController)
class iTermProvisioningProgressWindowController: NSObject {
    private var panel: NSPanel?

    // Show the window with a message. Must be called on the main thread. A no-op if a
    // window is already showing.
    @objc func show(message: String) {
        guard panel == nil else {
            return
        }
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 92)
        let panel = NSPanel(contentRect: contentRect,
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.title = "iTerm2"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 30, width: 32, height: 32))
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 64, y: 24, width: 296, height: 44)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.font = NSFont.systemFont(ofSize: 13)

        panel.contentView?.addSubview(spinner)
        panel.contentView?.addSubview(label)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    // Close the window. Must be called on the main thread. Safe to call if not showing.
    @objc func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}
