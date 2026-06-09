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
    private var sidebarToggleRelayoutGeneration = 0
    private let sidebarToggleButton: NSButton = {
        let image = NSImage(systemSymbolName: SFSymbol.sidebarLeft.rawValue,
                            accessibilityDescription: "Toggle Chat List")!
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .badge
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        return button
    }()

    init(chatListViewController: ChatListViewController, chatViewController: ChatViewController) {
        self.chatListViewController = chatListViewController
        self.chatViewController = chatViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(toggleChatList)
        sidebarToggleButton.autoresizingMask = [.minYMargin, .maxXMargin]
        chatViewController.view.postsFrameChangedNotifications = true
        chatViewController.view.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(chatContentViewFrameDidChange(_:)),
                                               name: NSView.frameDidChangeNotification,
                                               object: chatViewController.view)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(chatContentViewFrameDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification,
                                               object: chatViewController.view)
        chatViewController.view.addSubview(sidebarToggleButton)
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
        scheduleSidebarToggleButtonRelayouts()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        scheduleSidebarToggleButtonRelayouts()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSidebarToggleButton()
    }

    @objc func toggleChatList() {
        guard let sidebarItem = sidebarItem else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
        }, completionHandler: { [weak self] in
            self?.updateSidebarToggleButton()
            self?.scheduleSidebarToggleButtonRelayouts()
        })
    }

    @objc private func chatContentViewFrameDidChange(_ notification: Notification) {
        layoutSidebarToggleButton()
    }

    private func scheduleSidebarToggleButtonRelayouts() {
        sidebarToggleRelayoutGeneration += 1
        let generation = sidebarToggleRelayoutGeneration
        let delays: [TimeInterval] = [0, 0.05, 0.15, 0.35]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.sidebarToggleRelayoutGeneration == generation else {
                    return
                }
                self.layoutSidebarToggleButtonAfterWindowSettles()
            }
        }
    }

    private func layoutSidebarToggleButtonAfterWindowSettles() {
        view.layoutSubtreeIfNeeded()
        splitView.layoutSubtreeIfNeeded()
        chatViewController.view.layoutSubtreeIfNeeded()
        layoutSidebarToggleButton()
    }

    private func layoutSidebarToggleButton() {
        let buttonSize = NSSize(width: 30, height: 30)
        let contentBounds = chatViewController.view.bounds
        let topInset = chatViewController.view.safeAreaInsets.top
        sidebarToggleButton.frame = NSRect(x: 12,
                                           y: contentBounds.height - topInset - buttonSize.height - 10,
                                           width: buttonSize.width,
                                           height: buttonSize.height)
    }

    private func updateSidebarToggleButton() {
        let collapsed = sidebarItem?.isCollapsed ?? false
        sidebarToggleButton.toolTip = collapsed ? "Show chat list" : "Hide chat list"
        sidebarToggleButton.layer?.backgroundColor = (collapsed
                                                      ? NSColor.controlAccentColor.withAlphaComponent(0.28)
                                                      : NSColor.clear).cgColor
    }
}
