//
//  SSHWindowController.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/6/22.
//

import Foundation

@objc
class SSHWindowController: NSWindowController {
    class FolderInfo: Codable {
        let name: String
        var children: [Box] = []

        init(_ name: String) {
            self.name = name
        }
    }

    class ConfigurationInfo: Codable {
        struct Fields: Codable {
            var hostname: String
            var port: Int
            var username: String
            var password: String
            var options: String
            var profileGUID: String
        }
        private var fields: Fields
        var hostname: String {
            get { return fields.hostname }
            set { fields.hostname = newValue }
        }
        var port: Int {
            get { return fields.port }
            set { fields.port = newValue }
        }
        var username: String {
            get { return fields.username }
            set { fields.username = newValue }
        }
        var password: String {
            get { return fields.password }
            set { fields.password = newValue }
        }
        var options: String {
            get { return fields.options }
            set { fields.options = newValue }
        }
        var profileGUID: String {
            get { return fields.profileGUID }
            set { fields.profileGUID = newValue }
        }
        init(_ fields: Fields) {
            self.fields = fields
        }
    }

    enum Entry: Codable {
        case folder(FolderInfo)
        case configuration(ConfigurationInfo)

        var numberOfChildren: Int {
            switch self {
            case .configuration(_):
                return 0
            case .folder(let info):
                return info.children.count
            }
        }

        func child(at i: Int) -> Box {
            switch self {
            case .configuration(_):
                fatalError()
            case .folder(let info):
                return info.children[i]
            }
        }

        var displayString: String {
            switch self {
            case .configuration(let info):
                return info.hostname
            case .folder(let info):
                return info.name
            }
        }

        var toolTip: String {
            switch self {
            case .configuration(let info):
                return "\(info.username)@\(info.hostname):\(info.port)"
            case .folder(_):
                return ""
            }
        }

        var isFolder: Bool {
            switch self {
            case .folder(_):
                return true
            case .configuration(_):
                return false
            }
        }

        var isConfiguration: Bool {
            switch self {
            case .folder(_):
                return false
            case .configuration(_):
                return true
            }
        }

        var configurationInfo: ConfigurationInfo? {
            switch self {
            case .folder(_):
                return nil
            case .configuration(let info):
                return info
            }
        }

        var folderInfo: FolderInfo? {
            switch self {
            case .folder(let info):
                return info
            case .configuration(_):
                return nil
            }
        }
    }

    @objc
    class Box: NSObject, Codable {
        let entry: Entry
        init(_ entry: Entry) {
            self.entry = entry
        }
    }

    @objc static let instance = SSHWindowController(windowNibName: "SSHWindowController")
    @IBOutlet var outlineView: NSOutlineView!
    @IBOutlet var detailContainerView: NSView!
    @IBOutlet var hostnameTextField: NSTextField!
    @IBOutlet var portTextField: NSTextField!
    @IBOutlet var usernameTextField: NSTextField!
    @IBOutlet var passwordTextField: NSSecureTextField!
    @IBOutlet var optionsTextField: NSTextField!
    @IBOutlet var profileListView: ProfileListView!
    @IBOutlet var profileListViewBlock: NSView!
    @IBOutlet var removeButton: NSButton!
    @IBOutlet var addFolder: NSButton!
    @IBOutlet var addButton: NSButton!
    private var topLevelEntries: [Box] = []

    private static let userDefaultsKey = "SSH"

    override func awakeFromNib() {
        let decoder = JSONDecoder()
        if let json = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let data = json.data(using: .utf8),
           let entries = try? decoder.decode([Entry].self, from: data) {
            topLevelEntries = entries.map { Box($0) }
        } else {
            topLevelEntries = []
        }
        update()
    }

    private func box(atRow row: Int) -> Box {
        return outlineView.item(atRow: row) as! Box
    }

