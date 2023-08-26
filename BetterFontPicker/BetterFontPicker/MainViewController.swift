//
//  MainViewController.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

fileprivate var tokenCache: NSCache<NSString, NSArray> = {
    let value = NSCache<NSString, NSArray>()
    value.countLimit = 2000
    return value
}()

extension String {
    var normalizedTokens: [String] {
        if let cached = tokenCache.object(forKey: self as NSString) {
            return cached as! [String]
        }
        var words: [String] = []
        enumerateSubstrings(in: startIndex..<endIndex,
                            options: .byWords) { (substring, substringRange, enclosingRange, stop) in
                                if let substring = substring {
                                    words.append(substring.localizedLowercase)
                                }
        }
        tokenCache.setObject(words as NSArray, forKey: self as NSString)
        return words
    }

    func matchesTableViewSearchQueryTokens(_ queryTokens: [String]) -> Bool {
        if queryTokens.count == 0 {
            return true
        }
        let docTokens = self.normalizedTokens
        if docTokens.count == 0 {
            return true
        }
        if queryTokens.count == 0 {
            return true
        }
        for q in queryTokens {
            var ok = false
            for d in docTokens {
                if d.hasPrefix(q) {
                    ok = true
                    break
                }
            }
            if !ok {
                return false
            }
        }
        return true
    }
}

@objc(BFPMainViewControllerDelegate)
public protocol MainViewControllerDelegate {
    func mainViewController(_ mainViewController: MainViewController,
                            didSelectFontWithName name: String)
}

@objc(BFPMainViewController)
public class MainViewController: NSViewController, NSTextFieldDelegate, TableViewControllerDelegate {
    @IBOutlet public weak var tableView: FontListTableView!
    @IBOutlet public weak var searchField: NSSearchField!
    var desiredWidth: CGFloat {
        tableViewController?.desiredWidth ?? 0.0
    }
    @objc(delegate) @IBOutlet public weak var delegate: MainViewControllerDelegate?
    @objc public var systemFontDataSources: [FontListDataSource] = [SystemFontsDataSource()] {
        didSet {
            tableViewController?.invalidateDataSources()
        }
    }
    private var internalFamilyName: String?
    public var fontFamilyName: String? {
        get {
            return internalFamilyName
        }
        set {
            internalFamilyName = newValue
            tableViewController?.select(name: newValue)
        }
    }
    public var insets: NSEdgeInsets {
        let frame = view.convert(searchField.bounds, from: searchField)
        return NSEdgeInsets(top: NSMaxY(view.bounds) - NSMaxY(frame),
                            left: NSMinX(frame),
                            bottom: 0,
                            right: NSMaxX(view.bounds) - NSMaxX(frame))
    }

    public var tableViewController: TableViewController?

    init() {
        super.init(nibName: "MainViewController", bundle: Bundle(for: MainViewController.self))
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: "MainViewController", bundle: Bundle(for: MainViewController.self))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func awakeFromNib() {
        tableViewController = TableViewController(tableView: tableView, delegate: self)
        if let name = fontFamilyName {
            tableViewController?.select(name: name)
        }
    }

    @objc(controlTextDidChange:)
    public func controlTextDidChange(_ obj: Notification) {
        tableViewController?.filter = searchField.stringValue
    }

    public override func viewWillAppear() {
        view.window?.makeFirstResponder(searchField)
    }
    // Mark:- TableViewControllerDelegate

    func tableViewController(_ tableViewController: TableViewController,
                             didSelectFontWithName name: String) {
        internalFamilyName = name
        delegate?.mainViewController(self, didSelectFontWithName: name)
        view.window?.orderOut(nil)
    }

    func tableViewControllerDataSources(_ tableViewController: TableViewController) -> [FontListDataSource] {
        return systemFontDataSources
    }
}
