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
            addSplitViewItem(contentItem)
        }

        // Use thin divider style
        splitView.dividerStyle = .thin
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

    override func viewDidAppear() {
        super.viewDidAppear()

        // Ensure sidebar is visible
        if let sidebarItem = sidebarItem {
            sidebarItem.isCollapsed = false
        }
    }

    func toggleChatList() {
        guard let sidebarItem = sidebarItem else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        })
    }
}
