//
//  WorkgroupNavigationToolbarItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/26.
//

import AppKit

// Three navigation buttons (Back, Forward, Reload) packed into a
// single toolbar item so they read as a cluster rather than three
// loose controls separated by toolbar dividers.
//
// `ownerPeerID` identifies the peer/host config the button fired
// for; the delegate uses it to demultiplex which session needs the
// action. This protocol is shared with the smaller WorkgroupReload-
// ToolbarItem (reload-only variant) so the workgroup runtime needs
// only one delegate surface.
protocol WorkgroupNavigationToolbarItemDelegate: AnyObject {
    func workgroupNavigationDidTapBack(ownerPeerID: String?)
    func workgroupNavigationDidTapForward(ownerPeerID: String?)
    func workgroupNavigationDidTapReload(ownerPeerID: String?)
}

final class WorkgroupNavigationToolbarItem: SessionToolbarGenericView {
    weak var navigationDelegate: WorkgroupNavigationToolbarItemDelegate?
    // Tagged with the owning peer/host config UUID so the delegate
    // can demultiplex which session's button fired.
    var ownerPeerID: String?

    private let backButton: NSButton
    private let forwardButton: NSButton
    private let reloadButton: NSButton
    // Sits between back and forward, showing "X/Y" position in the
    // diff selector's file list. Hidden when no file is picked
    // (popup is on "All Files" / "Empty Diff" / has no items).
    private let progressLabel: NSTextField
    private static let interButtonSpacing = 8.0

    init(identifier: String, priority: Int) {
        backButton = Self.makeButton(symbol: .chevronLeft)
        forwardButton = Self.makeButton(symbol: .chevronRight)
        reloadButton = Self.makeButton(symbol: .arrowClockwise)
        progressLabel = Self.makeProgressLabel()

        // Plain NSView container, no auto layout — terminal-window
        // toolbars are explicitly autoresizing-mask territory per the
        // project rule. Children are positioned in layoutSubviews.
        let container = NSView(frame: .zero)
        container.addSubview(backButton)
        container.addSubview(progressLabel)
        container.addSubview(forwardButton)
        container.addSubview(reloadButton)

        super.init(identifier: identifier, priority: priority, view: container)
        backButton.target = self
        backButton.action = #selector(didTapBack(_:))
        forwardButton.target = self
        forwardButton.action = #selector(didTapForward(_:))
        reloadButton.target = self
        reloadButton.action = #selector(didTapReload(_:))
        // Default disabled — the diff selector hasn't reported file
        // statuses yet, so there's nothing to step through. The peer
        // port re-enables them once the selector has files and a
        // non-"All Files" row is showing.
        backButton.isEnabled = false
        forwardButton.isEnabled = false
        progressLabel.isHidden = true
    }

    // Set by the peer port (and workgroup instance) in response to
    // diff-selector state changes — file list reloaded by the git
    // poller, popup selection changed, or a button-driven advance.
    // `progress` is "X/Y" when a file is picked, nil otherwise; the
    // label hides in the nil case so the cluster collapses to just
    // back / forward / reload.
    func setNavigationState(canBack: Bool,
                            canForward: Bool,
                            progress: String?) {
        backButton.isEnabled = canBack
        forwardButton.isEnabled = canForward
        let wasHidden = progressLabel.isHidden
        let oldText = progressLabel.stringValue
        if let progress {
            progressLabel.stringValue = progress
            progressLabel.isHidden = false
            progressLabel.sizeToFit()
        } else {
            progressLabel.isHidden = true
        }
        let visibilityChanged = wasHidden != progressLabel.isHidden
        let textChanged = !progressLabel.isHidden && oldText != progressLabel.stringValue
        if visibilityChanged || textChanged {
            // Cluster width depends on whether the label is shown
            // and how wide its text is — kick the toolbar to relayout
            // so the new desiredWidthRange is honored.
            delegate?.itemDidChange(sender: self)
        }
    }

    private var laidOutSubviews: [NSView] {
        var result: [NSView] = [backButton]
        if !progressLabel.isHidden {
            result.append(progressLabel)
        }
        result.append(forwardButton)
        result.append(reloadButton)
        return result
    }

    private var naturalWidth: CGFloat {
        var width = 0.0
        let subs = laidOutSubviews
        for (i, v) in subs.enumerated() {
            width += v.fittingSize.width
            if i < subs.count - 1 {
                width += Self.interButtonSpacing
            }
        }
        return width
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        let w = naturalWidth
        return w...w
    }

    override func layoutSubviews() {
        // Skip super — its sizing assumes _view has a useful
        // fittingSize, but a plain container reports zero. Lay
        // _view (the container) and its children out by frame.
        let height = view.bounds.height
        _view.frame = NSRect(x: 0,
                             y: 0,
                             width: view.bounds.width,
                             height: height)
        var x = 0.0
        for v in laidOutSubviews {
            let size = v.fittingSize
            v.frame = NSRect(x: x,
                             y: (height - size.height) / 2.0,
                             width: size.width,
                             height: size.height)
            x += size.width + Self.interButtonSpacing
        }
    }

    fileprivate static func makeButton(symbol: SFSymbol) -> NSButton {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: nil) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private static func makeProgressLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .secondaryLabelColor
        field.alignment = .center
        return field
    }

    @objc private func didTapBack(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapBack(ownerPeerID: ownerPeerID)
    }

    @objc private func didTapForward(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapForward(ownerPeerID: ownerPeerID)
    }

    @objc private func didTapReload(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapReload(ownerPeerID: ownerPeerID)
    }

    static func makeReloadButton() -> NSButton {
        return makeButton(symbol: .arrowClockwise)
    }
}

// Standalone reload button — same delegate as the navigation cluster
// but with only the reload control. Suited for code-review-mode peers
// where back/forward have nothing to step through.
final class WorkgroupReloadToolbarItem: SessionToolbarGenericView {
    weak var navigationDelegate: WorkgroupNavigationToolbarItemDelegate?
    var ownerPeerID: String?

    private let reloadButton: NSButton

    init(identifier: String, priority: Int) {
        reloadButton = WorkgroupNavigationToolbarItem.makeReloadButton()
        let container = NSView(frame: .zero)
        container.addSubview(reloadButton)
        super.init(identifier: identifier, priority: priority, view: container)
        reloadButton.target = self
        reloadButton.action = #selector(didTapReload(_:))
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        let w = reloadButton.fittingSize.width
        return w...w
    }

    override func layoutSubviews() {
        let height = view.bounds.height
        _view.frame = NSRect(x: 0, y: 0, width: view.bounds.width, height: height)
        let buttonSize = reloadButton.fittingSize
        reloadButton.frame = NSRect(x: 0,
                                     y: (height - buttonSize.height) / 2.0,
                                     width: buttonSize.width,
                                     height: buttonSize.height)
    }

    @objc private func didTapReload(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapReload(ownerPeerID: ownerPeerID)
    }
}
