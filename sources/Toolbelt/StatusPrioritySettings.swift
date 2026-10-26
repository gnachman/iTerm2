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
    private static let mergeWorkgroupsDefaultsKey = "StatusMergeWorkgroups"
    // Set once a saved list has been given the done and error patterns, so a
    // user who later removes them is not given them back. Synced along with
    // the list it describes: a NoSync flag would be unset on another machine
    // sharing the same prefs folder, which would add the patterns back to the
    // shared list there.
    private static let addedDoneAndErrorDefaultsKey = "StatusPriorityAddedDoneAndError"

    /// Default priority patterns. Matching is a lowercased-substring test
    /// against status text that arrives over the wire protocol, which is
    /// inherently English, so these stay stable English substrings regardless
    /// of the app's UI language. A program waiting on the user comes first,
    /// then one whose finished (or failed) result the user has not seen yet,
    /// then one still working. Idle comes last: nothing there needs the user.
    static let defaultPatterns = ["wait", "done", "error", "work", "idle"]

    /// When enabled, all sessions in a workgroup collapse to a single row in
    /// the Session Status tool. Defaults to off to preserve prior behavior.
    var mergeWorkgroups: Bool {
        get { iTermUserDefaults.userDefaults().bool(forKey: Self.mergeWorkgroupsDefaultsKey) }
        set {
            guard newValue != mergeWorkgroups else {
                return
            }
            iTermUserDefaults.userDefaults().set(newValue, forKey: Self.mergeWorkgroupsDefaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

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
        // Whatever the user saves is already a list that knows about done and
        // error; a pattern missing from it was left out on purpose.
        iTermUserDefaults.userDefaults().set(true, forKey: Self.addedDoneAndErrorDefaultsKey)
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
        let userDefaults = iTermUserDefaults.userDefaults()
        var loaded: [StatusPriorityEntry]?
        if let data = userDefaults.data(forKey: Self.entriesDefaultsKey),
           let saved = try? JSONDecoder().decode([StatusPriorityEntry].self, from: data) {
            loaded = saved
        } else if let saved = userDefaults.stringArray(forKey: Self.defaultsKey) {
            // Migrate legacy string array
            loaded = saved.map { StatusPriorityEntry(pattern: $0) }
        }
        var needsMigration = false
        if let loaded {
            if userDefaults.bool(forKey: Self.addedDoneAndErrorDefaultsKey) {
                entries = loaded
            } else {
                entries = Self.addingDoneAndError(to: loaded)
                needsMigration = true
            }
        } else {
            // Nothing saved, so nothing to migrate and nothing to record: the
            // defaults already include done and error, and save() records the
            // flag along with the first list the user saves.
            entries = Self.defaultPatterns.map { StatusPriorityEntry(pattern: $0) }
        }
        super.init()
        if needsMigration {
            // didSet does not run during init. Write the list directly rather
            // than through save(), whose notification could reach an observer
            // that reads `shared` while it is still being created.
            Self.writeMigratedEntries(entries, to: userDefaults)
        }
    }

    /// Saves a list that has been given done and error, and records that it
    /// was. Reports the change as a migration so a custom settings folder that
    /// still holds the unmigrated list does not count it as an unsaved edit at
    /// quit. Internal for testing.
    static func writeMigratedEntries(_ entries: [StatusPriorityEntry], to userDefaults: UserDefaults) {
        iTermUserDefaults.migrateKeys([entriesDefaultsKey, defaultsKey, addedDoneAndErrorDefaultsKey],
                                      in: userDefaults) {
            if let data = try? JSONEncoder().encode(entries) {
                userDefaults.set(data, forKey: entriesDefaultsKey)
                userDefaults.removeObject(forKey: defaultsKey)
            }
            userDefaults.set(true, forKey: addedDoneAndErrorDefaultsKey)
        }
    }

    /// Lists saved before done and error existed rank those statuses below
    /// everything the user listed. Puts them where the defaults do, just after
    /// whatever matches “waiting” (or first, if nothing does), unless the list
    /// already has a pattern that matches them.
    static func addingDoneAndError(to saved: [StatusPriorityEntry]) -> [StatusPriorityEntry] {
        func index(matching status: String, in entries: [StatusPriorityEntry]) -> Int? {
            return entries.firstIndex { entry in
                let pattern = entry.pattern.lowercased()
                return !pattern.isEmpty && status.contains(pattern)
            }
        }
        // Before done and error existed, a finished or failed turn reported
        // idle, so whoever asked to be notified about that keeps being
        // notified about the same moment under its new name.
        let turnEndNotify = index(matching: "idle", in: saved).map { saved[$0].notify } ?? false
        var result = saved
        var insertionIndex = index(matching: "waiting", in: result).map { $0 + 1 } ?? 0
        for status in ["done", "error"] {
            if index(matching: status, in: result) == nil {
                result.insert(StatusPriorityEntry(pattern: status, notify: turnEndNotify),
                              at: insertionIndex)
                insertionIndex += 1
            } else {
                DLog("Saved status priorities already match \(status)")
            }
        }
        return result
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
        let warning = iTermWarning()
        warning.heading = String(localized: "StatusPriority.NewPatternTitle", defaultValue: "New Priority Pattern", comment: "Title of the new priority pattern dialog")
        warning.title = String(localized: "StatusPriority.NewPatternInfo", defaultValue: "Enter a substring to match against status text (case-insensitive).", comment: "Informative text of the new priority pattern dialog")
        warning.actionLabels = [iTermLocalizedOK(), iTermLocalizedCancel()]
        warning.cancelLabel = iTermLocalizedCancel()
        warning.warningType = .kiTermWarningTypePersistent

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        warning.accessory = textField
        warning.remoteInputs = [.textInput(withIdentifier: "pattern",  // Localization unneeded
                                           label: nil,
                                           textField: textField)]
        warning.initialFirstResponder = textField
        warning.window = window

        warning.runModalAsync { selection, _ in
            guard selection == .kiTermWarningSelection0 else { return }
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
        popover.contentSize = vc.view.frame.size
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: edge)
        self.popover = popover
    }
}

/// Sizes the priority popover to fit its localized titles. English fits the
/// minimum size; longer translations widen the popover, the Notify column, or
/// the instructions. Internal for testing.
struct StatusPriorityPopoverLayout {
    static let minimumWidth: CGFloat = 280
    static let minimumHeight: CGFloat = 322
    static let margin: CGFloat = 10
    static let minimumNotifyColumnWidth: CGFloat = 44
    static let minimumLabelHeight: CGFloat = 48
    // Room a table header cell needs around its text.
    private static let headerPadding: CGFloat = 10

    let width: CGFloat
    let height: CGFloat
    let notifyColumnWidth: CGFloat
    let labelHeight: CGFloat

    init(notifyTitle: String, checkboxTitles: [String], instructions: String) {
        let widestCheckbox = checkboxTitles.map {
            ceil(NSButton(checkboxWithTitle: $0, target: nil, action: nil).fittingSize.width)
        }.max() ?? 0
        width = max(Self.minimumWidth, widestCheckbox + 2 * Self.margin)

        let headerCell = NSTableHeaderCell(textCell: notifyTitle)
        let headerFont = headerCell.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let headerTextWidth = (notifyTitle as NSString).size(withAttributes: [.font: headerFont]).width
        notifyColumnWidth = max(Self.minimumNotifyColumnWidth, ceil(headerTextWidth + Self.headerPadding))

        let label = Self.makeInstructionsLabel(instructions)
        label.preferredMaxLayoutWidth = width - 2 * Self.margin
        labelHeight = max(Self.minimumLabelHeight, ceil(label.fittingSize.height))

        height = Self.minimumHeight + labelHeight - Self.minimumLabelHeight
    }

    static func makeInstructionsLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return label
    }
}

