//
//  WorkgroupNavigationToolbarItem.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/26/26.
//

import AppKit

// Three navigation buttons (Back, Forward, Reload) packed into a
// single toolbar item so they read as a cluster rather than three
// loose controls separated by toolbar dividers.
protocol WorkgroupNavigationToolbarItemDelegate: AnyObject {
    func workgroupNavigationDidTapBack(sender: WorkgroupNavigationToolbarItem)
    func workgroupNavigationDidTapForward(sender: WorkgroupNavigationToolbarItem)
    func workgroupNavigationDidTapReload(sender: WorkgroupNavigationToolbarItem)
}

final class WorkgroupNavigationToolbarItem: SessionToolbarGenericView {
    weak var navigationDelegate: WorkgroupNavigationToolbarItemDelegate?
    // Tagged with the owning peer/host config UUID so the delegate
    // can demultiplex which session's button fired.
    var ownerPeerID: String?

    private let backButton: NSButton
    private let forwardButton: NSButton
    private let reloadButton: NSButton
    private static let interButtonSpacing = 8.0

    init(identifier: String, priority: Int) {
        backButton = Self.makeButton(symbol: .chevronLeft)
        forwardButton = Self.makeButton(symbol: .chevronRight)
        reloadButton = Self.makeButton(symbol: .arrowClockwise)

        // Plain NSView container, no auto layout — terminal-window
        // toolbars are explicitly autoresizing-mask territory per the
        // project rule. Children are positioned in layoutSubviews.
        let container = NSView(frame: .zero)
        container.addSubview(backButton)
        container.addSubview(forwardButton)
        container.addSubview(reloadButton)

        super.init(identifier: identifier, priority: priority, view: container)
        backButton.target = self
        backButton.action = #selector(didTapBack(_:))
        forwardButton.target = self
        forwardButton.action = #selector(didTapForward(_:))
        reloadButton.target = self
        reloadButton.action = #selector(didTapReload(_:))
    }

    private var buttons: [NSButton] {
        [backButton, forwardButton, reloadButton]
    }

    private var naturalWidth: CGFloat {
        var width = 0.0
        let bs = buttons
        for (i, b) in bs.enumerated() {
            width += b.fittingSize.width
            if i < bs.count - 1 {
                width += Self.interButtonSpacing
            }
        }
        return width
    }

    override var desiredWidthRange: ClosedRange<CGFloat> {
        let w = naturalWidth
        return w...w
    }

    override func layoutSubviews() {
        // Skip super — its sizing assumes _view has a useful
        // fittingSize, but a plain container reports zero. Lay
        // _view (the container) and its children out by frame.
        let height = view.bounds.height
        _view.frame = NSRect(x: 0,
                             y: 0,
                             width: view.bounds.width,
                             height: height)
        var x = 0.0
        for b in buttons {
            let buttonSize = b.fittingSize
            b.frame = NSRect(x: x,
                             y: (height - buttonSize.height) / 2.0,
                             width: buttonSize.width,
                             height: buttonSize.height)
            x += buttonSize.width + Self.interButtonSpacing
        }
    }

    private static func makeButton(symbol: SFSymbol) -> NSButton {
        let image = NSImage(systemSymbolName: symbol.rawValue,
                            accessibilityDescription: nil) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.refusesFirstResponder = true
        button.setButtonType(.momentaryPushIn)
        return button
    }

    @objc private func didTapBack(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapBack(sender: self)
    }

    @objc private func didTapForward(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapForward(sender: self)
    }

    @objc private func didTapReload(_ sender: Any?) {
        navigationDelegate?.workgroupNavigationDidTapReload(sender: self)
    }
}
