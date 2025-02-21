//
//  ChatSplitViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

class NoDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        return 0
    }

    override func drawDivider(in rect: NSRect) {
    }
}

class ChatSplitViewController: NSViewController {
    let chatListViewController: ChatListViewController
    let chatViewController: ChatViewController
    private let splitView = NoDividerSplitView()

    init(chatListViewController: ChatListViewController, chatViewController: ChatViewController) {
        self.chatListViewController = chatListViewController
        self.chatViewController = chatViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        addChild(chatListViewController)
        addChild(chatViewController)
        splitView.addArrangedSubview(chatListViewController.view)
        splitView.addArrangedSubview(chatViewController.view)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        chatListViewController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 120.0).isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        splitView.setPosition(200, ofDividerAt: 0)
    }

    func toggleChatList() {
        if chatListViewController.view.isHidden {
            // Expanding: unhide first, then animate divider to 200.
            chatListViewController.view.isHidden = false
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.splitView.animator().setPosition(200, ofDividerAt: 0)
            })
        } else {
            // Collapsing: animate divider to 0 then hide.
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self.splitView.animator().setPosition(0, ofDividerAt: 0)
            }, completionHandler: {
                self.chatListViewController.view.isHidden = true
            })
        }
    }
}
