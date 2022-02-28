//
//  DonateViewController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/27/22.
//

import Foundation

@objc(iTermDonateViewController)
class DonateViewController: NSTitlebarAccessoryViewController {
    private static let userDefaultsKey = "NoSyncHideDonateLabel"
    private var button: NSButton?
    private var close: NSButton?
    private let rightMargin = 8.0
    private let innerMargin = 0.0

    @objc public static func disabled() -> Bool {
        if #available(macOS 11.0, *) {
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        } else {
            // Hide pre-big sur because I need SF Symbols.
            return true
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .right
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let button = NSButton()
        let hyperlinkBlue = NSColor.init(srgbRed: 0,
                                         green: 102.0 / 255.0,
                                         blue: 204.0 / 255.0,
                                         alpha: 1)
        let title = NSAttributedString(string: "Donate",
                                       attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize - 2),
                                                    .foregroundColor: hyperlinkBlue,
                                                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                                                    .underlineColor: hyperlinkBlue])
        button.isBordered = false
        button.attributedTitle = title
        button.target = self
        button.action = #selector(donate(_:))
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
                                              constant: 7))
        view.addConstraint(NSLayoutConstraint(item: button,
                                              attribute: .trailing,
                                              relatedBy: .equal,
                                              toItem: view,
                                              attribute: .trailing,
                                              multiplier: 1,
                                              constant: -rightMargin))
        if Self.disabled() {
            view.isHidden = true
        }
    }

    @objc func donate(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://iterm2.com/donate.html")!)
        if #available(macOS 11.0, *) {
            guard close == nil else {
                return
            }
            let imageButton = NSButton()
            imageButton.image = NSImage(systemSymbolName: "xmark.circle",
                                        accessibilityDescription: "Permanently hide Donate button")
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
        }
    }

    @objc func hide(_ sender: Any) {
        UserDefaults.standard.set(true, forKey: Self.userDefaultsKey)
        view.isHidden = true
    }
}
