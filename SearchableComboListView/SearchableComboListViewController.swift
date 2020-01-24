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
}

class SearchableComboListViewController: NSViewController {
    @IBOutlet public weak var tableView: SearchableComboTableView!
    @IBOutlet public weak var searchField: NSSearchField!
    @IBOutlet public weak var visualEffectView: NSVisualEffectView!
    private var closeOnSelect = true

    @objc(delegate) @IBOutlet public weak var delegate: SearchableComboListViewControllerDelegate?
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
    public var tableViewController: SearchableComboTableViewController?

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
        tableViewController?.filter = searchField.stringValue
    }

    public override func viewWillAppear() {
        view.window?.makeFirstResponder(searchField)
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

