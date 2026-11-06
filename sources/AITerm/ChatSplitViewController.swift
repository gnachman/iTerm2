//
//  ChatSplitViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

class ChatSplitViewController: NSSplitViewController {
    let chatListViewController: ChatListViewController
    let chatViewController: ChatViewController

    private var sidebarItem: NSSplitViewItem?
    private var contentItem: NSSplitViewItem?
    private var hasSetInitialWidth = false
    // On macOS 26 the window has no NSToolbar, so ChatWindowController puts
    // this button in the chat's floating toolbar. Earlier versions use the
    // toggleChatList NSToolbarItem instead and leave this button unused.
    let sidebarToggleButton: NSButton = {
        let image = NSImage(systemSymbolName: SFSymbol.sidebarLeft.rawValue,
                            accessibilityDescription: String(localized: "ChatWindowController.ToggleChatList", defaultValue: "Toggle Chat List", comment: "Toolbar item to show or hide the chat list"))!
        let button = NSButton(image: image, target: nil, action: nil)
        button.bezelStyle = .badge
        // Setting bezelStyle resets isBordered to true, so clear it after.
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        return button
    }()

    // Narrower than this and the find bar's search field is unreadable. The
    // window can't shrink the chat below it, so at the window's minimum width
    // the sidebar collapses (or, where a window resize can't collapse it, the
    // window stops shrinking) instead.
    static var minimumContentWidth: CGFloat {
        return ChatFindBarView.minimumUsableWidth + ChatViewController.findBarSideMargin * 2
    }

    static func configureContentItem(_ item: NSSplitViewItem) {
        item.minimumThickness = minimumContentWidth
    }

    init(chatListViewController: ChatListViewController, chatViewController: ChatViewController) {
        self.chatListViewController = chatListViewController
        self.chatViewController = chatViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }


    private func setupSplitView() {
        // Configure the split view
        splitView.isVertical = true

        // Set autosave name to persist sidebar width across launches
        splitView.autosaveName = "ChatSplitView"

        // Create sidebar item with sidebar behavior for glass effect
        sidebarItem = NSSplitViewItem(sidebarWithViewController: chatListViewController)
        if let sidebarItem = sidebarItem {
            sidebarItem.minimumThickness = 200
            sidebarItem.maximumThickness = 400
            // Set preferred thickness
            sidebarItem.preferredThicknessFraction = 0.25
            // Lower holding priority to allow user resizing
            sidebarItem.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
            sidebarItem.canCollapse = true
            // Enable automatic maximum thickness to allow resizing
            sidebarItem.automaticMaximumThickness = 400

            addSplitViewItem(sidebarItem)
        }

        // Create content item
        contentItem = NSSplitViewItem(viewController: chatViewController)
        if let contentItem = contentItem {
            Self.configureContentItem(contentItem)
            addSplitViewItem(contentItem)
        }

        // Use thin divider style
        splitView.dividerStyle = .thin

        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleChatList)
        updateSidebarToggleButton()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        // Set initial sidebar width on first appearance
        if !hasSetInitialWidth, let _ = sidebarItem {
            // Force initial width to 200 points
            splitView.setPosition(200, ofDividerAt: 0)
            hasSetInitialWidth = true
        }
    }

    @objc func toggleChatList() {
        guard let sidebarItem = sidebarItem else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        }, completionHandler: { [weak self] in
            self?.updateSidebarToggleButton()
        })
    }

    // The sidebar also collapses when the window gets too narrow for it and
    // the chat's minimum width, or when its divider is dragged shut.
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        updateSidebarToggleButton()
    }

    private func updateSidebarToggleButton() {
        let collapsed = sidebarItem?.isCollapsed ?? false
        sidebarToggleButton.toolTip = collapsed
            ? String(localized: "ChatSplitViewController.ShowChatList", defaultValue: "Show chat list", comment: "Tooltip for the button that shows the hidden chat list in the AI chat window")
            : String(localized: "ChatSplitViewController.HideChatList", defaultValue: "Hide chat list", comment: "Tooltip for the button that hides the chat list in the AI chat window")
    }
}
