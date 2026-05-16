//
//  DiffWaitingPromptView.swift
//  iTerm2SharedARC
//
//  In-session overlay shown on a .diff-mode workgroup peer while the
//  workgroup's git poller has not yet reported a diffable change. The
//  overlay explains the deferred-launch behavior in user-facing terms
//  (staged / unstaged changes, not internal poller machinery) and
//  exposes a button that fires the deferred launch immediately,
//  bypassing the wait. A second optional Cancel button is shown when
//  the deferral was initiated by a reload (so the user can back out
//  without clobbering the previously-running program). Parallels
//  CodeReviewPromptView in lifecycle and frame-tracking semantics so
//  SessionView can host either kind of pre-launch panel with the same
//  hooks.
//

import AppKit

@objc(iTermDiffWaitingPromptView)
class DiffWaitingPromptView: iTermLayerBackedSolidColorView {
    @objc var onRunAnyway: (() -> Void)?
    // When non-nil, a Cancel button is shown alongside Run Anyway and
    // routes to this closure (which is expected to clear the pending
    // launch and dismiss the overlay). Used by the queued-reload
    // variant so an accidental Reload click can be undone without
    // killing whatever was previously running.
    var onCancel: (() -> Void)?

    // Mirror of CodeReviewPromptView.frameProvider: returns the desired
    // frame in superview coordinates, re-invoked on superview resize
    // and right-gutter reservation changes so the overlay tracks the
    // scrollview area as the session resizes.
    var frameProvider: (() -> NSRect)? {
        didSet { updateFrameFromProvider() }
    }

    // Exposed for parity with CodeReviewPromptView.promptResponder. The
    // run-anyway button is the focusable element so a peer activation
    // that routes focus here ends up on a useful target rather than
    // the title label.
    @objc var promptResponder: NSView { runAnywayButton }

    private let titleLabel: NSTextField
    private let bodyLabel: NSTextField
    private let runAnywayButton: NSButton
    private let cancelButton: NSButton

    private let outerInset: CGFloat = 16
    private let innerSpacing: CGFloat = 8
    private let buttonSpacing: CGFloat = 12
    private let buttonHeight: CGFloat = 28
    private let titleHeight: CGFloat = 18

    // Block-based KVO token. Same lifetime concern as CodeReviewPromptView:
    // ARC zeros the weak SessionView ref before -[NSView dealloc]
    // propagates removeFromSuperview to subviews, so manual add/remove
    // against a weak SessionView would trip the observer-still-registered
    // trap at tear-down.
    private var panelReservationObservation: NSKeyValueObservation?

    @objc(initWithFrame:title:body:showCancel:)
    init(frame frameRect: NSRect,
         title: String,
         body: String,
         showCancel: Bool) {
        titleLabel = NSTextField(labelWithString: title)
        bodyLabel = NSTextField(wrappingLabelWithString: body)
        runAnywayButton = NSButton(frame: .zero)
        cancelButton = NSButton(frame: .zero)

        super.init(frame: frameRect)

        color = NSColor.windowBackgroundColor
        autoresizesSubviews = false

        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.autoresizingMask = [.width, .minYMargin]
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.usesSingleLineMode = false
        addSubview(bodyLabel)

        runAnywayButton.title = "Run Anyway"
        runAnywayButton.bezelStyle = .rounded
        runAnywayButton.target = self
        runAnywayButton.action = #selector(runAnywayClicked(_:))
        runAnywayButton.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(runAnywayButton)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked(_:))
        cancelButton.autoresizingMask = [.minXMargin, .maxYMargin]
        cancelButton.isHidden = !showCancel
        addSubview(cancelButton)

        autoresizingMask = [.width, .height]
    }

    // NSView's init(frame:) is unused. Both presentation entry points
    // (initial-spawn and queued-reload) instantiate via the designated
    // init above and pass explicit title/body/showCancel. The override
    // exists only to satisfy NSView subclass requirements; routing
    // through it would skip property initialization, so callers that
    // somehow reach it should crash loudly rather than get a half-built
    // view. Keeping the user-facing copy in one place (the SessionView
    // factory methods) prevents the two-copies-out-of-sync hazard
    // that motivated this consolidation.
    @objc override init(frame frameRect: NSRect) {
        it_fatalError("init(frame:) is not supported; use init(frame:title:body:showCancel:)")
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    required init(frame frameRect: NSRect, color: NSColor) {
        it_fatalError("init(frame:color:) is not supported; use init(frame:title:body:showCancel:)")
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let runWidth = max(100, runAnywayButton.fittingSize.width)
        let cancelWidth = max(80, cancelButton.fittingSize.width)

        let titleY = bounds.maxY - outerInset - titleHeight
        titleLabel.frame = NSRect(x: outerInset,
                                  y: titleY,
                                  width: bounds.width - 2 * outerInset,
                                  height: titleHeight)

        let buttonY = outerInset
        let runX = bounds.maxX - outerInset - runWidth
        runAnywayButton.frame = NSRect(x: runX,
                                       y: buttonY,
                                       width: runWidth,
                                       height: buttonHeight)
        if !cancelButton.isHidden {
            cancelButton.frame = NSRect(
                x: runX - buttonSpacing - cancelWidth,
                y: buttonY,
                width: cancelWidth,
                height: buttonHeight)
        }

        // Body fills the space between title and button. Cap the
        // width so wrapping respects the inset rather than running
        // edge to edge.
        let bodyMaxY = titleY - innerSpacing
        let bodyMinY = buttonY + buttonHeight + innerSpacing
        let bodyWidth = bounds.width - 2 * outerInset
        bodyLabel.preferredMaxLayoutWidth = bodyWidth
        let bodyFit = bodyLabel.sizeThatFits(NSSize(width: bodyWidth,
                                                    height: .greatestFiniteMagnitude))
        let availableHeight = max(0, bodyMaxY - bodyMinY)
        let bodyHeight = min(bodyFit.height, availableHeight)
        bodyLabel.frame = NSRect(x: outerInset,
                                 y: bodyMaxY - bodyHeight,
                                 width: bodyWidth,
                                 height: bodyHeight)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            window?.makeFirstResponder(runAnywayButton)
        }
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if let oldSuperview = superview {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: oldSuperview)
        }
        panelReservationObservation = nil
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let newSuperview = superview {
            newSuperview.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(superviewFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: newSuperview)
            if let sessionView = newSuperview as? SessionView {
                panelReservationObservation = sessionView.observe(
                    \.actualPanelReservation,
                    options: [.new]
                ) { [weak self] _, _ in
                    self?.updateFrameFromProvider()
                }
            }
            updateFrameFromProvider()
        }
    }

    @objc private func superviewFrameDidChange(_ notification: Notification) {
        updateFrameFromProvider()
    }

    private func updateFrameFromProvider() {
        guard let provider = frameProvider, superview != nil else { return }
        let target = provider()
        if frame != target {
            frame = target
        }
    }

    // Re-evaluate the frame against the current frameProvider. Called
    // from SessionView.updateLayout so the overlay re-syncs after the
    // toolbar or title strip is added/removed/resized. Those don't
    // change the SessionView's own frame, so the frameDidChange
    // observer doesn't fire for them.
    @objc func sessionViewLayoutDidChange() {
        updateFrameFromProvider()
    }

    @objc private func runAnywayClicked(_ sender: Any) {
        onRunAnyway?()
    }

    @objc private func cancelClicked(_ sender: Any) {
        onCancel?()
    }
}