// Internal for testing.
final class StatusPriorityViewController: NSViewController, CRUDTableViewControllerDelegate {
    /// The popover's user-visible titles. Tests pass translations in.
    struct Titles {
        var instructions: String
        var showStatusInTabSubtitle: String
        var mergeWorkgroups: String
        var notify: String

        static var localized: Titles {
            Titles(instructions: String(localized: "StatusPriority.InstructionsLabel", defaultValue: "Statuses are sorted by priority. Items near the top have higher priority. Drag to reorder. Click to edit.", comment: "Instructional label at the top of the status priority settings"),
                   showStatusInTabSubtitle: String(localized: "StatusPriority.ShowStatusInTabSubtitle", defaultValue: "Show status in tab subtitle", comment: "Checkbox to show status in the tab subtitle"),
                   mergeWorkgroups: String(localized: "StatusPriority.MergeWorkgroups", defaultValue: "Merge workgroup statuses", comment: "Checkbox to merge workgroup statuses"),
                   notify: String(localized: "StatusPriority.NotifyColumn", defaultValue: "Notify", comment: "Title of the Notify table column"))
        }
    }

    private let titles: Titles
    private var notifyColumnWidth = StatusPriorityPopoverLayout.minimumNotifyColumnWidth

    init(titles: Titles = .localized) {
        self.titles = titles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

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
        let instructions = titles.instructions
        let subtitleTitle = titles.showStatusInTabSubtitle
        let mergeTitle = titles.mergeWorkgroups
        let notifyTitle = titles.notify
        let layout = StatusPriorityPopoverLayout(notifyTitle: notifyTitle,
                                                 checkboxTitles: [subtitleTitle, mergeTitle],
                                                 instructions: instructions)
        notifyColumnWidth = layout.notifyColumnWidth

        let width = layout.width
        let height = layout.height
        let margin = StatusPriorityPopoverLayout.margin
        let segmentHeight: CGFloat = 24
        let labelHeight = layout.labelHeight
        let toggleHeight: CGFloat = 18
        let toggleGap: CGFloat = 8

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Instructional label at top
        let label = StatusPriorityPopoverLayout.makeInstructionsLabel(instructions)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: margin,
                             y: height - margin - labelHeight,
                             width: width - 2 * margin,
                             height: labelHeight)
        label.autoresizingMask = [.width, .minYMargin]
        container.addSubview(label)

