//
//  ToolNamedMarks.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/23.
//

import AppKit

fileprivate let buttonHeight = 23.0

func makeToolbeltButton(imageName: String?, title: String, target: AnyObject, selector: Selector, frame: NSRect) -> NSButton {
    let button = NSButton(frame: NSRect(x: 0.0, y: frame.size.height - buttonHeight, width: frame.width, height: buttonHeight))
    button.setButtonType(.momentaryPushIn)
    if let imageName {
        if #available(macOS 10.16, *) {
            button.image = NSImage.it_image(forSymbolName: imageName, accessibilityDescription: title)
        } else {
            button.image = NSImage(named: imageName)
        }
    } else {
        button.title = title
    }
    button.target = target
    button.action = selector
    if #available(macOS 10.16, *) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown
        button.imagePosition = .imageOnly
    } else {
        button.bezelStyle = .smallSquare
    }
    button.sizeToFit()
    button.autoresizingMask = [.minYMargin]

    return button
}

@objc
class ToolNamedMarks: NSView, ToolbeltTool, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {
    private var scrollView: NSScrollView?
    private var _tableView: NSTableView?
    private var addButton: NSButton?
    private var removeButton: NSButton?
    private var editButton: NSButton?

    private var marks = [VT100ScreenMarkReading]()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        scrollView = NSScrollView.scrollViewWithTableViewForToolbelt(container: self,
                                                                     insets: NSEdgeInsets(),
                                                                     rowHeight: NSTableView.heightForTextCell(using: .it_toolbelt()))

        _tableView = scrollView!.documentView! as? NSTableView
        _tableView!.allowsMultipleSelection = true
        _tableView!.perform(#selector(scrollToEndOfDocument(_:)), with: nil, afterDelay: 0)
        _tableView!.reloadData()
        _tableView!.backgroundColor = .clear

        addButton = makeToolbeltButton(imageName: "plus",
                                       title: "Add",
                                       target: self,
                                       selector: #selector(add(_:)),
                                       frame: frameRect)
        addSubview(addButton!)
        removeButton = makeToolbeltButton(imageName: "minus",
                                          title: "Remove",
                                          target: self,
                                          selector: #selector(remove(_:)),
                                          frame: frameRect)
        addSubview(removeButton!)
        editButton = makeToolbeltButton(imageName: "pencil",
                                        title: "Edit",
                                        target: self,
                                        selector: #selector(edit(_:)),
                                        frame: frameRect)
        addSubview(editButton!)

        relayout()
        updateEnabled()
    }

    static func isDynamic() -> Bool {
        return false
    }
    
    required init!(frame: NSRect, url: URL!, identifier: String!) {
        fatalError()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func shutdown() {
    }

    @objc override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        relayout()
    }

    func updateEnabled() {
        editButton?.isEnabled = _tableView!.selectedRowIndexes.count == 1
        removeButton?.isEnabled = !_tableView!.selectedRowIndexes.isEmpty
    }

    @objc func relayout() {
        var margin = -1.0
        if #available(macOS 10.16, *) {
            margin = 2
        }
        var x = frame.width
        for button in [ addButton!, removeButton!, editButton! ] {
            button.sizeToFit()
            var width = 0.0
            if #available(macOS 10.16, *) {
                width = button.frame.width
            } else {
                width = max(buttonHeight, button.frame.width)
            }
            x -= width + margin
            button.frame = NSRect(x: x, y: frame.height - buttonHeight, width: width, height: buttonHeight)
        }
        let bottomMargin = 4.0
        scrollView!.frame = NSRect(x: 0.0, y: 0.0, width: frame.width, height: frame.height - buttonHeight - bottomMargin)
        let contentSize = self.contentSize()
        _tableView!.frame = NSRect(origin: .zero, size: contentSize)
    }

    @objc func minimumHeight() -> CGFloat {
        return 60.0
    }

    @objc override var isFlipped: Bool { true }

    @objc(setNamedMarks:) func set(marks: [VT100ScreenMarkReading]) {
        self.marks = marks.sorted(by: { lhs, rhs in
            return (lhs.entry?.interval.location ?? 0) < (rhs.entry?.interval.location ?? 0)
        })
        _tableView!.reloadData()
    }

    @objc override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if _tableView!.window?.firstResponder == _tableView! && event.keyCode == kVK_Delete {
            remove(self)
            return true

        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func contentSize() -> NSSize {
        var size = scrollView!.contentSize
        size.height = _tableView!.intrinsicContentSize.height
        return size
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return marks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.newTableCellViewWithTextField(usingIdentifier: "ToolNamedMarks",
                                                           font: NSFont.it_toolbelt(),
                                                           string: marks[row].name ?? "(Unnamed)")
        cell.textField?.isEditable = true
        cell.textField?.delegate = self
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateEnabled()
        let row = _tableView!.selectedRow
        if row == -1 {
            return
        }
        toolWrapper().delegate?.delegate?.toolbeltDidSelect(marks[row])
    }

    @objc func add(_ sender: Any) {
        toolWrapper().delegate?.delegate?.toolbeltAddNamedMark()
    }

    @objc func remove(_ sender: Any) {
        let marks = _tableView!.selectedRowIndexes.map { i -> VT100ScreenMarkReading in return self.marks[i] }
        for mark in marks {
            toolWrapper().delegate?.delegate?.toolbeltRemoveNamedMark(mark)
        }
    }

    @objc func edit(_ sender: Any) {
        let marks = _tableView!.selectedRowIndexes.map { i -> VT100ScreenMarkReading in return self.marks[i] }
        for mark in marks {
            toolWrapper().delegate?.delegate?.toolbeltRenameNamedMark(mark, to: nil)
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard
            let textField = obj.object as? NSTextField,
            let cell = textField.superview as? NSTableCellView,
            let row = _tableView?.row(for: cell) else {
            return
        }
        toolWrapper().delegate?.delegate?.toolbeltRenameNamedMark(marks[row], to: textField.stringValue)
    }
}
