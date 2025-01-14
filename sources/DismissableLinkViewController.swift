//
//  DismissableLinkViewController.swift
//  iTerm2
//
//  Created by George Nachman on 3/27/22.
//

import Foundation
import AppKit

class ButtonWithCustomCursor: NSButton {
    var cursor: NSCursor? {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        if let cursor = cursor {
            addCursorRect(self.bounds, cursor: cursor)
        } else {
            super.resetCursorRects()
        }
    }
}

@objc(iTermDismissableLinkViewController)
class DismissableLinkViewController: NSViewController {
    private let userDefaultsKey: String
    private let text: String
    private let url: URL
    private var button: ButtonWithCustomCursor?
    private var close: NSButton?
    private let rightMargin = 8.0
    private let innerMargin = 0.0
    private let clickToHide: Bool

    @objc public func disabled() -> Bool {
        if #available(macOS 11.0, *) {
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        } else {
            // Hide pre-big sur because I need SF Symbols.
            return true
        }
    }

    @objc
    init(userDefaultsKey: String,
         text: String,
         url: URL,
         clickToHide: Bool) {
        self.userDefaultsKey = userDefaultsKey
        self.text = text
        self.url = url
        self.clickToHide = clickToHide
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let button = ButtonWithCustomCursor()
        button.cursor = NSCursor.pointingHand
        let hyperlinkBlue = NSColor.init(srgbRed: 0,
                                         green: 102.0 / 255.0,
                                         blue: 204.0 / 255.0,
                                         alpha: 1)
        let title = NSAttributedString(string: text,
                                       attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 2),
                                                    .foregroundColor: hyperlinkBlue,
                                                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                                                    .underlineColor: hyperlinkBlue])
        button.isBordered = false
        button.attributedTitle = title
        button.target = self
        button.action = #selector(handleClick(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.sizeToFit()
        self.button = button

        view = NSView()
        view.frame = NSRect(x: 0, y: 0, width: button.frame.width + rightMargin + 16, height: 5)
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(button)

        view.addConstraint(NSLayoutConstraint(item: button,
                                              attribute: .top,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .top,
                                              multiplier: 1,
                                              constant: 0))
        view.addConstraint(NSLayoutConstraint(item: button,
                                              attribute: .bottom,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .bottom,
                                              multiplier: 1,
                                              constant: 0))
        view.addConstraint(NSLayoutConstraint(item: button,
                                              attribute: .trailing,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .trailing,
                                              multiplier: 1,
                                              constant: -rightMargin))
        view.addConstraint(NSLayoutConstraint(item: button,
                                              attribute: .leading,
                                              relatedBy: .greaterThanOrEqual,
                                              toItem: view,
                                              attribute: .leading,
                                              multiplier: 1,
                                              constant: 0))
        if disabled() {
            view.isHidden = true
        }
        if #available(macOS 11.0, *) {
            if !clickToHide {
                addHideButton()
            }
        }
    }

    @available(macOS 11.0, *)
    private func addHideButton() {
        guard close == nil else {
            return
        }
        let imageButton = NSButton()
        close = imageButton
        imageButton.image = NSImage(systemSymbolName: "xmark.circle",
                                    accessibilityDescription: "Permanently hide \(text) button")
        imageButton.bezelStyle = .shadowlessSquare
        imageButton.isBordered = false
        imageButton.imagePosition = .imageOnly
        imageButton.target = self
        imageButton.action = #selector(hide(_:))
        imageButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageButton)

        view.addConstraint(NSLayoutConstraint(item: imageButton,
                                              attribute: .centerY,
                                              relatedBy: .equal,
                                              toItem: button!,
                                              attribute: .centerY,
                                              multiplier: 1,
                                              constant: 1))
        view.addConstraint(NSLayoutConstraint(item: imageButton,
                                              attribute: .trailing,
                                              relatedBy: .equal,
                                              toItem: button!,
                                              attribute: .leading,
                                              multiplier: 1,
                                              constant: -innerMargin))
        view.addConstraint(NSLayoutConstraint(item: imageButton,
                                              attribute: .leading,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .leading,
                                              multiplier: 1,
                                              constant: 0))
    }

    @objc func handleClick(_ sender: Any) {
        NSWorkspace.shared.open(url)
        if #available(macOS 11.0, *) {
            addHideButton()
        }
    }

    @objc func hide(_ sender: Any) {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
        view.isHidden = true
    }
}
