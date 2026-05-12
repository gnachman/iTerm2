//
//  MomentermGitGraphIndicator.swift
//  iTerm2
//
//  Small "Git Graph" pill anchored at the bottom-right of the terminal
//  window. Always visible; clicking it opens the standalone graph window
//  with the active session's cwd. Mirrors VS Code's status-bar entry but
//  rendered as a floating overlay because the terminal window has no
//  always-present status bar.
//
//  CLAUDE.md forbids auto layout inside the terminal window, so the
//  indicator pins itself with frame + autoresizingMask only.
//

import AppKit

@objc(MomentermGitGraphIndicatorDelegate)
protocol MomentermGitGraphIndicatorDelegate: AnyObject {
    /// Returns the cwd the indicator should hand off to the graph window
    /// when the user clicks it. Returning nil falls back to NSHomeDirectory.
    func momentermGitGraphIndicatorCurrentCwd() -> String?
}

@objc(MomentermGitGraphIndicator)
final class MomentermGitGraphIndicator: NSView {

    @objc weak var delegate: MomentermGitGraphIndicatorDelegate?

    private let button = NSButton()
    private let icon = NSImageView()

    @objc override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.4).cgColor

        icon.image = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                             accessibilityDescription: "Git Graph")
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)

        button.title = "Git Graph"
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.alignment = .left
        button.target = self
        button.action = #selector(clicked)
        button.toolTip = "Open Git Graph"
        addSubview(button)

        layoutContents()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not supported")
    }

    override func layout() {
        super.layout()
        layoutContents()
    }

    private func layoutContents() {
        let h = bounds.height
        let iconSize: CGFloat = 13
        icon.frame = NSRect(x: 6, y: (h - iconSize) / 2.0, width: iconSize, height: iconSize)
        button.frame = NSRect(x: 6 + iconSize + 4, y: 0, width: bounds.width - 26, height: h)
    }

    @objc private func clicked() {
        let cwd = delegate?.momentermGitGraphIndicatorCurrentCwd() ?? NSHomeDirectory()
        MomentermGitGraphWindowController.shared.toggleForCwd(cwd)
    }

    // Mouse enter / exit hover styling
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        button.contentTintColor = .controlAccentColor
        icon.contentTintColor = .controlAccentColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        button.contentTintColor = .secondaryLabelColor
        icon.contentTintColor = .secondaryLabelColor
    }
}
