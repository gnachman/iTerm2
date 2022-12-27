//
//  iTermPleaseWaitWindow.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/19/22.
//

import Foundation
import AppKit

@objc(iTermPleaseWaitWindow)
class PleaseWaitWindow: NSWindow {
    private var progressIndicator = NSProgressIndicator()
    private var cancelButton: NSButton!
    private var messageLabel = NSTextField()
    private var imageView: NSImageView!
    private var finished = false
    private weak var owningWindow: NSWindow?
    private(set) var canceled = false

    @objc
    init(owningWindow: NSWindow, message: String, image: NSImage) {
        self.owningWindow = owningWindow
        super.init(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let vev = NSVisualEffectView()
        vev.wantsLayer = true
        vev.blendingMode = .withinWindow
        vev.material = .sheet
        vev.state = .active
        contentView?.addSubview(vev)

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        messageLabel.stringValue = message
        messageLabel.isEditable = false
        messageLabel.isSelectable = false
        messageLabel.isBordered = false
        messageLabel.drawsBackground = false
        messageLabel.sizeToFit()
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.sizeToFit()
        imageView = NSImageView(image: image)
        imageView.image!.isTemplate = true
        imageView.frame = NSRect(origin: .zero, size: imageView.fittingSize)

        if let contentView {
            let views = [cancelButton!, progressIndicator, messageLabel, imageView!]
            for view in views {
                contentView.addSubview(view)
            }

            let sideMargin = 20.0
            let topMargin = 12.0
            let bottomMargin = 16.0
            let innerMargin = 12.0

            let contentViewWidth = views.map { $0.bounds.width }.max()! + sideMargin * 2

            var y = topMargin
            var frames = [NSRect]()
            for view in views {
                let w = view.bounds.width
                let x = (contentViewWidth - w) / 2.0
                let h = view.bounds.height
                frames.append(NSRect(x: x, y: y, width: w, height: h))
                y += h + innerMargin
                view.autoresizingMask = []
            }
            let height = y + bottomMargin
            let windowFrame = NSWindow.frameRect(
                forContentRect: NSRect(x: 0,
                                       y: 0,
                                       width: contentViewWidth,
                                       height: height),
                styleMask: self.styleMask)
            self.setFrame(windowFrame, display: true)
            for (view, frame) in zip(views, frames) {
                view.frame = frame
            }
        }
    }

    @objc func run() {
        guard let owningWindow else {
            return
        }
        progressIndicator.startAnimation(nil)
        owningWindow.beginSheet(self) { [weak self] _ in
            self?.orderOut(nil)
        }

        let session = NSApp.beginModalSession(for: self)
        let runloop = RunLoop.current
        let port = NSMachPort()
        runloop.add(port, forMode: .default)
        while !finished {
            if NSApp.runModalSession(session) != .continue {
                break
            }
            runloop.run(mode: .default, before: .distantFuture)
        }
        NSApp.endModalSession(session)
    }

    @objc func cancel(_ sender: Any?) {
        canceled = true
        stop()
    }

    @objc func stop() {
        if finished {
            return
        }
        finished = true
        sheetParent?.endSheet(self)
    }
}
