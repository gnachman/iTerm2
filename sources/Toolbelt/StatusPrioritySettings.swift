import Foundation

struct StatusPriorityEntry: Codable, Equatable {
    var pattern: String
    var notify: Bool = false
}

@objc(iTermStatusPrioritySettings)
class StatusPrioritySettings: NSObject {
    @objc static let shared = StatusPrioritySettings()
    static let didChangeNotification = Notification.Name("StatusPrioritySettingsDidChange")

    private static let defaultsKey = "StatusPriorities"
    private static let entriesDefaultsKey = "StatusPriorityEntries"
    private static let defaultPatterns = ["wait", "work", "idle"]

    private(set) var entries: [StatusPriorityEntry] {
        didSet {
            save()
        }
    }

    var patterns: [String] {
        entries.map { $0.pattern }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            iTermUserDefaults.userDefaults().set(data, forKey: Self.entriesDefaultsKey)
        }
        // Remove legacy key on save
        iTermUserDefaults.userDefaults().removeObject(forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Restore entries from an external source (e.g., undo).
    func restoreEntries(_ newEntries: [StatusPriorityEntry]) {
        entries = newEntries
    }

    private override init() {
        // Try new format first
        if let data = iTermUserDefaults.userDefaults().data(forKey: Self.entriesDefaultsKey),
           let saved = try? JSONDecoder().decode([StatusPriorityEntry].self, from: data) {
            entries = saved
        } else if let saved = iTermUserDefaults.userDefaults().stringArray(forKey: Self.defaultsKey) {
            // Migrate legacy string array
            entries = saved.map { StatusPriorityEntry(pattern: $0) }
        } else {
            entries = Self.defaultPatterns.map { StatusPriorityEntry(pattern: $0) }
        }
        super.init()
    }

    /// Priority value for status text that doesn't match any pattern.
    @objc var unmatchedPriority: Int { entries.count }

    /// Returns true if the given status text matches the highest-priority pattern (index 0).
    @objc func isHighestPriority(for statusText: String?) -> Bool {
        return !entries.isEmpty && priority(for: statusText) == 0
    }

    /// Returns priority for the given status text.
    /// Lower numbers = higher priority.
    /// nil statusText gets the lowest priority.
    @objc func priority(for statusText: String?) -> Int {
        guard let statusText, !entries.isEmpty else {
            return entries.count + 1
        }
        let lower = statusText.lowercased()
        for (i, entry) in entries.enumerated() {
            if lower.contains(entry.pattern.lowercased()) {
                return i
            }
        }
        return entries.count
    }

    /// Returns whether a notification should be posted for the given status text.
    @objc func shouldNotify(for statusText: String?) -> Bool {
        guard let statusText else {
            return false
        }
        let lower = statusText.lowercased()
        for entry in entries {
            if lower.contains(entry.pattern.lowercased()) {
                return entry.notify
            }
        }
        return false
    }

    // MARK: - Mutation

    func add(_ pattern: String, at index: Int) {
        var updated = entries
        updated.insert(StatusPriorityEntry(pattern: pattern), at: index)
        entries = updated
    }

    func remove(at indexes: IndexSet) {
        var updated = entries
        for i in indexes.sorted().reversed() {
            updated.remove(at: i)
        }
        entries = updated
    }

    func update(_ pattern: String, at index: Int) {
        var updated = entries
        updated[index].pattern = pattern
        entries = updated
    }

    func setNotify(_ notify: Bool, at index: Int) {
        var updated = entries
        updated[index].notify = notify
        entries = updated
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = entries
        let item = updated.remove(at: sourceIndex)
        updated.insert(item, at: destinationIndex)
        entries = updated
    }
}

// MARK: - Settings Popover

extension StatusPrioritySettings {
    @objc func showSettingsPopover(relativeTo positioningRect: NSRect,
                                   of positioningView: NSView,
                                   preferredEdge edge: NSRectEdge) {
        StatusPriorityPopover.shared.show(relativeTo: positioningRect,
                                          of: positioningView,
                                          preferredEdge: edge)
    }
}

// MARK: - CRUD Support

private struct PriorityRow: CRUDRow {
    var entry: StatusPriorityEntry
    func format(column: Int) -> CRUDFormatted {
        switch column {
        case 0:
            return .string(entry.pattern)
        case 1:
            return .boolean(entry.notify)
        default:
            return .string("")
        }
    }
}

private class PriorityDataProvider: CRUDDataProvider {
    weak var viewController: NSViewController?

    var count: Int { StatusPrioritySettings.shared.entries.count }
    var supportsReorder: Bool { true }
    var supportsInlineEditing: Bool { true }

    subscript(_ index: Int) -> CRUDRow {
        PriorityRow(entry: StatusPrioritySettings.shared.entries[index])
    }

