import Foundation

struct StatusPriorityEntry: Codable, Equatable {
    var pattern: String
    var notify: Bool = false
    // Colors to draw a matching status in instead of the ones the program
    // sent, as sRGB #rrggbb. nil keeps the program's color. Overrides change
    // only how a status is drawn, never what is stored for it.
    var dotColor: String? = nil
    var textColor: String? = nil
}

@objc(iTermStatusPrioritySettings)
class StatusPrioritySettings: NSObject {
    @objc static let shared = StatusPrioritySettings()
    static let didChangeNotification = Notification.Name("StatusPrioritySettingsDidChange")
    /// Posted when a color override changes, as soon as it does (at most once
    /// per pass through the run loop), so what is drawn can follow a color
    /// picker live. didChangeNotification follows later, once the change is
    /// saved.
    static let colorsDidChangeNotification = Notification.Name("StatusPriorityColorsDidChange")

    /// Every notification after which a status may need drawing in different
    /// colors. Any edit to the list can change that, not only a color edit:
    /// undo, deleting or reordering entries, or editing a pattern changes
    /// which entry a status matches first. Observe all of these to keep
    /// colors current.
    @objc static var displayColorsNotificationNames: [NSNotification.Name] {
        [colorsDidChangeNotification, didChangeNotification]
    }

    private static let defaultsKey = "StatusPriorities"
    private static let entriesDefaultsKey = "StatusPriorityEntries"
    private static let mergeWorkgroupsDefaultsKey = "StatusMergeWorkgroups"
    // Set once a saved list has been given the done and error patterns, so a
    // user who later removes them is not given them back. Synced along with
    // the list it describes: a NoSync flag would be unset on another machine
    // sharing the same prefs folder, which would add the patterns back to the
    // shared list there.
    private static let addedDoneAndErrorDefaultsKey = "StatusPriorityAddedDoneAndError"
    // The same for the background pattern, added later on its own so that a
    // list already given done and error still gets it.
    private static let addedBackgroundDefaultsKey = "StatusPriorityAddedBackground"