        // Global toggle: gate the status-text subtitle on tabs without
        // affecting the colored dot or this priority list’s meaning.
        // Pinned to the bottom with the other per-popover switch.
        let toggleY = margin
        let toggle = NSButton(checkboxWithTitle: subtitleTitle,
                              target: self,
                              action: #selector(showSubtitleToggleChanged(_:)))
        toggle.state = iTermUserDefaults.showSessionStatusInTabSubtitle ? .on : .off
        toggle.frame = NSRect(x: margin,
                              y: toggleY,
                              width: width - 2 * margin,
                              height: toggleHeight)
        toggle.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(toggle)

        // Merge toggle: collapse each workgroup to a single status row. Sits
        // directly above the subtitle toggle so both per-popover switches are
        // grouped together.
        let mergeToggleY = toggleY + toggleHeight + toggleGap
        let mergeToggle = NSButton(checkboxWithTitle: mergeTitle,
                                   target: self,
                                   action: #selector(mergeWorkgroupsToggleChanged(_:)))
        mergeToggle.state = StatusPrioritySettings.shared.mergeWorkgroups ? .on : .off
        mergeToggle.toolTip = String(localized: "StatusPriority.MergeWorkgroupsTooltip", defaultValue: "When enabled, only the most recent status from each workgroup is shown.", comment: "Tooltip for the merge workgroup statuses checkbox")
        mergeToggle.frame = NSRect(x: margin,
                                   y: mergeToggleY,
                                   width: width - 2 * margin,
                                   height: toggleHeight)
        mergeToggle.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(mergeToggle)

        // +/- segmented control, above the checkboxes and below the table.
        let segmentY = mergeToggleY + toggleHeight + toggleGap
        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "plus", accessibilityDescription: iTermLocalizedAdd())!,
            NSImage(systemSymbolName: "minus", accessibilityDescription: iTermLocalizedRemove())!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.frame = NSRect(x: margin, y: segmentY, width: 60, height: segmentHeight)
        addRemove.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(addRemove)

        // Table view between label and the +/- control
        let scrollY = segmentY + segmentHeight + toggleGap
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
        patternColumn.title = String(localized: "StatusPriority.PatternColumn", defaultValue: "Pattern", comment: "Title of the Pattern table column")
        patternColumn.isEditable = true
        tv.addTableColumn(patternColumn)

        let notifyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Notify"))
        notifyColumn.title = notifyTitle
        notifyColumn.width = notifyColumnWidth
        notifyColumn.minWidth = notifyColumnWidth
        notifyColumn.maxWidth = notifyColumnWidth
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
        let newWidth = scrollView.contentSize.width - notifyColumnWidth - spacing
        patternColumn.width = newWidth
    }

    @objc private func showSubtitleToggleChanged(_ sender: NSButton) {
        iTermUserDefaults.showSessionStatusInTabSubtitle = (sender.state == .on)
    }

    @objc private func mergeWorkgroupsToggleChanged(_ sender: NSButton) {
        StatusPrioritySettings.shared.mergeWorkgroups = (sender.state == .on)
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
