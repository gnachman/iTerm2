//
//  CompanionToast.swift
//  iTerm2
//
//  A small, self-dismissing toast shown in the center of the main screen to
//  confirm a companion device connecting or disconnecting. This is a custom
//  in-app panel, not a macOS user notification (those deliver unreliably and
//  are easily missed). Layout uses explicit frames (no auto layout).
//

import AppKit

@MainActor
final class CompanionToast {
    // Hold the toast that is currently on screen so a rapid second event
    // replaces it instead of stacking.
    private static var current: CompanionToast?

    private let panel: NSPanel
    private var dismissWorkItem: DispatchWorkItem?

    /// Show a toast centered on the main screen. Replaces any visible toast.
    static func show(message: String, symbolName: String, tint: NSColor) {
        current?.removeNow()
        let toast = CompanionToast(message: message, symbolName: symbolName, tint: tint)
        current = toast
        toast.present()
    }

    private init(message: String, symbolName: String, tint: NSColor) {
        let height: CGFloat = 88
        let sideMargin: CGFloat = 20
        let iconSize: CGFloat = 40
        let iconLabelGap: CGFloat = 14
        let labelX = sideMargin + iconSize + iconLabelGap

        // Measure the label so the panel hugs the text: the right margin (from the
        // label's trailing edge to the panel edge) equals the left margin (sideMargin).
        let labelFont = NSFont.systemFont(ofSize: 15, weight: .medium)
        // Measure the glyph run and add a small buffer for the text field's internal
        // cell padding, otherwise the label truncates by a few points.
        let textWidth = (message as NSString).size(withAttributes: [.font: labelFont]).width
        let labelWidth = ceil(textWidth) + 4
        let width = labelX + labelWidth + sideMargin

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.alphaValue = 0

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        panel.contentView = background

        let iconView = NSImageView(frame: NSRect(x: sideMargin, y: (height - iconSize) / 2,
                                                 width: iconSize, height: iconSize))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: message)?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        iconView.image = image
        iconView.contentTintColor = tint
        background.addSubview(iconView)

        let label = NSTextField(labelWithString: message)
        label.font = labelFont
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: labelX, y: (height - 20) / 2, width: labelWidth, height: 20)
        background.addSubview(label)
    }

    private func present() {
        if let screen = NSScreen.main {
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        // Runs on the main queue, so assumeIsolated is safe.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // The completion handler is delivered on the main thread.
            MainActor.assumeIsolated { self?.removeNow() }
        })
    }

    private func removeNow() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel.orderOut(nil)
        if CompanionToast.current === self {
            CompanionToast.current = nil
        }
    }
}
