//
//  InlineChatToolbarView.swift
//  iTerm2SharedARC
//
//  Toolbar shown at the top of the inline (right-gutter) chat panel. The chat
//  window has its own NSToolbar / floating bar; the inline panel had none, so
//  this provides the panel-only controls: create a new chat, switch to another
//  chat, open the session/link menu, and hide the panel. Manual layout (no
//  auto layout) to match the rest of ChatViewController's view tree.
//

import Foundation

protocol InlineChatToolbarViewDelegate: AnyObject {
    func inlineChatToolbarDidTapNewChat()
    func inlineChatToolbarDidTapSwitchChat(_ sender: NSButton)
    func inlineChatToolbarDidTapSessionInfo(_ sender: NSButton)
    func inlineChatToolbarDidTapClose()
}

// An NSTextField installs an I-beam cursor rect on hover even when it is a
// non-editable, non-selectable label. The toolbar's title is purely decorative,
// so force the arrow cursor over it.
private final class InlineChatToolbarTitleLabel: NSTextField {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

final class InlineChatToolbarView: NSView {
    static let height: CGFloat = 28

    private static let buttonWidth: CGFloat = 24
    private static let horizontalPadding: CGFloat = 8
    private static let spacing: CGFloat = 6

    weak var delegate: InlineChatToolbarViewDelegate?

    let titleLabel: NSTextField
    private let backdrop: NSVisualEffectView
    private let newChatButton: NSButton
    private let switchChatButton: NSButton
    private let sessionInfoButton: NSButton
    private let closeButton: NSButton
    private let separator: NSBox
    // Horizontal row [newChat, switchChat, <flexible title>, sessionInfo,
    // close]. ChatManualStackView (the same no-auto-layout row used by the
    // chat window's floating toolbar) handles the left/center/right math.
    private let row = ChatManualStackView(orientation: .horizontal,
                                          spacing: InlineChatToolbarView.spacing,
                                          alignment: .center)

    override init(frame frameRect: NSRect) {
        let label = InlineChatToolbarTitleLabel(labelWithString: "AI Chat")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        titleLabel = label

        newChatButton = Self.makeButton(symbol: .squareAndPencil,
                                        tooltip: "New chat")
        switchChatButton = Self.makeButton(symbol: .bubbleLeftAndBubbleRight,
                                           tooltip: "Switch to another chat")
        // Same info-circle control the chat window toolbar uses.
        sessionInfoButton = ChatToolbar.makeSessionInfoButton()
        sessionInfoButton.imageScaling = .scaleProportionallyDown
        sessionInfoButton.toolTip = "Link or unlink terminal/browser session"
        // makeSessionInfoButton builds the image with a nil accessibility
        // description, so give VoiceOver an explicit label (the tooltip only
        // maps to accessibility help, not the element's label).
        sessionInfoButton.setAccessibilityLabel("Link or unlink terminal/browser session")
        closeButton = Self.makeButton(symbol: .xmark,
                                      tooltip: "Hide chat")

        separator = NSBox()
        separator.boxType = .separator

        // Translucent background so the toolbar reads as a distinct header band
        // rather than floating over the chat content behind it.
        backdrop = NSVisualEffectView()
        backdrop.material = .headerView
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active

        super.init(frame: frameRect)

        addSubview(backdrop)
        addSubview(separator)
        addSubview(row)
        for control in [newChatButton, switchChatButton, titleLabel,
                        sessionInfoButton, closeButton] {
            row.addArrangedSubview(control)
        }
        // The title takes the leftover width between the button groups; its
        // own text is centered (label alignment is .center).
        row.setFlex(titleLabel, true)
        row.sizeOverride = { [weak self] view, _ in
            guard let self else { return nil }
            if view === self.titleLabel {
                // Width 0 (not -1) makes flex clamp the title to exactly its
                // leftover share rather than treating the full intrinsic
                // width as a minimum. Otherwise a long title would overflow
                // the row and push the right-hand buttons off-screen. Height
                // -1 keeps the measured (single-line) height. The label's
                // .byTruncatingTail then truncates within the clamped width.
                return NSSize(width: 0, height: -1)
            }
            return NSSize(width: Self.buttonWidth, height: Self.buttonWidth)
        }

        newChatButton.target = self
        newChatButton.action = #selector(newChatClicked(_:))
        switchChatButton.target = self
        switchChatButton.action = #selector(switchChatClicked(_:))
        sessionInfoButton.target = self
        sessionInfoButton.action = #selector(sessionInfoClicked(_:))
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) not implemented")
    }

    private static func makeButton(symbol: SFSymbol, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.bezelStyle = .badge
        button.toolTip = tooltip
        return button
    }

    override func resetCursorRects() {
        // Claim the arrow over the whole toolbar so the buttons (which set no
        // cursor rect of their own) don't inherit the I-beam from the chat
        // content behind us. The title label installs its own arrow rect.
        addCursorRect(bounds, cursor: .arrow)
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        backdrop.frame = bounds
        // The control row spans the width minus horizontal padding; the
        // ChatManualStackView centers each control vertically within it.
        row.frame = NSRect(x: Self.horizontalPadding,
                           y: 0,
                           width: max(0, bounds.width - Self.horizontalPadding * 2),
                           height: bounds.height)
        // Hairline along the bottom edge separating the toolbar from content.
        separator.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    @objc private func newChatClicked(_ sender: NSButton) {
        delegate?.inlineChatToolbarDidTapNewChat()
    }

    @objc private func switchChatClicked(_ sender: NSButton) {
        delegate?.inlineChatToolbarDidTapSwitchChat(sender)
    }

    @objc private func sessionInfoClicked(_ sender: NSButton) {
        delegate?.inlineChatToolbarDidTapSessionInfo(sender)
    }

    @objc private func closeClicked(_ sender: NSButton) {
        delegate?.inlineChatToolbarDidTapClose()
    }
}
