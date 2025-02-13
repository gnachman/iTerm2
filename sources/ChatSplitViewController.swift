//
//  ChatSplitViewController.swift
//  iTerm2
//
//  Created by George Nachman on 2/11/25.
//

import AppKit

class ChatSplitViewController: NSViewController {
    let chatListViewController: ChatListViewController
    let chatViewController: ChatViewController
    private var splitView = NSSplitView()

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
        splitView = NSSplitView()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.dividerStyle = .thin
        view.addSubview(splitView)

        addChild(chatListViewController)
        addChild(chatViewController)
        splitView.addArrangedSubview(chatListViewController.view)
        splitView.addArrangedSubview(chatViewController.view)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 40), // leave space for button
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Set an initial width for the chat list pane.
        chatListViewController.view.widthAnchor.constraint(equalToConstant: 200).isActive = true
    }

    func toggleChatList() {
        // Toggle collapse/expand by hiding/unhiding the chat list view.
        chatListViewController.view.isHidden.toggle()
    }
}