    func delete(_ indexes: IndexSet) {
        StatusPrioritySettings.shared.remove(at: indexes)
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        guard let vc = viewController as? StatusPriorityViewController,
              let window = vc.view.window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "New Priority Pattern"
        alert.informativeText = "Enter a substring to match against status text (case-insensitive)."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let value = textField.stringValue
            guard !value.isEmpty else { return }
            vc.undoableAdd(value, completion: completion)
        }
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        StatusPrioritySettings.shared.reorder(from: sourceIndex, to: destinationIndex)
    }
}

// MARK: - Popover

private final class StatusPriorityPopover: NSObject {
    static let shared = StatusPriorityPopover()

    private var popover: NSPopover?

    func show(relativeTo positioningRect: NSRect,
              of positioningView: NSView,
              preferredEdge edge: NSRectEdge) {
        if let popover, popover.isShown {
            popover.close()
            return
        }
        let vc = StatusPriorityViewController()
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .semitransient
        popover.contentSize = NSSize(width: 280, height: 260)
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: edge)
        self.popover = popover
    }
}

private final class StatusPriorityViewController: NSViewController, CRUDTableViewControllerDelegate {
    static let notifyColumnWidth: CGFloat = 44

    typealias CRUDState = [StatusPriorityEntry]

    private var crudController: CRUDTableViewController<StatusPriorityViewController>?
    private weak var tableView: NSTableView?

    var crudState: CRUDState {
        get { StatusPrioritySettings.shared.entries }
        set {
            StatusPrioritySettings.shared.restoreEntries(newValue)
        }
    }

    override func loadView() {
        let width: CGFloat = 280
        let height: CGFloat = 260
        let margin: CGFloat = 10
        let segmentHeight: CGFloat = 24
        let labelHeight: CGFloat = 48

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Instructional label at top
        let label = NSTextField(wrappingLabelWithString: "Statuses are sorted by priority. Items near the top have higher priority. Drag to reorder. Click to edit.")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: margin,
                             y: height - margin - labelHeight,
                             width: width - 2 * margin,
                             height: labelHeight)
        label.autoresizingMask = [.width, .minYMargin]
        container.addSubview(label)

        // +/- segmented control at bottom
        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
            NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.frame = NSRect(x: margin, y: margin, width: 60, height: segmentHeight)
        addRemove.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(addRemove)

        // Table view between label and segmented control
        let scrollY = margin + segmentHeight + 4
        let scrollHeight = height - margin - labelHeight - 4 - scrollY
        let scrollView = NSScrollView(frame: NSRect(x: margin, y: scrollY,
                                                     width: width - 2 * margin,
                                                     height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let tv = CompetentTableView(frame: scrollView.bounds)
        tv.rowHeight = 20
        tv.columnAutoresizingStyle = .noColumnAutoresizing

        let patternColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Pattern"))
        patternColumn.title = "Pattern"
        patternColumn.isEditable = true
        tv.addTableColumn(patternColumn)

        let notifyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Notify"))
        notifyColumn.title = "Notify"
        notifyColumn.width = StatusPriorityViewController.notifyColumnWidth
        notifyColumn.minWidth = StatusPriorityViewController.notifyColumnWidth
        notifyColumn.maxWidth = StatusPriorityViewController.notifyColumnWidth
        tv.addTableColumn(notifyColumn)

        scrollView.documentView = tv
        self.tableView = tv
        container.addSubview(scrollView)

        let dataProvider = PriorityDataProvider()
        dataProvider.viewController = self
        let schema = CRUDSchema(columns: [CRUDColumn(type: .string),
                                          CRUDColumn(type: .boolean)],
                                dataProvider: dataProvider)
        crudController = CRUDTableViewController(tableView: tv,
                                                  addRemove: addRemove,
                                                  schema: schema)
        crudController?.delegate = self

        self.view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        crudController?.reload()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let tv = tableView, let scrollView = tv.enclosingScrollView else { return }
        let patternColumn = tv.tableColumns[0]
        let spacing = tv.intercellSpacing.width * CGFloat(tv.numberOfColumns)
        let newWidth = scrollView.contentSize.width - Self.notifyColumnWidth - spacing
        patternColumn.width = newWidth
    }

    func undoableAdd(_ value: String, completion: @escaping (Int) -> ()) {
        crudController?.undoable {
            let index = StatusPrioritySettings.shared.entries.count
            StatusPrioritySettings.shared.add(value, at: index)
            completion(index)
        }
    }

    // MARK: - CRUDTableViewControllerDelegate

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                                     selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
        crudController?.undoable {
            StatusPrioritySettings.shared.update(newValue, at: row)
        }
    }

    func crudCheckboxDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                               row: Int,
                               column: Int,
                               newValue: Bool) {
        crudController?.undoable {
            StatusPrioritySettings.shared.setNotify(newValue, at: row)
        }
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                         row: Int,
                         column: Int) {
    }
}