    func update() {
        let enableDetail: Bool
        let indexes = outlineView.selectedRowIndexes
        if indexes.count == 0 {
            enableDetail = false
        } else {
            enableDetail = indexes.allSatisfy {
                box(atRow: $0).entry.isConfiguration
            }
        }
        addFolder.isEnabled = (indexes.count <= 1)
        addButton.isEnabled = (indexes.count <= 1)
        if enableDetail {
            let configurations = indexes.map { box(atRow: $0).entry.configurationInfo! }
            let hostnames = Set(configurations.map { $0.hostname })
            let passwords = Set(configurations.map { $0.password })
            let ports = Set(configurations.map { String($0.port) })
            let usernames = Set(configurations.map { $0.username })
            let options = Set(configurations.map { $0.options })
            let profileGUIDs = Set(configurations.map { $0.profileGUID })
            let tuples: [(Set<String>, NSTextField)] = [(hostnames, hostnameTextField),
                                                        (passwords, passwordTextField),
                                                        (ports, portTextField),
                                                        (usernames, usernameTextField),
                                                        (options, optionsTextField)]
            for tuple in tuples {
                let (values, field) = tuple
                if values.count == 1 {
                    field.stringValue = values.first!
                    field.placeholderString = ""
                } else {
                    field.stringValue = ""
                    field.placeholderString = "Multiple Values"
                }
                field.isEnabled = true
            }
            if profileGUIDs.count != 1 {
                profileListView.deselectAll()
            } else {
                profileListView.selectRow(byGuid: profileGUIDs.first!)
            }
        } else {
            for view in [hostnameTextField, portTextField, usernameTextField, passwordTextField, optionsTextField] {
                view?.stringValue = ""
            }
            profileListView.deselectAll()
        }
        detailContainerView.alphaValue = enableDetail ? 1.0 : 0.5
        for view in [hostnameTextField, portTextField, usernameTextField, passwordTextField, optionsTextField] {
            view?.isEnabled = enableDetail
        }
        profileListViewBlock.isHidden = !enableDetail
        removeButton.isEnabled = outlineView.selectedRowIndexes.count > 0
    }

    @discardableResult
    private func add(entry entryToAdd: Entry) -> Any {
        let newBox = Box(entryToAdd)
        let indexes = outlineView.selectedRowIndexes
        outlineView.beginUpdates()
        defer {
            outlineView.endUpdates()
        }
        if let index = indexes.first {
            // There was a selection
            let selectedBox = box(atRow: index)
            let selectedEntry = selectedBox.entry
            if selectedEntry.isFolder && outlineView.isItemExpanded(selectedBox) {
                // An expanded folder was selected. Add a child at its first location.
                let folder = selectedEntry.folderInfo!
                folder.children.insert(newBox, at: 0)
                outlineView.insertItems(at: IndexSet(integer: 0), inParent: selectedBox)
                return newBox
            }
            if let anyParent = outlineView.parent(forItem: outlineView.item(atRow: index)) as? Box {
                // selectedEntry has a parent.
                let parent = anyParent.entry
                let i = outlineView.childIndex(forItem: selectedBox)
                parent.folderInfo!.children.insert(newBox, at: i + 1)
                outlineView.insertItems(at: IndexSet(integer: i + 1), inParent: anyParent)
                return outlineView.child(i + 1, ofItem: anyParent)!
            }
            // selectedEntry does not have a parent so it must be top-level.
            let i = outlineView.childIndex(forItem: selectedBox)
            topLevelEntries.insert(newBox, at: i + 1)
            outlineView.insertItems(at: IndexSet(integer: i + 1), inParent: nil)
            return outlineView.child(i + 1, ofItem: nil)!
        }
        // There was no selection. Add to the end.
        topLevelEntries.append(newBox)
        outlineView.insertItems(at: IndexSet(integer: topLevelEntries.count - 1), inParent: nil)
        return outlineView.child(topLevelEntries.count - 1, ofItem: nil)!
    }

    @IBAction
    @objc func newFolder(_ sender: AnyObject) {
        let item = Entry.folder(FolderInfo("Untitled"))
        let anyItem = add(entry: item)
        outlineView.expandItem(anyItem)
    }

    @IBAction
    @objc func add(_ sender: AnyObject) {
        let newEntry = Entry.configuration(
            ConfigurationInfo(
                ConfigurationInfo.Fields(hostname: "Hostname",
                                         port: 22,
                                         username: NSUserName(),
                                         password: "",
                                         options: "",
                                         profileGUID: "")))
        add(entry: newEntry)
        update()
    }

    private func remove(at itemIndex: Int) {
        guard let anyItem = outlineView.item(atRow: itemIndex) else {
            return
        }
        let childIndex = outlineView.childIndex(forItem: anyItem)
        if let parent = (outlineView.parent(forItem: anyItem) as? Box)?.entry {
            // Item has a parent
            parent.folderInfo!.children.remove(at: childIndex)
            outlineView.removeItems(at: IndexSet(integer: childIndex), inParent: parent)
        } else {
            // Item does not have a parent
            topLevelEntries.remove(at: childIndex)
            outlineView.removeItems(at: IndexSet(integer: childIndex), inParent: nil)
        }
    }
    @IBAction
    @objc func remove(_ sender: AnyObject) {
        outlineView.beginUpdates()
        for index in outlineView.selectedRowIndexes.reversed() {
            remove(at: index)
        }
        outlineView.endUpdates()
        update()
    }
}

