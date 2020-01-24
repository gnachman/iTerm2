//
//  SearchableComboView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/20.
//

import AppKit

@objc(iTermSearchableComboViewDelegate)
public protocol SearchableComboViewDelegate: class {
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
    public var maxHeight: CGFloat = 600

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

    private func showPanel() {
        let insets = listViewController.insets
        let initialSize = CGSize(width: bounds.width + insets.left + insets.right,
                                 height: maxHeight)
        let myFrameInWindowCoords = convert(bounds, to: nil)
        let myFrameInScreenCoords = window!.convertToScreen(myFrameInWindowCoords)
        listViewController.view.frame = panel.contentView!.bounds
        window?.addChildWindow(panel, ordered: .above)
        let panelFrame = NSRect(origin: CGPoint(x: myFrameInScreenCoords.minX - insets.left,
                                                y: myFrameInScreenCoords.maxY - initialSize.height + insets.top),
                                size: initialSize)
        panel.setFrame(panelFrame, display: true)
        panel.makeKeyAndOrderFront(nil)
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
}