    /// Default priority patterns. Matching is a lowercased-substring test
    /// against status text that arrives over the wire protocol, which is
    /// inherently English, so these stay stable English substrings regardless
    /// of the app's UI language. A program waiting on the user comes first,
    /// then one whose finished (or failed) result the user has not seen yet,
    /// then one still working, then one whose own turn is over while work it
    /// started keeps running in the background (it will take input, and its
    /// results are still on the way). Idle comes last: nothing there needs the
    /// user.
    static let defaultPatterns = ["wait", "done", "error", "work", "background", "idle"]

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
            if !deferringSave {
                save()
            }
        }
    }

    // A live color picker changes a color on every mouse move. Saving writes
    // a synced key and posts didChangeNotification, which re-sorts the
    // Session Status tool, so color changes are saved once the picking
    // pauses rather than each time.
    private var deferringSave = false
    private var pendingColorSave: Timer?
    private var colorsDidChangePostScheduled = false
    private static let colorSaveDelay: TimeInterval = 0.5

    var patterns: [String] {
        entries.map { $0.pattern }
    }

    private func save() {
        pendingColorSave?.invalidate()
        pendingColorSave = nil
        if let data = try? JSONEncoder().encode(entries) {
            iTermUserDefaults.userDefaults().set(data, forKey: Self.entriesDefaultsKey)
        }
        // Whatever the user saves is already a list that knows about done,
        // error and background; a pattern missing from it was left out on
        // purpose.
        iTermUserDefaults.userDefaults().set(true, forKey: Self.addedDoneAndErrorDefaultsKey)
        iTermUserDefaults.userDefaults().set(true, forKey: Self.addedBackgroundDefaultsKey)
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
            var migrated = loaded
            if !userDefaults.bool(forKey: Self.addedDoneAndErrorDefaultsKey) {
                migrated = Self.addingDoneAndError(to: migrated)
                needsMigration = true
            }
            if !userDefaults.bool(forKey: Self.addedBackgroundDefaultsKey) {
                migrated = Self.addingBackground(to: migrated)
                needsMigration = true
            }
            entries = migrated
        } else {
            // Nothing saved, so nothing to migrate and nothing to record: the
            // defaults already include done, error and background, and save()
            // records the flags along with the first list the user saves.
            entries = Self.defaultPatterns.map { StatusPriorityEntry(pattern: $0) }
        }
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillTerminate(_:)),
                                               name: NSApplication.willTerminateNotification,
                                               object: nil)
        if needsMigration {
            // didSet does not run during init. Write the list directly rather
            // than through save(), whose notification could reach an observer
            // that reads `shared` while it is still being created.
            Self.writeMigratedEntries(entries, to: userDefaults)
        }
    }

    /// Saves a list that has been given done, error and background, and
    /// records that it was. Reports the change as a migration so a custom
    /// settings folder that still holds the unmigrated list does not count it
    /// as an unsaved edit at quit. Internal for testing.
    static func writeMigratedEntries(_ entries: [StatusPriorityEntry], to userDefaults: UserDefaults) {
        iTermUserDefaults.migrateKeys([entriesDefaultsKey, defaultsKey, addedDoneAndErrorDefaultsKey,
                                       addedBackgroundDefaultsKey],
                                      in: userDefaults) {
            if let data = try? JSONEncoder().encode(entries) {
                userDefaults.set(data, forKey: entriesDefaultsKey)
                userDefaults.removeObject(forKey: defaultsKey)
            }
            userDefaults.set(true, forKey: addedDoneAndErrorDefaultsKey)
            userDefaults.set(true, forKey: addedBackgroundDefaultsKey)
        }
    }

    /// The first entry whose pattern matches `status` under the same
    /// lowercased-substring rule priority(for:) applies.
    private static func index(matching status: String, in entries: [StatusPriorityEntry]) -> Int? {
        return entries.firstIndex { entry in
            let pattern = entry.pattern.lowercased()
            return !pattern.isEmpty && status.contains(pattern)
        }
    }

    /// Lists saved before done and error existed rank those statuses below
    /// everything the user listed. Puts them where the defaults do, just after
    /// whatever matches “waiting” (or first, if nothing does), unless the list
    /// already has a pattern that matches them.
    static func addingDoneAndError(to saved: [StatusPriorityEntry]) -> [StatusPriorityEntry] {
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

    /// Lists saved before the background status existed rank it below
    /// everything the user listed. Puts it where the defaults do, just after
    /// whatever matches “working”, or else just before whatever matches
    /// “idle”, or else last, unless the list already has a pattern that
    /// matches it. It does not notify: until it existed this moment was still
    /// “working”, which changed nothing anyone could be notified about.
    static func addingBackground(to saved: [StatusPriorityEntry]) -> [StatusPriorityEntry] {
        guard index(matching: "background", in: saved) == nil else {
            DLog("Saved status priorities already match background")
            return saved
        }
        let insertionIndex = index(matching: "working", in: saved).map { $0 + 1 }
            ?? index(matching: "idle", in: saved)
            ?? saved.count
        var result = saved
        result.insert(StatusPriorityEntry(pattern: "background"), at: insertionIndex)
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

    /// The first entry whose pattern matches the status text, under the same
    /// lowercased-substring rule as priority(for:).
    private func entry(matching statusText: String?) -> StatusPriorityEntry? {
        guard let statusText else {
            return nil
        }
        let lower = statusText.lowercased()
        return entries.first { entry in
            let pattern = entry.pattern.lowercased()
            return !pattern.isEmpty && lower.contains(pattern)
        }
    }

    /// The dot color the user chose for statuses like this one, or nil to
    /// draw the color the program sent. Only the first matching entry counts,
    /// so a status that matches an entry without a color is not colored by a
    /// later entry.
    func dotColorOverride(for statusText: String?) -> iTermSRGBColor? {
        return entry(matching: statusText)?.dotColor.flatMap(Self.srgbColor(hex:))
    }

    /// The status text color the user chose for statuses like this one, or
    /// nil to draw the color the program sent.
    func textColorOverride(for statusText: String?) -> iTermSRGBColor? {
        return entry(matching: statusText)?.textColor.flatMap(Self.srgbColor(hex:))
    }

    /// Parses #rrggbb. Internal for testing.
    static func srgbColor(hex: String) -> iTermSRGBColor? {
        guard hex.hasPrefix("#"), hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        return iTermSRGBColor(r: Double((value >> 16) & 0xff) / 255.0,
                              g: Double((value >> 8) & 0xff) / 255.0,
                              b: Double(value & 0xff) / 255.0)
    }

    /// Formats a color as sRGB #rrggbb, or nil for no color. Internal for
    /// testing.
    static func hexString(_ color: NSColor?) -> String? {
        guard let srgb = color?.usingColorSpace(.sRGB) else {
            return nil
        }
        func component(_ value: CGFloat) -> Int {
            return Int((min(1, max(0, value)) * 255).rounded())
        }
        // Localization unneeded
        return String(format: "#%02x%02x%02x",
                      component(srgb.redComponent),
                      component(srgb.greenComponent),
                      component(srgb.blueComponent))
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

    func setDotColor(_ color: String?, at index: Int) {
        updateColors { $0[index].dotColor = color }
    }

    func setTextColor(_ color: String?, at index: Int) {
        updateColors { $0[index].textColor = color }
    }

    /// Writes a color change the save of which is still pending. Internal for
    /// testing.
    func flushPendingColorSave() {
        guard pendingColorSave != nil else {
            return
        }
        save()
    }

    private func updateColors(_ mutate: (inout [StatusPriorityEntry]) -> ()) {
        var updated = entries
        mutate(&updated)
        guard updated != entries else {
            return
        }
        deferringSave = true
        entries = updated
        deferringSave = false

        pendingColorSave?.invalidate()
        pendingColorSave = Timer.scheduledTimer(withTimeInterval: Self.colorSaveDelay,
                                                repeats: false) { [weak self] _ in
            self?.flushPendingColorSave()
        }
        guard !colorsDidChangePostScheduled else {
            return
        }
        colorsDidChangePostScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            colorsDidChangePostScheduled = false
            NotificationCenter.default.post(name: Self.colorsDidChangeNotification, object: self)
        }
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        flushPendingColorSave()
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
        case 2:
            return .color(Self.color(entry.dotColor))
        case 3:
            return .color(Self.color(entry.textColor))
        default:
            return .string("")
        }
    }

    private static func color(_ hex: String?) -> NSColor? {
        guard let srgb = hex.flatMap(StatusPrioritySettings.srgbColor(hex:)) else {
            return nil
        }
        return NSColor(srgbRed: srgb.r, green: srgb.g, blue: srgb.b, alpha: 1)
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
/// minimum size; longer translations widen the popover, the fixed-width
/// columns, or the instructions. Internal for testing.
struct StatusPriorityPopoverLayout {
    static let minimumWidth: CGFloat = 320
    static let minimumHeight: CGFloat = 322
    static let margin: CGFloat = 10
    static let minimumNotifyColumnWidth: CGFloat = 44
    static let minimumColorColumnWidth: CGFloat = 36
    static let minimumPatternColumnWidth: CGFloat = 120
    static let minimumLabelHeight: CGFloat = 48
    // Room a table header cell needs around its text.
    private static let headerPadding: CGFloat = 10
    // Generous allowance for the table's intercell spacing and scroller.
    private static let tableChrome: CGFloat = 24

    let width: CGFloat
    let height: CGFloat
    let notifyColumnWidth: CGFloat
    let colorColumnWidths: [CGFloat]
    let labelHeight: CGFloat

    /// The fixed-width columns' total, which is what the pattern column
    /// does not get.
    var fixedColumnsWidth: CGFloat {
        notifyColumnWidth + colorColumnWidths.reduce(0, +)
    }

    init(notifyTitle: String, colorTitles: [String], checkboxTitles: [String], instructions: String) {
        let widestCheckbox = checkboxTitles.map {
            ceil(NSButton(checkboxWithTitle: $0, target: nil, action: nil).fittingSize.width)
        }.max() ?? 0

        notifyColumnWidth = max(Self.minimumNotifyColumnWidth, Self.headerWidth(notifyTitle))
        colorColumnWidths = colorTitles.map {
            max(Self.minimumColorColumnWidth, Self.headerWidth($0))
        }
        let columnsWidth = Self.minimumPatternColumnWidth + notifyColumnWidth +
            colorColumnWidths.reduce(0, +) + Self.tableChrome
        width = max(Self.minimumWidth,
                    widestCheckbox + 2 * Self.margin,
                    ceil(columnsWidth + 2 * Self.margin))

        let label = Self.makeInstructionsLabel(instructions)
        label.preferredMaxLayoutWidth = width - 2 * Self.margin
        labelHeight = max(Self.minimumLabelHeight, ceil(label.fittingSize.height))

        height = Self.minimumHeight + labelHeight - Self.minimumLabelHeight
    }

    private static func headerWidth(_ title: String) -> CGFloat {
        let headerCell = NSTableHeaderCell(textCell: title)
        let headerFont = headerCell.font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let textWidth = (title as NSString).size(withAttributes: [.font: headerFont]).width
        return ceil(textWidth + headerPadding)
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
        var showStatusOnTabs: String
        var mergeWorkgroups: String
        var notify: String
        var dotColor: String
        var textColor: String

        static var localized: Titles {
            Titles(instructions: String(localized: "StatusPriority.InstructionsLabel", defaultValue: "Statuses are sorted by priority. Items near the top have higher priority. Drag to reorder. Click to edit.", comment: "Instructional label at the top of the status priority settings"),
                   showStatusOnTabs: String(localized: "StatusPriority.ShowStatusOnTabs", defaultValue: "Show status on tabs", comment: "Checkbox in the Session Status settings popover. When on, a session’s status appears on its tab, both as a colored dot and as text in the tab subtitle."),
                   mergeWorkgroups: String(localized: "StatusPriority.MergeWorkgroups", defaultValue: "Merge workgroup statuses", comment: "Checkbox to merge workgroup statuses"),
                   notify: String(localized: "StatusPriority.NotifyColumn", defaultValue: "Notify", comment: "Title of the Notify table column"),
                   dotColor: String(localized: "StatusPriority.DotColorColumn", defaultValue: "Dot", comment: "Title of a table column of color wells in the Session Status settings popover. Each well sets the color of the dot drawn next to a status that matches the row’s pattern, in place of the color the program sent. Keep it short: the column is narrow."),
                   textColor: String(localized: "StatusPriority.TextColorColumn", defaultValue: "Text", comment: "Title of a table column of color wells in the Session Status settings popover. Each well sets the color of the status text for a status that matches the row’s pattern, in place of the color the program sent. Keep it short: the column is narrow."))
        }
    }

    private let titles: Titles
    private var fixedColumnsWidth = StatusPriorityPopoverLayout.minimumNotifyColumnWidth

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
        let subtitleTitle = titles.showStatusOnTabs
        let mergeTitle = titles.mergeWorkgroups
        let notifyTitle = titles.notify
        let colorTitles = [titles.dotColor, titles.textColor]
        let layout = StatusPriorityPopoverLayout(notifyTitle: notifyTitle,
                                                 colorTitles: colorTitles,
                                                 checkboxTitles: [subtitleTitle, mergeTitle],
                                                 instructions: instructions)
        let notifyColumnWidth = layout.notifyColumnWidth
        fixedColumnsWidth = layout.fixedColumnsWidth

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

        // Global toggle: gate everything status draws on tabs (the subtitle
        // text, its tint, and the colored dot) without affecting this
        // priority list’s meaning.
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

        let colorTooltips = [
            String(localized: "StatusPriority.DotColorTooltip", defaultValue: "Color of the dot for statuses that match this pattern. Leave it empty to use the color the program chose.", comment: "Tooltip for the Dot column of color wells in the Session Status settings popover"),
            String(localized: "StatusPriority.TextColorTooltip", defaultValue: "Color of the status text for statuses that match this pattern. Leave it empty to use the color the program chose.", comment: "Tooltip for the Text column of color wells in the Session Status settings popover")
        ]
        // Localization unneeded
        let colorIdentifiers = ["DotColor", "TextColor"]
        for i in 0..<colorTitles.count {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(colorIdentifiers[i]))
            column.title = colorTitles[i]
            column.headerToolTip = colorTooltips[i]
            column.width = layout.colorColumnWidths[i]
            column.minWidth = layout.colorColumnWidths[i]
            column.maxWidth = layout.colorColumnWidths[i]
            tv.addTableColumn(column)
        }

        scrollView.documentView = tv
        self.tableView = tv
        container.addSubview(scrollView)

        let dataProvider = PriorityDataProvider()
        dataProvider.viewController = self
        let schema = CRUDSchema(columns: [CRUDColumn(type: .string),
                                          CRUDColumn(type: .boolean),
                                          CRUDColumn(type: .color),
                                          CRUDColumn(type: .color)],
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

    override func viewWillDisappear() {
        super.viewWillDisappear()
        StatusPrioritySettings.shared.flushPendingColorSave()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let tv = tableView, let scrollView = tv.enclosingScrollView else { return }
        let patternColumn = tv.tableColumns[0]
        let spacing = tv.intercellSpacing.width * CGFloat(tv.numberOfColumns)
        let newWidth = scrollView.contentSize.width - fixedColumnsWidth - spacing
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

    func crudColorDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                            row: Int,
                            column: Int,
                            newValue: NSColor?) {
        let hex = StatusPrioritySettings.hexString(newValue)
        crudController?.undoable {
            if column == 2 {
                StatusPrioritySettings.shared.setDotColor(hex, at: row)
            } else {
                StatusPrioritySettings.shared.setTextColor(hex, at: row)
            }
        }
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                         row: Int,
                         column: Int) {
    }
}