extension SSHWindowController: NSTextFieldDelegate {
    private func mutateConfigurations(_ closure: (ConfigurationInfo) -> ()) {
        for index in outlineView.selectedRowIndexes {
            guard let item = outlineView.item(atRow: index) as? Box else {
                continue
            }
            guard let info = item.entry.configurationInfo else {
                continue
            }
            closure(info)
        }
    }

    @IBAction
    @objc func controlTextDidChange(_ obj: Notification) {
        guard let sender = obj.object as? NSTextField else {
            return
        }
        let value = sender.stringValue
        if (sender === hostnameTextField) {
            mutateConfigurations {
                $0.hostname = value
            }
            outlineView.beginUpdates()
            outlineView.reloadData(forRowIndexes: outlineView.selectedRowIndexes,
                                   columnIndexes: IndexSet(integer: 0))
            outlineView.endUpdates()
        } else if (sender === portTextField) {
            mutateConfigurations {
                $0.port = Int(value) ?? $0.port
            }
        } else if (sender === usernameTextField) {
            mutateConfigurations {
                $0.username = value
            }
        } else if (sender === passwordTextField) {
            mutateConfigurations {
                $0.password = value
            }
        } else if (sender === optionsTextField) {
            mutateConfigurations {
                $0.options = value
            }
        }
        update()
    }
}

extension SSHWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn:
                     NSTableColumn?,
                     item: Any) -> NSView? {
        NSLog("viewForItem \(String(describing: item))")
        guard let entry = (item as? Box)?.entry else {
            return  nil
        }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return CellView.with(string: entry.displayString,
                             font: font,
                             from: outlineView,
                             owner: self)
    }

    func outlineView(_ outlineView: NSOutlineView,
                     toolTipFor cell: NSCell,
                     rect: NSRectPointer,
                     tableColumn: NSTableColumn?,
                     item: Any,
                     mouseLocation: NSPoint) -> String {
        return (item as? Box)?.entry.toolTip ?? ""
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        update()
    }

    func outlineView(_ outlineView: NSOutlineView, shouldEdit tableColumn: NSTableColumn?, item: Any) -> Bool {
        return true
    }
}

extension SSHWindowController: NSOutlineViewDataSource {
    static let pasteboardType = NSPasteboard.PasteboardType("SSHWindowControllerEntry")

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        NSLog("numberOfChildrenOfItem \(String(describing: item))")
        if item == nil {
            return topLevelEntries.count
        }
        return (item as! Box).entry.numberOfChildren
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return topLevelEntries[index]
        }
        return (item as! Box).entry.child(at: index)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return (item as? Box)?.entry.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let entry = (item as? Box)?.entry else {
            return nil
        }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(entry) else {
            return nil
        }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: Self.pasteboardType)
        return pasteboardItem
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {

    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {

    }


    func outlineView(_ outlineView: NSOutlineView, writeItems items: [Any], to pasteboard: NSPasteboard) -> Bool {
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, updateDraggingItemsForDrag draggingInfo: NSDraggingInfo) {

    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        return false
    }
}

extension SSHWindowController {
    class CellView: NSTableCellView {
        private static let identifier = NSUserInterfaceItemIdentifier(
            rawValue: "SSHWindowController.CellView")
        static func with(string: String,
                         font: NSFont,
                         from outlineView: NSOutlineView,
                         owner: Any) -> CellView {
            let cached = outlineView.makeView(withIdentifier: Self.identifier,
                                              owner: owner) as? CellView
            let view = cached ?? create(font)
            view.textField?.stringValue = string
            view.layoutSubviews()
            return view
        }

        override func resizeSubviews(withOldSize oldSize: NSSize) {
            layoutSubviews()
        }

        private static func create(_ font: NSFont) -> CellView {
            let view = CellView()
            view.autoresizesSubviews = false

            let textField = NSTextField.newLabelStyled()
            textField.font = font
            view.textField = textField
            view.addSubview(textField)
            textField.frame = view.bounds
            textField.isEditable = true

            return view
        }

        private func layoutSubviews() {
            guard let textField = textField else {
                return
            }
            textField.sizeToFit()
            let width = max(textField.bounds.width, bounds.width)
            let leftInset = CGFloat(0)
            let topInset = CGFloat(-2)
            textField.frame = NSRect(x: leftInset,
                                     y: topInset,
                                     width: width,
                                     height: textField.frame.height + 4)
        }
    }
}
