//
//  PeerSessionSettingsViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/23/26.
//

import AppKit

// Generic settings panel for one peer kind in a peer group (e.g. Diff or Code
// Review within the Claude Code group). For now, the only setting is a command
// to run; the view controller is shaped so we can add more controls later
// (e.g. a type picker for terminal vs. browser-backed peers, browser URL, env
// vars) without breaking callers.
@objc(iTermPeerSessionSettingsViewController)
class PeerSessionSettingsViewController: NSViewController {
    @objc let peerDisplayName: String
    @objc private(set) var command: String
    @objc var onCommandChange: ((String) -> Void)?

    private var commandField: NSTextField!

    @objc
    init(peerDisplayName: String,
         command: String) {
        self.peerDisplayName = peerDisplayName
        self.command = command
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let width: CGFloat = 460
        let margin: CGFloat = 14
        let verticalSpacing: CGFloat = 6

        let titleLabel = NSTextField(labelWithString: peerDisplayName)
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.sizeToFit()

        let helpLabel = NSTextField(wrappingLabelWithString:
            "Command to run in this pane. Changes take effect the next time the pane is restarted.")
        helpLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.preferredMaxLayoutWidth = width - 2 * margin
        helpLabel.frame.size = helpLabel.fittingSize

        let commandHeaderLabel = NSTextField(labelWithString: "Command:")
        commandHeaderLabel.sizeToFit()

        let field = NSTextField(string: command)
        field.isEditable = true
        field.isSelectable = true
        field.font = .userFixedPitchFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        field.frame.size = NSSize(width: width - 2 * margin, height: 22)
        commandField = field

        // Stack vertically from the top.
        var y: CGFloat = margin
        let fieldHeight = field.frame.height
        let totalHeight = margin
            + titleLabel.frame.height
            + verticalSpacing
            + helpLabel.frame.height
            + verticalSpacing * 2
            + commandHeaderLabel.frame.height
            + verticalSpacing
            + fieldHeight
            + margin

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: totalHeight))

        // Build from the bottom up.
        field.frame.origin = NSPoint(x: margin, y: y)
        field.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(field)
        y += fieldHeight + verticalSpacing

        commandHeaderLabel.frame.origin = NSPoint(x: margin, y: y)
        commandHeaderLabel.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(commandHeaderLabel)
        y += commandHeaderLabel.frame.height + verticalSpacing * 2

        helpLabel.frame.origin = NSPoint(x: margin, y: y)
        helpLabel.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(helpLabel)
        y += helpLabel.frame.height + verticalSpacing

        titleLabel.frame.origin = NSPoint(x: margin, y: y)
        titleLabel.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(titleLabel)

        view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(commandField)
    }
}

extension PeerSessionSettingsViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        command = commandField.stringValue
        onCommandChange?(command)
    }
}
