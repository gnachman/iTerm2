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
    private let newChatButton: NSButton
    private let switchChatButton: NSButton
    private let sessionInfoButton: NSButton
    private let closeButton: NSButton
    private let separator: NSBox

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
        sessionInfoButton = Self.makeButton(symbol: .infoCircle,
                                            tooltip: "Link or unlink terminal/browser session")
        closeButton = Self.makeButton(symbol: .xmark,
                                      tooltip: "Hide chat")

        separator = NSBox()
        separator.boxType = .separator

        super.init(frame: frameRect)

        for view in [newChatButton, switchChatButton, titleLabel,
                     sessionInfoButton, closeButton, separator] {
            view.autoresizingMask = []
            addSubview(view)
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
        let buttonY = floor((bounds.height - Self.buttonWidth) / 2)

        // Left group: new chat, switch chat.
        var x = Self.horizontalPadding
        newChatButton.frame = NSRect(x: x, y: buttonY,
                                     width: Self.buttonWidth, height: Self.buttonWidth)
        x += Self.buttonWidth + Self.spacing
        switchChatButton.frame = NSRect(x: x, y: buttonY,
                                        width: Self.buttonWidth, height: Self.buttonWidth)
        let leftEdge = x + Self.buttonWidth

        // Right group: session info, close (close is rightmost).
        var rx = bounds.width - Self.horizontalPadding - Self.buttonWidth
        closeButton.frame = NSRect(x: rx, y: buttonY,
                                   width: Self.buttonWidth, height: Self.buttonWidth)
        rx -= Self.spacing + Self.buttonWidth
        sessionInfoButton.frame = NSRect(x: rx, y: buttonY,
                                         width: Self.buttonWidth, height: Self.buttonWidth)
        let rightEdge = rx

        // Title fills the gap between the two groups.
        let titleX = leftEdge + Self.spacing
        let titleWidth = max(0, rightEdge - Self.spacing - titleX)
        let titleHeight = titleLabel.intrinsicContentSize.height
        let titleY = floor((bounds.height - titleHeight) / 2)
        titleLabel.frame = NSRect(x: titleX, y: titleY,
                                  width: titleWidth, height: titleHeight)

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
