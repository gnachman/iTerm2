//
//  ChatWindowController.swift
//  iTerm2
//
//  Created by George Nachman on 2/10/25.
//

import AppKit

@objc(iTermChatWindowController)
class ChatWindowController: NSWindowController {
    @objc let chatViewController: ChatViewController

    @objc(initWithTitle:)
    init(title: String) {
        // Create the chat view controller
        chatViewController = ChatViewController()

        // Configure the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Chat"
        window.contentViewController = chatViewController
        window.center()

        super.init(window: window)

        // Configure window appearance
        window.titlebarAppearsTransparent = false
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("ChatWindow")
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()
        configureWindowSettings()
    }

    private func configureWindowSettings() {
        guard let window else {
            return
        }
        window.minSize = NSSize(width: 400, height: 300)
    }

    // MARK: - Public Interface

    @objc
    func showChatWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func appendAgentMessage(_ text: String) {
        chatViewController.appendAgentMessage(text: text)
    }

    func loadChatHistory(_ history: NSDictionary) {
        chatViewController.loadChat(from: history)
    }

    var dictionaryValue: NSDictionary {
        return chatViewController.dictionaryValue
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(closeCurrentSession(_:)) {
            return true
        }
        return false
    }

    @objc(closeCurrentSession:)
    func closeCurrentSession(_ sender: Any) {
        window?.performClose(sender)
    }
}
