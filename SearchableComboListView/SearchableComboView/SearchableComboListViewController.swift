//
//  SearchableComboListViewController.swift
//  SearchableComboListView
//
//  Created by George Nachman on 1/24/20.
//

import AppKit

@objc(iTermSearchableComboListViewControllerDelegate)
protocol SearchableComboListViewControllerDelegate: NSObjectProtocol {
    func searchableComboListViewController(_ listViewController: SearchableComboListViewController,
                                           didSelectItem item: SearchableComboViewItem?)

    func searchableComboListViewController(_ listViewController: SearchableComboListViewController,
                                           maximumHeightDidChange maxHeight: CGFloat)
}

class SearchableComboListViewController: NSViewController {
    @objc(delegate) @IBOutlet public weak var delegate: SearchableComboListViewControllerDelegate?
    @IBOutlet public weak var tableView: SearchableComboTableView!
    @IBOutlet public weak var searchField: NSSearchField!
    @IBOutlet public weak var visualEffectView: NSVisualEffectView!
    private var closeOnSelect = true
    public var tableViewController: SearchableComboTableViewController?
    let groups: [SearchableComboViewGroup]

    public var selectedItem: SearchableComboViewItem? {
        didSet {
            let _ = view
            tableViewController!.selectedTag = selectedItem?.tag ?? -1
        }
    }

    public var insets: NSEdgeInsets {
        let frame = view.convert(searchField.bounds, from: searchField)
        return NSEdgeInsets(top: NSMaxY(view.bounds) - NSMaxY(frame),
                            left: NSMinX(frame),
                            bottom: 0,
                            right: NSMaxX(view.bounds) - NSMaxX(frame))
    }

    var desiredHeight: CGFloat {
        return (tableViewController?.desiredHeight ?? 0) + heightAboveTable + 1
    }


    private var heightAboveTable: CGFloat {
        guard let scrollView = tableView.enclosingScrollView else {
            return 0
        }
        return view.frame.height - scrollView.frame.maxY
    }

    init(groups: [SearchableComboViewGroup]) {
        self.groups = groups
        super.init(nibName: "SearchableComboView", bundle: Bundle(for: SearchableComboListViewController.self))
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        preconditionFailure()
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    public override func awakeFromNib() {
        tableViewController = SearchableComboTableViewController(tableView: tableView, groups: groups)
        tableViewController?.delegate = self
        visualEffectView.blendingMode = .behindWindow;
        visualEffectView.material = .menu;
        visualEffectView.state = .active;
    }

    func item(withTag tag: Int) -> SearchableComboViewItem? {
        for group in groups {
            for item in group.items {
                if item.tag == tag {
                    return item
                }
            }
        }
        return nil
    }
}

extension SearchableComboListViewController: NSTextFieldDelegate {
    @objc(controlTextDidChange:)
    public func controlTextDidChange(_ obj: Notification) {
        let previouslySelectedItem = tableViewController?.selectedItem

        tableViewController?.filter = searchField.stringValue
        tableViewController?.selectOnlyItem(or: previouslySelectedItem)
        delegate?.searchableComboListViewController(
            self, maximumHeightDidChange: desiredHeight)
    }

    public override func viewWillAppear() {
        let tag = tableViewController?.selectedTag
        view.window?.makeFirstResponder(searchField)
        tableViewController?.selectedTag = tag
    }

    private func makeSearchFieldFirstResponderPreservingTableViewSelectedRow() {
        let selectedIndexes = tableView.selectedRowIndexes
        searchField.window?.makeFirstResponder(searchField)
        // The tableview removers its selection upon resigning first responder. Re-select it so that
        // the serach field can manipulate the table view's selection appropriately.
        tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
    }
}

extension SearchableComboListViewController: SearchableComboTableViewControllerDelegate {
    func searchableComboTableViewController(_ tableViewController: SearchableComboTableViewController,
                                            didSelectItem item: SearchableComboViewItem?) {
        selectedItem = item
        delegate?.searchableComboListViewController(self, didSelectItem: item)
        if closeOnSelect {
            view.window?.orderOut(nil)
        }
    }

    func searchableComboTableViewControllerGroups(_ tableViewController: SearchableComboTableViewController) -> [SearchableComboViewGroup] {
        return groups
    }

    func searchableComboTableViewController(_ tableViewController: SearchableComboTableViewController,
                                            didType event: NSEvent) {
        // Restore keyboard focus to the search field.
        guard searchField.window != nil else {
            return
        }
        makeSearchFieldFirstResponderPreservingTableViewSelectedRow()
        guard let fieldEditor = searchField.window?.fieldEditor(false, for: searchField) else {
            return
        }
        let insertionRange = NSRange(location: fieldEditor.string.utf16.count, length: 0)
        fieldEditor.selectedRange = insertionRange
        fieldEditor.keyDown(with: event)
        tableView.window?.makeFirstResponder(searchField)
        fieldEditor.selectedRange = NSRange(location: fieldEditor.string.utf16.count, length: 0)
    }
}

extension SearchableComboListViewController: SearchableComboListSearchFieldDelegate {
    func searchFieldPerformKeyEquivalent(with event: NSEvent) -> Bool {
        guard let window = searchField.window else {
            return false
        }
        guard let firstResponder = window.firstResponder else {
            return false
        }
        guard let textView = firstResponder as? NSTextView else {
            return false
        }
        guard window.fieldEditor(false, for: nil) != nil else {
            return false
        }
        guard searchField == textView.delegate as? NSSearchField else {
            return false
        }
        let mask: NSEvent.ModifierFlags = [.shift, .control, .option, .command]
        guard event.modifierFlags.intersection(mask) == [] else {
            return super.performKeyEquivalent(with: event)
        }
        if event.keyCode == 125 /* down arrow */ || event.keyCode == 126 /* up arrow */ {
            // TODO: Prevent reentrancy?
            closeOnSelect = false
            tableView.window?.makeFirstResponder(tableView)
            tableView.keyDown(with: event)
            closeOnSelect = true
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

