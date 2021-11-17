//
//  SearchableComboView.swift
//  SearchableComboView
//
//  Created by George Nachman on 1/20/20.
//

import AppKit

@objc(iTermSearchableComboViewDelegate)
public protocol SearchableComboViewDelegate: AnyObject {
    func searchableComboView(_ view: SearchableComboView, didSelectItem: SearchableComboViewItem?)
}

@objc(iTermSearchableComboViewGroup)
public class SearchableComboViewGroup: NSObject {
    let label: String
    let items: [SearchableComboViewItem]
    let labelTokens: [String]

    @objc(initWithLabel:items:)
    public init(_ label: String, items: [SearchableComboViewItem]) {
        self.label = label
        self.items = items
        labelTokens = label.tokens

        super.init()

        for item in items {
            item.group = self
        }
    }
}

@objc(iTermSearchableComboViewItem)
public class SearchableComboViewItem: NSObject {
    let label: String
    let tag: Int
    let labelTokens: [String]
    weak var group: SearchableComboViewGroup?

    @objc(initWithLabel:tag:)
    public init(_ label: String, tag: Int) {
        self.label = label
        self.tag = tag
        labelTokens = label.tokens
    }
}

@objc(iTermSearchableComboView)
public class SearchableComboView: NSPopUpButton {
    public class Panel: NSPanel {
        public override var canBecomeKey: Bool {
            return true
        }

        public override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
            return 0.167
        }

        public override func cancelOperation(_ sender: Any?) {
            parent?.removeChildWindow(self)
            orderOut(nil)
        }

        public override func resignKey() {
            super.resignKey()
            parent?.removeChildWindow(self)
            orderOut(nil)
        }
    }

    @objc public weak var delegate: SearchableComboViewDelegate?
    let listViewController: SearchableComboListViewController
    private var internalPanel: Panel?
    private let minimumHeight = CGFloat(99)
    // Is the panel above the button?
    private var isAbove = false

    private var panel: Panel {
        get {
            if let internalPanel = internalPanel {
                return internalPanel
            }
            let newPanel = Panel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                 styleMask: [.resizable, .fullSizeContentView],
                                 backing: .buffered,
                                 defer: true)
            newPanel.hidesOnDeactivate = false
            newPanel.orderOut(nil)
            newPanel.contentView?.addSubview(listViewController.view)
            newPanel.isOpaque = false

            newPanel.contentView?.wantsLayer = true;
            newPanel.contentView?.layer?.cornerRadius = 6;
            newPanel.contentView?.layer?.masksToBounds = true;
            newPanel.contentView?.layer?.borderColor = NSColor(white: 0.66, alpha: 1).cgColor
            newPanel.contentView?.layer?.borderWidth = 0.5;

            internalPanel = newPanel

            return newPanel
        }
    }

    private func postInit() {
        listViewController.delegate = self
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    @objc(initWithGroups:)
    public init(_ groups: [SearchableComboViewGroup]) {
        listViewController = SearchableComboListViewController(groups: groups)
        super.init(frame: NSRect.zero, pullsDown: true)
        addItem(withTitle: "")
        postInit()
    }

    deinit {
        if let internalPanel = internalPanel {
            internalPanel.close()
        }
    }

    override public func selectItem(withTag tag: Int) -> Bool {
        if let item = listViewController.item(withTag: tag) {
            setTitle(item.label)
            listViewController.selectedItem = item
            return true
        }
        setTitle("Selection Action…")
        listViewController.selectedItem = nil
        return false
    }

    override public func selectedTag() -> Int {
        return listViewController.tableViewController?.selectedTag ?? -1
    }

    override public func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.cancelTrackingWithoutAnimation()
        showPanel()
    }

    private var myFrameInScreenCoords: NSRect {
        let myFrameInWindowCoords = convert(bounds, to: nil)
        return window!.convertToScreen(myFrameInWindowCoords)
    }

    private var maxPanelHeightWhenBelow: CGFloat {
        return myFrameInScreenCoords.maxY - window!.screen!.visibleFrame.minY
    }

    private var maxPanelHeightWhenAbove: CGFloat {
        return max(minimumHeight, window!.screen!.visibleFrame.maxY - myFrameInScreenCoords.minY)
    }

    private var panelShouldBeAboveButton: Bool {
        return maxPanelHeightWhenBelow < minimumHeight
    }

    private func desiredPanelFrame(_ desiredHeight: CGFloat) -> CGRect {
        if isAbove {
            return desiredPanelFrameWhenAbove(desiredHeight)
        } else {
            return desiredPanelFrameWhenBelow(desiredHeight)
        }
    }

    private func desiredPanelFrameWhenAbove(_ desiredHeight: CGFloat) -> CGRect {
        let insets = listViewController.insets
        let initialSize = CGSize(width: bounds.width + insets.left + insets.right,
                                 height: min(maxPanelHeightWhenAbove, desiredHeight))
        return NSRect(origin: CGPoint(x: myFrameInScreenCoords.minX - insets.left,
                                      y: myFrameInScreenCoords.minY),
                      size: initialSize)
    }

    private func desiredPanelFrameWhenBelow(_ desiredHeight: CGFloat) -> CGRect {
        let insets = listViewController.insets
        let initialSize = CGSize(width: bounds.width + insets.left + insets.right,
                                 height: min(maxPanelHeightWhenBelow, desiredHeight))
        return NSRect(origin: CGPoint(x: myFrameInScreenCoords.minX - insets.left,
                                      y: myFrameInScreenCoords.maxY - initialSize.height + insets.top),
                      size: initialSize)
    }

    private func showPanel() {
        isAbove = panelShouldBeAboveButton
        window?.addChildWindow(panel, ordered: .above)
        panel.setFrame(desiredPanelFrame(listViewController.desiredHeight), display: true)
        listViewController.view.frame = panel.contentView!.bounds
        panel.makeKeyAndOrderFront(nil)
        listViewController.tableViewController?.selectOnlyItem()
    }
}

extension SearchableComboView: SearchableComboListViewControllerDelegate {
    func searchableComboListViewController(_ listViewController: SearchableComboListViewController,
                                           didSelectItem item: SearchableComboViewItem?) {
        guard let item = item else {
            return
        }
        setTitle(item.label)

        delegate?.searchableComboView(self, didSelectItem: item)
    }

    func searchableComboListViewController(_ listViewController: SearchableComboListViewController,
                                           maximumHeightDidChange desiredHeight: CGFloat) {
        let frame = desiredPanelFrame(desiredHeight)
        if frame == panel.frame {
            return
        }
        panel.setFrame(frame, display: true, animate: true)
    }
}

