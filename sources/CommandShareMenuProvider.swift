//
//  CommandShareMenuProvider.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/30/24.
//

import Foundation

@objc(iTermCommandShareMenuProvider)
class CommandShareMenuProvider: NSObject {
    private let mark: VT100ScreenMarkReading
    private let promisedContent: iTermRenegablePromise<NSAttributedString>
    private let defaultBackgroundColor: NSColor
    private let commandURL: URL?

    @objc
    init(mark: VT100ScreenMarkReading,
         promisedContent: iTermRenegablePromise<NSAttributedString>,
         defaultBackgroundColor: NSColor,
         commandURL: URL?) {
        self.mark = mark
        self.promisedContent = promisedContent
        self.defaultBackgroundColor = defaultBackgroundColor
        self.commandURL = commandURL
    }

    @objc
    func pop(locationInWindow: NSPoint,
             view: NSView) {
        guard let window = view.window else {
            return
        }
        let menu = SimpleContextMenu()
        let command = mark.command ?? ""
        if !command.isEmpty {
            menu.addItem(title: "Add Command as Snippet") { [weak window] in
                CommandShareMenuProvider.addCommandAsSnippet(command,
                                                             window: window,
                                                             locationInWindow: locationInWindow)
            }
        }

        menu.addSeparator()

        let mark = self.mark
        let promisedContent = self.promisedContent
        let defaultBackgroundColor = self.defaultBackgroundColor
        menu.addItem(title: "Save Command & Output…") { [weak window] in
            CommandShareMenuProvider.saveCommandAndOutput(promisedContent: promisedContent,
                                                          defaultBackgroundColor: defaultBackgroundColor,
                                                          mark: mark,
                                                          window: window)
        }

        menu.addSeparator()

        menu.addItem(title: "Share Command Output…") { [weak view] in
            if let view {
                CommandShareMenuProvider.shareCommandOutput(locationInWindow: locationInWindow,
                                                            promisedContent: promisedContent,
                                                            view: view)
            }
        }

        menu.addSeparator()

        if let commandURL {
            menu.addItem(title: "Copy Command URL to Clipboard") { [weak window] in
                CommandShareMenuProvider.copyCommandURL(url: commandURL,
                                                        window: window,
                                                        locationInWindow: locationInWindow)
            }
            menu.addItem(title: "Share Command URL…") { [weak view] in
                if let view {
                    CommandShareMenuProvider.shareCommandURL(locationInWindow: locationInWindow,
                                                             url: commandURL,
                                                             view: view)
                }
            }
        }

        if !menu.isEmpty, let event = NSApp.currentEvent {
            menu.show(in: view, for: event)
        }
    }

    private static func addCommandAsSnippet(_ command: String,
                                            window: NSWindow?,
                                            locationInWindow: NSPoint) {
        let snippet = iTermSnippet(title: command,
                                   value: command,
                                   guid: UUID().uuidString,
                                   tags: [],
                                   escaping: .none,
                                   version: iTermSnippet.currentVersion())
        iTermSnippetsModel.sharedInstance().addSnippet(snippet)
        guard let window else {
            return
        }
        let point = window.convertPoint(toScreen: locationInWindow)
        ToastWindowController.showToast(withMessage: "Snippet Added",
                                        duration: 1,
                                        topLeftScreenCoordinate: point,
                                        pointSize: 12)
    }

    private static func defaultCommand(_ maybeCommand: String?) -> String {
        let fallback = "iTerm2 Command"
        guard let justCommand = maybeCommand else {
            return fallback
        }
        let command = justCommand as NSString
        guard let path = command.componentsInShellCommand().first else {
            return fallback
        }
        return path.lastPathComponent
    }

    private static func saveCommandAndOutput(promisedContent: iTermRenegablePromise<NSAttributedString>,
                                             defaultBackgroundColor: NSColor,
                                             mark: VT100ScreenMarkReading,
                                             window: NSWindow?) {
        guard let window else {
            return
        }
        let saver = AttributedStringSaver(promisedContent)
        saver.documentAttributes = [ .backgroundColor: defaultBackgroundColor]
        saver.save(defaultName: defaultCommand(mark.command), window: window)
    }

    private static func copyCommandURL(url: URL, window: NSWindow?, locationInWindow: NSPoint) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let objects: [any NSPasteboardWriting] = [ url as NSURL, url.absoluteString as NSString ]
        pasteboard.writeObjects(objects)

        guard let window else {
            return
        }
        let point = window.convertPoint(toScreen: locationInWindow)
        ToastWindowController.showToast(withMessage: "Copied",
                                        duration: 1,
                                        topLeftScreenCoordinate: point,
                                        pointSize: 12)
    }

    private static func shareCommandURL(locationInWindow: NSPoint,
                                        url: URL,
                                        view: NSView) {
        var viewRect = NSRect()
        viewRect.origin = locationInWindow
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: viewRect, of: view, preferredEdge: .minY)
    }

    private static func shareCommandOutput(locationInWindow: NSPoint,
                                           promisedContent: iTermRenegablePromise<NSAttributedString>,
                                           view: NSView) {
        var viewRect = NSRect()
        viewRect.origin = locationInWindow
        promisedContent.wait().whenFirst { [weak view] attributedString in
            guard let view else {
                return
            }
            let picker = NSSharingServicePicker(items: [attributedString])
            picker.show(relativeTo: viewRect, of: view, preferredEdge: .minY)
        }
    }
}
