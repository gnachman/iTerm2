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
    public let label: String
    public let tag: Int
    public let identifier: String?
    public let labelTokens: [String]
    internal(set) public weak var group: SearchableComboViewGroup?

    @objc(initWithLabel:tag:)
    public init(_ label: String, tag: Int) {
        self.label = label
        self.tag = tag
        self.identifier = nil
        labelTokens = label.tokens
    }

    @objc(initWithLabel:tag:identifier:)
    public init(_ label: String, tag: Int, identifier: String?) {
        self.label = label
        self.tag = tag
        self.identifier = identifier
        labelTokens = label.tokens
    }
}

@objc(iTermSearchableComboView)
open class SearchableComboView: NSPopUpButton {
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
    private let defaultTitle: String

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

    @objc open class func groups() -> [SearchableComboViewGroup] {
        return []
    }

    open class func defaultTitleValue() -> String {
        return "Select Action…"
    }

    required public init?(coder: NSCoder) {
        listViewController = SearchableComboListViewController(groups: Self.groups())
        defaultTitle = Self.defaultTitleValue()
        super.init(coder: coder)
        addItem(withTitle: "")
        postInit()
    }

    @objc(initWithGroups:defaultTitle:)
    public init(_ groups: [SearchableComboViewGroup], defaultTitle: String) {
        listViewController = SearchableComboListViewController(groups: groups)
        self.defaultTitle = defaultTitle
        super.init(frame: NSRect.zero, pullsDown: true)
        addItem(withTitle: "")
        postInit()
    }

    deinit {
        if let internalPanel = internalPanel {
            internalPanel.close()
        }
    }

    private func removeSelection() {
        setTitle(defaultTitle)
        listViewController.selectedItem = nil
    }

    override public func selectItem(withTag tag: Int) -> Bool {
        if let item = listViewController.item(withTag: tag) {
            setTitle(item.label)
            listViewController.selectedItem = item
            return true
        }
        removeSelection()
        return false
    }

    public func selectItem(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> Bool {
        if let item = listViewController.item(withIdentifier: identifier) {
            setTitle(item.label)
            listViewController.selectedItem = item
            return true
        }
        removeSelection()
        return false
    }

    open override func selectItem(withTitle title: String) {
        if let item = listViewController.item(withTitle: title) {
            setTitle(item.label)
            listViewController.selectedItem = item
            return
        }
        removeSelection()
    }

    override public func selectedTag() -> Int {
        return listViewController.tableViewController?.selectedTag ?? -1
    }


    override public func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.cancelTrackingWithoutAnimation()
        showPanel()
    }

    @objc open override var selectedItem: NSMenuItem? {
        let item = NSMenuItem()
        guard let myItem = listViewController.tableViewController?.selectedItem else {
            return nil
        }
        item.title = myItem.label
        item.identifier = myItem.identifier.map { NSUserInterfaceItemIdentifier($0) }
        return item
    }

    @objc var selectedTitle: String? {
        return selectedItem?.title
    }

    @objc var selectedIdentifier: NSUserInterfaceItemIdentifier? {
        return selectedItem?.identifier
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
        let initialSize = CGSize(width: max(listViewController.widestItemWidth, bounds.width) + insets.left + insets.right,
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

        // Work around an apparent bug in NSTableView that causes it to want to grow 16 points larger
        // than the scrollview.
        listViewController.tableViewController?.updateColumnWidths()

        listViewController.tableView.tile()
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

