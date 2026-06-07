//
//  CockpitWindowController.swift
//  iTerm2SharedARC
//

import AppKit

// Floating session-status panel for users running many concurrent
// Claude Code sessions. Hosts an outline view of all CC sessions
// across windows. Loaded from Cockpit.xib.
//
// IB wiring required (set in Cockpit.xib):
//   - File's Owner custom class -> iTermCockpitWindowController
//   - File's Owner "window" outlet -> the panel
//   - The @IBOutlet/@IBAction connections below
//
// Window semantics match the global-search panel: a normal NSPanel
// at NSFloatingWindowLevel, becomesKeyOnlyIfNeeded, hidesOnDeactivate.
// That gives a calm floater that stays above iTerm2 windows while
// iTerm2 is foremost but disappears when another app takes over,
// instead of overlapping everything across the system. We do NOT
// use isFloatingPanel or the nonactivatingPanel styleMask; both
// turn the cockpit into a system-wide always-on-top overlay.
@objc(iTermCockpitWindowController)
class CockpitWindowController: NSWindowController {

    // One cockpit per app instance. Lazy: loads the nib the first
    // time someone calls show().
    @objc static let shared = CockpitWindowController()

    @IBOutlet private var outlineView: NSOutlineView!
    @IBOutlet private var settingsToolbarItem: NSToolbarItem!
    @IBOutlet private var searchToolbarItem: NSSearchToolbarItem!
    @IBOutlet private var groupModeToolbarItem: NSToolbarItem!

    // How rows are organized at the top of the outline. Persisted in
    // NoSync user defaults so a relaunch comes back in the same mode
    // the user left it in.
    private var groupMode: CockpitGroupMode = CockpitGroupMode.loadPersisted() {
        didSet {
            if oldValue == groupMode { return }
            CockpitGroupMode.persist(groupMode)
            scheduleRefresh()
        }
    }

    // Empty = no filter, show the grouped tree as built. Non-empty =
    // post-rebuild prune: keep only session leaves whose title contains
    // the filter (case-insensitive), drop intermediate rows that no
    // longer have any matching descendant. Keeps the structure the user
    // chose (group mode), just narrower.
    private var filter: String = ""

    // Live tree built from iTermController + session state. Rebuilt
    // by refresh(); the cache below keeps CockpitRow instances stable
    // across rebuilds so NSOutlineView's pointer-identity-based row
    // tracking (expansion, selection) survives.
    private var rootRows: [CockpitRow] = []
    private var rowCache: [CockpitRow.Identity: CockpitRow] = [:]

    // Coalesces a burst of notifications into a single refresh on the
    // next runloop tick. Without this, opening a window that creates
    // several sessions and posts a tabStatus update each would trigger
    // N back-to-back reloadData() calls.
    private var refreshScheduled = false

    private convenience init() {
        self.init(windowNibName: "Cockpit")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        configurePanel()
        configureToolbar()
        configureGroupModeToolbarItem()
        configureOutlineView()
        configureSearch()
        registerForLiveUpdates()
        // First-time bootstrap. oldShape is empty (rootRows is empty),
        // so every window/group/session flows through applyDiff as an
        // insert and autoExpandNewlyAddedItems opens the new subtrees.
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configurePanel() {
        guard let panel = window as? NSPanel else {
            DLog("Cockpit: window is not an NSPanel; check Cockpit.xib custom class")
            return
        }
        // Mirror iTermGlobalSearchWindowController: float above iTerm2
        // windows but only while iTerm2 is the active app, and stay out
        // of the user's way the rest of the time. hidesOnDeactivate is
        // what stops the panel from overlapping unrelated apps.
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
    }

    private func configureToolbar() {
        if #available(macOS 11.0, *) {
            window?.toolbarStyle = .unifiedCompact
        }
    }

    private func configureOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        // Source-list convention: a single click on a leaf reveals the
        // backing entity (Finder sidebar style). NSTableView fires
        // action for the first click of a double-click too, so wiring
        // doubleAction here would invoke reveal twice on a double-click.
        outlineView.action = #selector(rowClicked(_:))
        outlineView.headerView = nil
        // Defensive: isGroupItem returns false for every row today, so
        // there are no group rows to float, but if a future change
        // re-introduces source-list group items we don't want the
        // first one to render as a pinned floating header (which
        // shows a different background and looks inconsistent).
        outlineView.floatsGroupRows = false
    }

    private func configureGroupModeToolbarItem() {
        // Built in code so we can attach a real NSSegmentedControl to a
        // toolbar item that was reserved as a placeholder in the XIB.
        // Doing it in the XIB would mean hand-authoring nested
        // <segmentedControl> XML inside <toolbarItem>, which Interface
        // Builder is fussy about; this is shorter and easier to evolve.
        // The toolbar item's min/maxSize are set in the XIB; we just
        // need the control to fit inside that reserved space.
        let segmented = NSSegmentedControl()
        segmented.segmentCount = CockpitGroupMode.allCases.count
        segmented.trackingMode = .selectOne
        segmented.target = self
        segmented.action = #selector(groupModeChanged(_:))
        segmented.controlSize = .small
        segmented.segmentStyle = .rounded
        for (idx, mode) in CockpitGroupMode.allCases.enumerated() {
            // Prefer the SF Symbol icon. Fall back to the short text
            // label only if the symbol can't be resolved on this OS,
            // so the segment never renders empty.
            if let image = NSImage(systemSymbolName: mode.symbolName,
                                    accessibilityDescription: mode.tooltip) {
                segmented.setImage(image, forSegment: idx)
            } else {
                segmented.setLabel(mode.shortLabel, forSegment: idx)
            }
            segmented.setToolTip(mode.tooltip, forSegment: idx)
        }
        segmented.selectedSegment = groupMode.rawValue
        segmented.sizeToFit()
        groupModeToolbarItem.view = segmented
    }

    private func configureSearch() {
        let field = searchToolbarItem.searchField
        field.delegate = self
        field.sendsSearchStringImmediately = true
        // macOS 26 (Tahoe) inflated NSSearchField's intrinsic content
        // size for the new chrome, which drags the toolbar (and title
        // bar) taller than other items and leaves the placeholder
        // vertically off-center. Forcing controlSize = .small on both
        // the field and its cell asks AppKit for the smaller intrinsic
        // variant, which matches the unifiedCompact toolbar height.
        field.controlSize = .small
        (field.cell as? NSSearchFieldCell)?.controlSize = .small
    }

    // MARK: - Public API

    @objc func show() {
        // Touching .window triggers lazy nib load via the getter.
        window?.orderFront(nil)
    }

    // For the global "summon panel and start typing" hotkey we
    // discussed. Brings the panel to front, makes it key, focuses
    // the search field.
    @objc func showAndFocusSearch() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchToolbarItem.searchField)
    }

    // MARK: - Toolbar actions

    @IBAction func showSettings(_ sender: Any?) {
        // TODO: open the Session Status tool's settings popover,
        // anchored to the Settings toolbar item's button view.
        DLog("Cockpit: showSettings tapped (not yet implemented)")
    }

    @IBAction func groupModeChanged(_ sender: Any?) {
        guard let segmented = sender as? NSSegmentedControl,
              let mode = CockpitGroupMode(rawValue: segmented.selectedSegment) else {
            return
        }
        groupMode = mode
    }

    // MARK: - Selection

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? CockpitRow else {
            return
        }
        switch item.kind {
        case .session(let sessionGUID):
            jumpToSession(guid: sessionGUID)
        case .window(let windowGuid):
            jumpToWindow(guid: windowGuid)
        case .tab(let uniqueId):
            jumpToTab(uniqueId: uniqueId)
        case .workgroup(let id):
            jumpToWorkgroup(id: id)
        case .group, .buriedRoot:
            return
        }
    }

    private func jumpToSession(guid: String) {
        // anySession(withGUID:) reaches buried sessions *and* workgroup
        // peers via the peer-port fallback. PTYSession.reveal handles
        // peer activation internally (swaps the peer into its tab via
        // peerPort.activate), so we don't have to disambiguate active
        // vs inactive peers here. revealSession(withGUID:) on the
        // controller would miss inactive peers entirely.
        guard let session = iTermController.sharedInstance()?.anySession(withGUID: guid) else {
            return
        }
        session.reveal()
    }

    // Bring a window to the foreground without changing the active
    // tab within it. Implemented by revealing whichever session is
    // currently active in that window — reveal() routes through the
    // window controller's makeKeyAndOrderFront path and doesn't touch
    // the selected tab when the chosen session is already in it.
    private func jumpToWindow(guid: String) {
        guard let terminal = terminal(forGuid: guid),
              let session = terminal.currentTab()?.activeSession
                ?? terminal.allSessions().first else {
            return
        }
        session.reveal()
    }

    // Switch to a tab by uniqueId and bring its window forward. Same
    // reveal-an-anchor-session pattern as jumpToWindow.
    private func jumpToTab(uniqueId: Int) {
        guard let controller = iTermController.sharedInstance() else { return }
        for terminal in controller.terminals() {
            if let tab = terminal.tab(withUniqueId: Int32(uniqueId)) {
                let session = tab.activeSession ?? orderedSessions(of: tab).first
                session?.reveal()
                return
            }
        }
    }

    // Workgroups don't have a single canonical "front" in the way a
    // window or tab does, so we reveal the workgroup's main (leader)
    // session. That brings the leader's window forward and swaps the
    // leader peer in if it isn't currently the active one.
    private func jumpToWorkgroup(id: String) {
        guard let instance = iTermWorkgroupController.instance.allInstances
                .first(where: { $0.instanceUniqueIdentifier == id }),
              let leader = instance.mainSession else {
            return
        }
        leader.reveal()
    }

    private func terminal(forGuid guid: String) -> PseudoTerminal? {
        guard let controller = iTermController.sharedInstance() else { return nil }
        return controller.terminals().first { $0.terminalGuid == guid }
    }
}

// MARK: - Live model

// Outline rows for the cockpit's tree. The shape varies by
// CockpitGroupMode:
//   * byStatus:    window > state-bucket > session (empty state
//                  buckets are suppressed)
//   * byWindow:    window > tab > session
//   * byWorkgroup: workgroup > session
// Buried sessions appear under a synthetic "Buried Sessions" root
// in byStatus and byWindow.
//
// Class, not struct: NSOutlineView's data source uses pointer
// identity for items (not isEqual:), and Swift bridges structs
// through Any with a fresh __SwiftValue wrapper on every bridge,
// so two equal structs are different pointers and the outline view
// can't track expansion/selection across rebuilds. CockpitRow
// instances are cached on the controller by their Identity so the
// same pointer survives a rebuild whenever the underlying entity
// (window, per-window state bucket, session) still exists.
fileprivate final class CockpitRow {
    // `Kind` is decorated with payloads we use at render or click time
    // (target guids, state labels, etc). `Identity` is the value used
    // by NSOutlineView's pointer cache + the diff: it lifts each Kind
    // to a strictly Hashable form so identity-equality is well-defined
    // even when the kind carries non-Hashable payloads. Group identity
    // is parameterized by an arbitrary "scope" string (window guid in
    // byStatus mode) so the same SessionState bucket under different
    // scopes hashes as different identities.
    enum Kind {
        case window(guid: String)
        case buriedRoot
        case workgroup(id: String)
        case tab(uniqueId: Int)
        case group(scope: String, state: SessionState)
        case session(guid: String)
    }
    enum Identity: Hashable {
        case window(String)
        case buriedRoot
        case workgroup(String)
        case tab(Int)
        case group(String, SessionState)
        case session(String)
    }
    let identity: Identity
    let kind: Kind
    var title: String
    // Secondary line shown under the title in a smaller, dimmer font.
    // Only populated for session rows in byStatus mode (the only place
    // a session's live detail string is surfaced); nil everywhere else,
    // which the cell renders as a plain single-line row.
    var detail: String?
    var children: [CockpitRow] = []

    init(identity: Identity, kind: Kind, title: String) {
        self.identity = identity
        self.kind = kind
        self.title = title
    }
}

// User-visible grouping axis. The cockpit's outline view re-roots
// every time this changes. Persisted across launches so the user
// returns to the mode they last used.
@objc enum CockpitGroupMode: Int, CaseIterable {
    case byStatus = 0
    case byWindow = 1
    case byWorkgroup = 2

    var shortLabel: String {
        switch self {
        case .byStatus: return "Status"
        case .byWindow: return "Window"
        case .byWorkgroup: return "Workgroup"
        }
    }

    var tooltip: String {
        switch self {
        case .byStatus:
            return "Group sessions by status (Waiting / Working / Idle), within each window."
        case .byWindow:
            return "Group sessions by window, then by tab and split pane."
        case .byWorkgroup:
            return "Show only sessions in a workgroup, grouped by workgroup."
        }
    }

    // SF Symbol for the toolbar segment. progress.indicator only
    // exists on macOS 14+, so byStatus falls back to clock.badge.
    // checkmark on earlier systems (the deployment target is 12).
    var symbolName: String {
        switch self {
        case .byStatus:
            if #available(macOS 14, *) {
                return "progress.indicator"
            }
            return "clock.badge.checkmark"
        case .byWindow:
            return "macwindow.on.rectangle"
        case .byWorkgroup:
            return "rectangle.3.group"
        }
    }

    fileprivate static let userDefaultsKey = "NoSyncCockpitGroupMode"

    fileprivate static func loadPersisted() -> CockpitGroupMode {
        let raw = iTermUserDefaults.userDefaults().integer(forKey: userDefaultsKey)
        return CockpitGroupMode(rawValue: raw) ?? .byStatus
    }

    fileprivate static func persist(_ mode: CockpitGroupMode) {
        iTermUserDefaults.userDefaults().set(mode.rawValue,
                                              forKey: userDefaultsKey)
    }
}

// Sentinel scope value for state-bucket rows under the synthetic
// buried-sessions root. Real terminal guids never start with "<", so
// there's no collision risk and group(scope:state:) identities stay
// disjoint between real windows and the buried section.
fileprivate let cockpitBuriedWindowGuid = "<buried>"

// Display order for state subgroups within a window. Waiting first
// (it's the only state that requires user attention), then Working
// (active runs the user might be watching), then Idle (the rest).
private let cockpitStateOrder: [SessionState] = [.waiting, .working, .idle]

// Row view that always reports itself as emphasized so source-list
// selection draws in its active blue style on the non-activating
// cockpit panel, where the window never becomes key.
fileprivate final class CockpitAlwaysEmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { return true }
        set { /* fixed */ }
    }
}

// Cell view that paints its label text with an explicit color
// attribute baked into an NSAttributedString. NSTableView's source-
// list rendering applies a secondary text appearance to certain
// rows when the containing window isn't key (in practice, the
// ancestor chain leading to the most-recently-touched item). That
// secondary styling can't be reliably overridden by setting
// textField.textColor on the prototype — AppKit re-runs the
// styling on every key-window change and can win the tie. Setting
// the color through the attributed-string attributes makes the
// text carry its own color and rendering doesn't fall through to
// AppKit's auto-styling.
//
// `cockpitTitle` is the canonical text source; the attributed
// representation is rebuilt whenever the title or backgroundStyle
// changes (the latter so selected rows get inverted text on the
// blue selection background).
@objc(iTermCockpitTableCellView)
fileprivate final class CockpitTableCellView: NSTableCellView {
    // The title uses the table's appearance font (same as before this
    // cell gained a detail line). The detail line is one size smaller
    // and dimmer so it reads as subordinate to the title.
    static let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    // Gap between the title baseline box and the detail line.
    private static let detailSpacing: CGFloat = 1
    // Vertical breathing room above the title and below the detail.
    private static let verticalPadding: CGFloat = 8

    // Row height the outline view should use for a row with or without
    // a detail line. Single-line rows keep the original 24pt look.
    static func rowHeight(hasDetail: Bool) -> CGFloat {
        let layoutManager = NSLayoutManager()
        let titleHeight = ceil(layoutManager.defaultLineHeight(
            for: NSFont.systemFont(ofSize: NSFont.systemFontSize)))
        if !hasDetail {
            return max(24, titleHeight + verticalPadding)
        }
        let detailHeight = ceil(layoutManager.defaultLineHeight(for: detailFont))
        return titleHeight + detailSpacing + detailHeight + verticalPadding
    }

    var cockpitTitle: String = "" {
        didSet {
            if cockpitTitle != oldValue { applyText() }
        }
    }

    // Raw markdown for the detail line. Rendering is cached in
    // renderedDetail so we don't re-parse markdown on every selection or
    // appearance change.
    var cockpitDetail: String? {
        didSet {
            if cockpitDetail != oldValue {
                renderedDetail = cockpitDetail.flatMap(Self.renderDetailMarkdown)
                detailField?.isHidden = (renderedDetail == nil)
                applyText()
                needsLayout = true
            }
        }
    }

    private var detailField: NSTextField?
    private var renderedDetail: NSAttributedString?

    // Lay out top-down so the title sits above the detail line.
    override var isFlipped: Bool { true }

    override var backgroundStyle: NSView.BackgroundStyle {
        get { return super.backgroundStyle }
        set {
            super.backgroundStyle = newValue
            applyText()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyText()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        installDetailField()
        applyText()
    }

    // The title field comes from the xib; the detail field is added
    // programmatically. Both are positioned by hand in layout() (no auto
    // layout), so opt them out of constraint generation and clear the
    // xib's autoresizing so our frames are authoritative.
    private func installDetailField() {
        guard detailField == nil else { return }
        textField?.translatesAutoresizingMaskIntoConstraints = true
        textField?.autoresizingMask = []
        let field = NSTextField(labelWithString: "")
        field.font = Self.detailFont
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.isHidden = true
        field.translatesAutoresizingMaskIntoConstraints = true
        field.autoresizingMask = []
        addSubview(field)
        detailField = field
    }

    override func layout() {
        super.layout()
        guard let textField else { return }
        let width = bounds.width
        let titleHeight = ceil(textField.intrinsicContentSize.height)
        if let detailField, !detailField.isHidden {
            let detailHeight = ceil(detailField.intrinsicContentSize.height)
            let total = titleHeight + Self.detailSpacing + detailHeight
            let top = max(0, (bounds.height - total) / 2)
            textField.frame = NSRect(x: 0, y: top, width: width, height: titleHeight)
            detailField.frame = NSRect(x: 0,
                                       y: top + titleHeight + Self.detailSpacing,
                                       width: width,
                                       height: detailHeight)
        } else {
            textField.frame = NSRect(x: 0,
                                     y: (bounds.height - titleHeight) / 2,
                                     width: width,
                                     height: titleHeight)
        }
    }

    private func applyText() {
        let emphasized = (backgroundStyle == .emphasized)
        if let textField {
            let color: NSColor = emphasized
                ? .alternateSelectedControlTextColor
                : .labelColor
            textField.attributedStringValue = NSAttributedString(
                string: cockpitTitle,
                attributes: [.foregroundColor: color])
        }
        if let detailField, let renderedDetail {
            if emphasized {
                // On the blue selection fill, force the whole detail
                // line (including any markdown links) to the selected
                // text color so it stays legible.
                let copy = renderedDetail.mutableCopy() as! NSMutableAttributedString
                copy.addAttribute(.foregroundColor,
                                  value: NSColor.alternateSelectedControlTextColor,
                                  range: NSRange(location: 0, length: copy.length))
                detailField.attributedStringValue = copy
            } else {
                detailField.attributedStringValue = renderedDetail
            }
        }
    }

    // Render the markdown detail string into a compact, single-line
    // attributed string sized for the detail row. The shared markdown
    // renderer formats at the system font size with the body in
    // secondaryLabelColor; we scale every run down to the detail size
    // (preserving bold / italic / code traits via the font descriptor)
    // and force tail truncation so a long detail stays on one line.
    static func renderDetailMarkdown(_ markdown: String) -> NSAttributedString? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let rendered = AttributedStringForGPTMarkdown(trimmed,
                                                      linkColor: .linkColor,
                                                      textColor: .secondaryLabelColor,
                                                      didCopy: nil)
        let result = rendered.mutableCopy() as! NSMutableAttributedString
        // Drop any trailing newline the markdown renderer appended so it
        // doesn't push a phantom second line into the height.
        while let last = result.string.last, last.isNewline {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }
        let fullRange = NSRange(location: 0, length: result.length)
        let targetSize = NSFont.smallSystemFontSize
        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let scaled = NSFont(descriptor: font.fontDescriptor, size: targetSize) ?? font
            result.addAttribute(.font, value: scaled, range: range)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        result.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)
        return result
    }
}

private func cockpitStateLabel(_ state: SessionState, count: Int) -> String {
    let name: String
    switch state {
    case .waiting: name = "Waiting"
    case .working: name = "Working"
    case .idle, .unknown: name = "Idle"
    }
    return "\(name) · \(count)"
}

// MARK: - Data source / delegate

extension CockpitWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView,
                     numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return rootRows.count
        }
        return (item as? CockpitRow)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView,
                     child index: Int,
                     ofItem item: Any?) -> Any {
        if item == nil {
            return rootRows[index]
        }
        // AppKit can occasionally feed back items the data source didn't
        // produce, e.g. during window state restoration. Don't crash; if
        // the contract breaks, log via it_assert and return a safe value.
        guard let row = item as? CockpitRow else {
            it_assert(false, "Unexpected outline item type: \(type(of: item))")
            return NSNull()
        }
        return row.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView,
                     isItemExpandable item: Any) -> Bool {
        guard let row = item as? CockpitRow else { return false }
        switch row.kind {
        case .group, .window, .buriedRoot, .workgroup, .tab: return true
        case .session: return false
        }
    }

    // Source-list selection on session leaves draws in the inactive
    // gray-fill blue-text look when the table isn't first responder.
    // Pinning isEmphasized true on the row view fixes the selection.
    // We only apply that override to session rows: window group-header
    // rows render different chrome based on isEmphasized too, and
    // forcing them to emphasized state would make the section headers
    // look "active" even when iTerm2 isn't frontmost — a behavior
    // change orthogonal to the selection fix.
    func outlineView(_ outlineView: NSOutlineView,
                     rowViewForItem item: Any) -> NSTableRowView? {
        guard let row = item as? CockpitRow else { return nil }
        switch row.kind {
        case .session, .window, .tab, .workgroup:
            // Clickable rows — keep selection drawing in the active
            // blue style even though the cockpit panel is rarely key.
            return CockpitAlwaysEmphasizedRowView()
        case .group, .buriedRoot:
            return nil
        }
    }

    // Every row is a regular expandable/leaf row. We deliberately do
    // NOT use sourceList section-header styling (isGroupItem -> true)
    // for top-level rows because AppKit's source-list group treatment
    // conflicts with what we want here:
    //   - Section headers can't have disclosure triangles, so windows
    //     would stop being collapsable.
    //   - The header look applies inconsistently to siblings (the
    //     first window stays normal-styled, later ones get the small
    //     gray uppercase treatment) and that propagates to nested
    //     rows in unpredictable ways (e.g. the deepest peer of an
    //     inner workgroup picks up the secondary-text appearance).
    // Visual distinction at the top level comes from the "Window N"
    // prefix and the label content itself, not from section chrome.
    func outlineView(_ outlineView: NSOutlineView,
                     isGroupItem item: Any) -> Bool {
        return false
    }

    // Selectable iff the click does something. Selecting a state bucket
    // or the "Buried Sessions" header has no action, so they shouldn't
    // even highlight on click.
    func outlineView(_ outlineView: NSOutlineView,
                     shouldSelectItem item: Any) -> Bool {
        guard let row = item as? CockpitRow else { return false }
        switch row.kind {
        case .session, .window, .tab, .workgroup: return true
        case .group, .buriedRoot: return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let row = item as? CockpitRow,
              let identifier = tableColumn?.identifier
                ?? outlineView.tableColumns.first?.identifier else {
            return nil
        }
        guard let cell = outlineView.makeView(withIdentifier: identifier,
                                               owner: self) as? CockpitTableCellView else {
            return nil
        }
        cell.cockpitTitle = row.title
        cell.cockpitDetail = row.detail
        return cell
    }

    // Rows carrying a detail line are taller so the smaller second line
    // fits under the title. Everything else keeps the original height.
    func outlineView(_ outlineView: NSOutlineView,
                     heightOfRowByItem item: Any) -> CGFloat {
        let hasDetail = ((item as? CockpitRow)?.detail?.isEmpty == false)
        return CockpitTableCellView.rowHeight(hasDetail: hasDetail)
    }
}

// MARK: - Live model wiring

extension CockpitWindowController {

    fileprivate func registerForLiveUpdates() {
        let center = NotificationCenter.default
        let names: [NSNotification.Name] = [
            .PTYSessionCreated,
            .PTYSessionTerminated,
            .iTermSessionWillTerminate,
            .iTermDidCreateTerminalWindow,
            .iTermWindowDidClose,
            iTermSessionTabStatus.didChangeNotificationName,
            GlobalJobMonitor.didChangeNotification,
            // Picks up session renames (and, transitively, window
            // title changes — setWindowTitle runs synchronously off
            // the same delegate chain that posts this, so by the time
            // our coalesced refresh fires on the next runloop tick
            // the NSWindow's title is already up to date).
            .PTYSessionPresentationNameDidChange,
            // Bury / unbury moves a session in and out of our synthetic
            // Buried Sessions root.
            .iTermSessionBuriedStateChangeTab,
        ]
        for name in names {
            center.addObserver(self,
                               selector: #selector(scheduleRefresh),
                               name: name,
                               object: nil)
        }
    }

    @objc fileprivate func scheduleRefresh() {
        if refreshScheduled { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    // Diffable-update path. reloadData() is a sledgehammer: it drops
    // expansion, selection, scroll position, and forces a full re-walk
    // of the data source. Computing the structural diff between the old
    // shape and the new shape and emitting per-item insert/remove/move
    // ops inside beginUpdates/endUpdates lets NSOutlineView preserve
    // everything for rows that didn't move. The defensive
    // restoreSelection at the end is a backstop for rows whose parent
    // changes (state transition moves) — beginUpdates/endUpdates only
    // preserves selection for items that stay put.
    fileprivate func refresh() {
        let oldShape = snapshotTreeShape(of: rootRows)
        // rebuildRows() reassigns rowCache to a fresh dictionary keyed
        // by the new shape, so the post-rebuild cache no longer holds
        // rows for removed identities. Save the pre-rebuild cache so
        // remove ops on parents that survive can still resolve their
        // pre-existing row reference even if a future change to
        // rebuildRows stops reusing the same CockpitRow instance for
        // surviving identities. (Today it does, so oldRowCache and
        // rowCache agree on common keys; this is defensive.)
        let oldRowCache = rowCache
        let previouslySelected = capturedSelectedIdentities()
        let previouslyExpanded = capturedExpandedIdentities()
        rebuildRows()
        let newShape = snapshotTreeShape(of: rootRows)
        applyDiff(from: oldShape,
                  oldRowCache: oldRowCache,
                  to: newShape)
        autoExpandNewlyAddedItems(oldShape: oldShape, newShape: newShape)
        restoreExpansionForMovedItems(oldShape: oldShape,
                                       newShape: newShape,
                                       previouslyExpanded: previouslyExpanded)
        restoreSelection(previouslySelected: previouslySelected)
    }

    fileprivate func rebuildRows() {
        var freshCache: [CockpitRow.Identity: CockpitRow] = [:]
        let rebuiltRoots: [CockpitRow]
        switch groupMode {
        case .byStatus:
            rebuiltRoots = rebuildByStatus(freshCache: &freshCache)
        case .byWindow:
            rebuiltRoots = rebuildByWindow(freshCache: &freshCache)
        case .byWorkgroup:
            rebuiltRoots = rebuildByWorkgroup(freshCache: &freshCache)
        }
        let pruned = filter.isEmpty
            ? rebuiltRoots
            : Self.prune(rebuiltRoots, filter: filter, keptCache: &freshCache)
        rowCache = freshCache
        rootRows = pruned
    }

    // Walk a freshly-built tree and keep only the subtrees that contain
    // at least one session leaf whose title contains `filter` (case-
    // insensitive). Intermediate rows survive only if at least one
    // descendant survives. Identity-stable: surviving rows are the same
    // CockpitRow instances NSOutlineView already knows about, so
    // expansion / selection persist across filter edits. Identities of
    // dropped rows are evicted from keptCache so the diff and the cache
    // agree on the surviving set.
    private static func prune(_ rows: [CockpitRow],
                              filter: String,
                              keptCache: inout [CockpitRow.Identity: CockpitRow]) -> [CockpitRow] {
        let needle = filter.lowercased()
        var kept: [CockpitRow] = []
        for row in rows {
            if let surviving = pruneRow(row, needle: needle, keptCache: &keptCache) {
                kept.append(surviving)
            }
        }
        return kept
    }

    private static func pruneRow(_ row: CockpitRow,
                                 needle: String,
                                 keptCache: inout [CockpitRow.Identity: CockpitRow]) -> CockpitRow? {
        switch row.kind {
        case .session:
            if row.title.lowercased().contains(needle) {
                return row
            }
            keptCache.removeValue(forKey: row.identity)
            return nil
        case .window, .buriedRoot, .workgroup, .tab, .group:
            var keptChildren: [CockpitRow] = []
            for child in row.children {
                if let survivor = pruneRow(child, needle: needle, keptCache: &keptCache) {
                    keptChildren.append(survivor)
                }
            }
            if keptChildren.isEmpty {
                keptCache.removeValue(forKey: row.identity)
                return nil
            }
            row.children = keptChildren
            return row
        }
    }

    // byStatus: window > {Waiting/Working/Idle} > sessions.
    private func rebuildByStatus(
        freshCache: inout [CockpitRow.Identity: CockpitRow]
    ) -> [CockpitRow] {
        let controller = iTermController.sharedInstance()
        let terminals = controller?.terminals() ?? []
        var rebuiltRoots: [CockpitRow] = []
        var alreadySeen: Set<ObjectIdentifier> = []
        for terminal in terminals {
            guard let windowGuid = terminal.terminalGuid else { continue }
            let title = cockpitWindowTitle(for: terminal)
            let windowIdentity = CockpitRow.Identity.window(windowGuid)
            let windowRow = rowCache[windowIdentity]
                ?? CockpitRow(identity: windowIdentity,
                              kind: .window(guid: windowGuid),
                              title: title)
            windowRow.title = title
            freshCache[windowIdentity] = windowRow
            let expanded = expandWithPeers(terminal.allSessions(),
                                            alreadySeen: &alreadySeen)
            windowRow.children = bucketSessionsByState(
                expanded,
                scope: windowGuid,
                freshCache: &freshCache)
            rebuiltRoots.append(windowRow)
        }

        // Buried sessions live under a synthetic root row at the
        // bottom of the outline. iTermBuriedSessions doesn't make
        // them visible in any window controller, so without this
        // they wouldn't be addressable from the cockpit at all.
        let buried = iTermBuriedSessions.sharedInstance().buriedSessions() ?? []
        let buriedExpanded = expandWithPeers(buried,
                                              alreadySeen: &alreadySeen)
        if !buriedExpanded.isEmpty {
            let identity = CockpitRow.Identity.buriedRoot
            let buriedRow = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .buriedRoot,
                              title: "Buried Sessions")
            buriedRow.title = "Buried Sessions"
            freshCache[identity] = buriedRow
            buriedRow.children = bucketSessionsByState(
                buriedExpanded,
                scope: cockpitBuriedWindowGuid,
                freshCache: &freshCache)
            rebuiltRoots.append(buriedRow)
        }
        return rebuiltRoots
    }

    // byWindow: window > tab > sessions. Tab level is kept even when
    // a tab has only one session, so the user reads the structure as
    // "this window has N tabs."
    private func rebuildByWindow(
        freshCache: inout [CockpitRow.Identity: CockpitRow]
    ) -> [CockpitRow] {
        let controller = iTermController.sharedInstance()
        let terminals = controller?.terminals() ?? []
        var rebuiltRoots: [CockpitRow] = []
        var alreadySeen: Set<ObjectIdentifier> = []
        for terminal in terminals {
            guard let windowGuid = terminal.terminalGuid else { continue }
            let title = cockpitWindowTitle(for: terminal)
            let windowIdentity = CockpitRow.Identity.window(windowGuid)
            let windowRow = rowCache[windowIdentity]
                ?? CockpitRow(identity: windowIdentity,
                              kind: .window(guid: windowGuid),
                              title: title)
            windowRow.title = title
            freshCache[windowIdentity] = windowRow

            var tabRows: [CockpitRow] = []
            for (tabIndex, tab) in terminal.tabs().enumerated() {
                let tabUniqueId = Int(tab.uniqueId)
                let tabIdentity = CockpitRow.Identity.tab(tabUniqueId)
                let tabTitle = cockpitTabTitle(for: tab,
                                                positionInWindow: tabIndex + 1)
                let tabRow = rowCache[tabIdentity]
                    ?? CockpitRow(identity: tabIdentity,
                                  kind: .tab(uniqueId: tabUniqueId),
                                  title: tabTitle)
                tabRow.title = tabTitle
                freshCache[tabIdentity] = tabRow
                let expanded = expandWithPeers(orderedSessions(of: tab),
                                                alreadySeen: &alreadySeen)
                tabRow.children = sessionRows(
                    for: expanded,
                    freshCache: &freshCache)
                tabRows.append(tabRow)
            }
            windowRow.children = tabRows
            rebuiltRoots.append(windowRow)
        }

        // Buried section, same shape as in byStatus but flat (no tab
        // wrapper — buried sessions don't have one).
        let buried = iTermBuriedSessions.sharedInstance().buriedSessions() ?? []
        let buriedExpanded = expandWithPeers(buried,
                                              alreadySeen: &alreadySeen)
        if !buriedExpanded.isEmpty {
            let identity = CockpitRow.Identity.buriedRoot
            let buriedRow = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .buriedRoot,
                              title: "Buried Sessions")
            buriedRow.title = "Buried Sessions"
            freshCache[identity] = buriedRow
            buriedRow.children = sessionRows(for: buriedExpanded,
                                              freshCache: &freshCache)
            rebuiltRoots.append(buriedRow)
        }
        return rebuiltRoots
    }

    // byWorkgroup: workgroup > sessions. Only sessions that belong to
    // an active workgroup instance appear; standalone sessions (those
    // without a workgroupInstance) are omitted entirely. This mode is
    // for users who organize work into named workgroups, so listing
    // unrelated standalone sessions would just bloat the tree.
    private func rebuildByWorkgroup(
        freshCache: inout [CockpitRow.Identity: CockpitRow]
    ) -> [CockpitRow] {
        var rebuiltRoots: [CockpitRow] = []
        for instance in iTermWorkgroupController.instance.allInstances {
            let liveSessions = instance.resolvedMembers().compactMap { $0.session }
            if liveSessions.isEmpty { continue }
            let identity = CockpitRow.Identity.workgroup(instance.instanceUniqueIdentifier)
            let title = cockpitWorkgroupTitle(for: instance)
            let row = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .workgroup(id: instance.instanceUniqueIdentifier),
                              title: title)
            row.title = title
            freshCache[identity] = row
            row.children = sessionRows(for: liveSessions,
                                        freshCache: &freshCache)
            rebuiltRoots.append(row)
        }
        return rebuiltRoots
    }

    // Build session-leaf rows in input order, no grouping. Used by
    // byWindow and byWorkgroup where the parent provides the grouping.
    private func sessionRows(
        for sessions: [PTYSession],
        freshCache: inout [CockpitRow.Identity: CockpitRow]
    ) -> [CockpitRow] {
        return sessions.map { session in
            let identity = CockpitRow.Identity.session(session.guid)
            let title = cockpitSessionTitle(for: session)
            let row = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .session(guid: session.guid),
                              title: title)
            row.title = title
            // Detail is a byStatus-only affordance; clear any value a
            // cached row carried over from a previous byStatus build so
            // it doesn't leak into byWindow / byWorkgroup rows.
            row.detail = nil
            row.children = []
            freshCache[identity] = row
            return row
        }
    }

    // Bridge through Objective-C's untyped NSArray to a strongly-typed
    // [PTYSession]. orderedSessions is declared as NSArray rather than
    // NSArray<PTYSession *> because the property comes from a category
    // wired up before PTYSession was generic-friendly; the contents are
    // PTYSession in practice.
    private func orderedSessions(of tab: PTYTab) -> [PTYSession] {
        return tab.orderedSessions.compactMap { $0 as? PTYSession }
    }

    // Walk a list of "anchor" sessions (e.g. from tab.orderedSessions
    // or terminal.allSessions, which only contain *visible* sessions)
    // and add every workgroup peer that shares a peer port with any of
    // them. Only one peer per port is active in a tab at a time; the
    // rest live in the workgroup instance's peer ports and aren't part
    // of any tab's session list. Without this expansion, byStatus and
    // byWindow would silently drop every non-selected peer.
    //
    // Workgroup instances can host nested peer ports in addition to
    // the top-level one (a split whose config declares peer children
    // gets its own port). An anchor session may belong to either, so
    // we search both via instance.allPeerPorts.
    //
    // Peer ordering: peer-port sessions are emitted in the workgroup
    // config's declared order, not in port dictionary order and not
    // "active first." A click that switches which peer is active must
    // not reshuffle the outline, which is confusing UX. Config order
    // is stable for the life of the workgroup, so the row sequence
    // stays put across peer activations.
    //
    // The `alreadySeen` set carries across phases of a single rebuild
    // so a peer surfaced under one tab/window isn't also surfaced under
    // another (or the buried section).
    private func expandWithPeers(_ anchors: [PTYSession],
                                  alreadySeen: inout Set<ObjectIdentifier>) -> [PTYSession] {
        var result: [PTYSession] = []
        var seenPorts: Set<ObjectIdentifier> = []
        for session in anchors {
            let sid = ObjectIdentifier(session)
            if alreadySeen.contains(sid) { continue }

            // When the anchor is itself a peer of an unexpanded port,
            // expand the whole port in config order and let the anchor
            // take its config-driven position. Otherwise add it
            // directly (non-peer workgroup children, plain sessions).
            if let instance = session.workgroupInstance,
               let port = instance.allPeerPorts.first(where: { $0.contains(session: session) }) {
                let portID = ObjectIdentifier(port)
                if !seenPorts.contains(portID) {
                    seenPorts.insert(portID)
                    for config in instance.workgroup.sessions {
                        guard let peer = port.session(forIdentifier: config.uniqueIdentifier) else {
                            continue
                        }
                        let pid = ObjectIdentifier(peer)
                        if alreadySeen.contains(pid) { continue }
                        alreadySeen.insert(pid)
                        result.append(peer)
                    }
                    continue
                }
            }

            alreadySeen.insert(sid)
            result.append(session)
        }
        return result
    }

    private func bucketSessionsByState(_ sessions: [PTYSession],
                                       scope: String,
                                       freshCache: inout [CockpitRow.Identity: CockpitRow]) -> [CockpitRow] {
        var bucketed: [SessionState: [CockpitRow]] = [:]
        for session in sessions {
            let state = sessionState(for: session)
            let identity = CockpitRow.Identity.session(session.guid)
            let title = cockpitSessionTitle(for: session)
            let row = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .session(guid: session.guid),
                              title: title)
            row.title = title
            row.detail = cockpitDetailText(for: session)
            row.children = []
            freshCache[identity] = row
            bucketed[state, default: []].append(row)
        }

        var groupRows: [CockpitRow] = []
        for state in cockpitStateOrder {
            let members = bucketed[state] ?? []
            if members.isEmpty { continue }
            let identity = CockpitRow.Identity.group(scope, state)
            let label = cockpitStateLabel(state, count: members.count)
            let groupRow = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .group(scope: scope, state: state),
                              title: label)
            groupRow.title = label
            groupRow.children = members
            freshCache[identity] = groupRow
            groupRows.append(groupRow)
        }
        return groupRows
    }

    // Backstop after diffable updates: covers the edge case where a
    // selected session row changes parent (state transition) within a
    // single refresh. NSOutlineView preserves selection for items that
    // don't move, but a moveItem clears the row's selection state.
    private func capturedSelectedIdentities() -> Set<CockpitRow.Identity> {
        var selected: Set<CockpitRow.Identity> = []
        for rowIndex in outlineView.selectedRowIndexes {
            if let row = outlineView.item(atRow: rowIndex) as? CockpitRow {
                selected.insert(row.identity)
            }
        }
        return selected
    }

    private func restoreSelection(previouslySelected: Set<CockpitRow.Identity>) {
        if previouslySelected.isEmpty { return }
        var indexes = IndexSet()
        let rowCount = outlineView.numberOfRows
        for rowIndex in 0..<rowCount {
            guard let row = outlineView.item(atRow: rowIndex) as? CockpitRow else {
                continue
            }
            if previouslySelected.contains(row.identity) {
                indexes.insert(rowIndex)
            }
        }
        if !indexes.isEmpty {
            outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        }
    }

    // Auto-expand items that didn't exist before this refresh. Items
    // that survived from the previous shape keep whatever expansion
    // state the user set (NSOutlineView preserves that across batched
    // updates), so this only affects brand-new windows and brand-new
    // state buckets. expandChildren: true recursively expands new
    // subtrees, so we skip identities whose parent is also newly added
    // (the parent's recursive expand covers them).
    private func autoExpandNewlyAddedItems(oldShape: TreeShape,
                                           newShape: TreeShape) {
        let added = newShape.all.subtracting(oldShape.all)
        for id in added {
            if let parentId = newShape.parentOf[id], added.contains(parentId) {
                continue
            }
            if let row = rowCache[id] {
                outlineView.expandItem(row, expandChildren: true)
            }
        }
    }

    // Snapshot of which row identities are currently expanded. Used to
    // restore expansion for items whose parent changed across a refresh
    // (a tab dragged from one window to another, a session moving
    // between state buckets, etc). NSOutlineView's diffable batched
    // updates only preserve expansion for items that stay in place; an
    // item whose parent changes is re-inserted in its default
    // (collapsed) state on the new parent.
    private func capturedExpandedIdentities() -> Set<CockpitRow.Identity> {
        var expanded: Set<CockpitRow.Identity> = []
        for (id, row) in rowCache where outlineView.isItemExpanded(row) {
            expanded.insert(id)
        }
        return expanded
    }

    private func restoreExpansionForMovedItems(
        oldShape: TreeShape,
        newShape: TreeShape,
        previouslyExpanded: Set<CockpitRow.Identity>
    ) {
        let common = oldShape.all.intersection(newShape.all)
        for id in common {
            guard previouslyExpanded.contains(id) else { continue }
            // Items whose parent didn't change keep their expansion
            // through the batched update; nothing to do.
            if oldShape.parentOf[id] == newShape.parentOf[id] { continue }
            if let row = rowCache[id] {
                outlineView.expandItem(row, expandChildren: false)
            }
        }
    }

    // Captures parent/index/title for every identity in the current
    // tree. Frozen by value: rebuildRows mutates row.children in place,
    // so we snapshot before the mutation and compare snapshots after.
    private struct TreeShape {
        var all: Set<CockpitRow.Identity> = []
        // parentOf[id] absent for root-level identities; present
        // otherwise. Combined with `all.contains(id)` this disambiguates
        // "root" from "not in tree" without a double-optional dance.
        var parentOf: [CockpitRow.Identity: CockpitRow.Identity] = [:]
        var indexOf: [CockpitRow.Identity: Int] = [:]
        var titleOf: [CockpitRow.Identity: String] = [:]
        var detailOf: [CockpitRow.Identity: String?] = [:]
    }

    private func snapshotTreeShape(of roots: [CockpitRow]) -> TreeShape {
        var shape = TreeShape()
        for (i, root) in roots.enumerated() {
            shape.all.insert(root.identity)
            shape.indexOf[root.identity] = i
            shape.titleOf[root.identity] = root.title
            shape.detailOf[root.identity] = root.detail
            snapshotChildren(of: root, into: &shape)
        }
        return shape
    }

    private func snapshotChildren(of row: CockpitRow, into shape: inout TreeShape) {
        for (i, child) in row.children.enumerated() {
            shape.all.insert(child.identity)
            shape.parentOf[child.identity] = row.identity
            shape.indexOf[child.identity] = i
            shape.titleOf[child.identity] = child.title
            shape.detailOf[child.identity] = child.detail
            snapshotChildren(of: child, into: &shape)
        }
    }

    // Approach: collect all structural changes as a pure remove set
    // and a pure insert set, then apply each phase with IndexSets.
    // Reasons:
    //   * Decomposing every move into remove+insert avoids the
    //     "multiple moveItem ops within a parent must be sequenced
    //     in the order that lines up with NSOutlineView's
    //     interpretation of indexes" trap. removeItems indexes are
    //     all relative to the pre-batch state; insertItems indexes
    //     are all relative to the post-batch state — neither cares
    //     about iteration order, so unordered Set traversal of
    //     `common` is safe.
    //   * For cross-parent moves the classification matters:
    //       old parent removed + new parent added → both cascades
    //         together produce the right tree; emit nothing.
    //       old parent removed + new parent surviving → old cascade
    //         already dropped the row; need an explicit insert.
    //       old parent surviving + new parent added → new parent's
    //         insertion fetches the row via the data source; need
    //         an explicit remove so NSOutlineView's batched state
    //         stays consistent with the data source's child count
    //         on the surviving old parent.
    //       both parents surviving → standard remove+insert pair.
    private func applyDiff(from old: TreeShape,
                           oldRowCache: [CockpitRow.Identity: CockpitRow],
                           to new: TreeShape) {
        let removed = old.all.subtracting(new.all)
        let added = new.all.subtracting(old.all)
        let common = old.all.intersection(new.all)

        var removesByParent: [CockpitRow.Identity?: IndexSet] = [:]
        var insertsByParent: [CockpitRow.Identity?: IndexSet] = [:]

        for id in removed {
            let parent = old.parentOf[id]
            // If the parent is also being removed, its cascade handles
            // this child. Without the skip we'd remove the child first
            // and then try to remove its already-gone parent, which
            // NSOutlineView throws on.
            if let parentId = parent, removed.contains(parentId) {
                continue
            }
            let index = old.indexOf[id] ?? 0
            removesByParent[parent, default: IndexSet()].insert(index)
        }

        for id in added {
            let parent = new.parentOf[id]
            // If the parent is also new, its insertion's data-source
            // callback brings this child in implicitly.
            if let parentId = parent, added.contains(parentId) {
                continue
            }
            let index = new.indexOf[id] ?? 0
            insertsByParent[parent, default: IndexSet()].insert(index)
        }

        for id in common {
            let oldParent = old.parentOf[id]
            let newParent = new.parentOf[id]
            let oldIndex = old.indexOf[id] ?? 0
            let newIndex = new.indexOf[id] ?? 0
            if oldParent == newParent && oldIndex == newIndex {
                continue
            }
            let oldParentRemoved =
                oldParent.map { removed.contains($0) } ?? false
            let newParentAdded =
                newParent.map { added.contains($0) } ?? false
            switch (oldParentRemoved, newParentAdded) {
            case (true, true):
                // Both cascades together produce the right tree.
                break
            case (true, false):
                insertsByParent[newParent,
                                default: IndexSet()].insert(newIndex)
            case (false, true):
                removesByParent[oldParent,
                                default: IndexSet()].insert(oldIndex)
            case (false, false):
                removesByParent[oldParent,
                                default: IndexSet()].insert(oldIndex)
                insertsByParent[newParent,
                                default: IndexSet()].insert(newIndex)
            }
        }

        outlineView.beginUpdates()

        // Pre-batch parent rows: for removes, the parent is either nil
        // (root) or in `common` (we filtered removed parents). Look up
        // through oldRowCache so a future rebuildRows that allocates a
        // fresh CockpitRow for surviving identities can't desync this.
        for (parent, indexes) in removesByParent {
            let parentRow = parent.flatMap { oldRowCache[$0] }
            outlineView.removeItems(at: indexes,
                                    inParent: parentRow,
                                    withAnimation: [])
        }

        // Post-batch parent rows: for inserts, the parent is either nil
        // (root) or in `common`/`added` — rowCache (post-rebuild)
        // holds it in both cases.
        for (parent, indexes) in insertsByParent {
            let parentRow = parent.flatMap { rowCache[$0] }
            outlineView.insertItems(at: indexes,
                                    inParent: parentRow,
                                    withAnimation: [])
        }

        // Title- or detail-only changes (session rename, group "· N"
        // count, late window-title resolution, or a session publishing /
        // clearing its detail line) reuse the existing row. Track rows
        // whose detail line appeared or disappeared: that flips the row
        // height, which reloadItem alone doesn't recompute.
        var heightChangedIdentities: [CockpitRow.Identity] = []
        for id in common {
            let titleChanged = old.titleOf[id] != new.titleOf[id]
            let detailChanged = old.detailOf[id] != new.detailOf[id]
            guard titleChanged || detailChanged, let row = rowCache[id] else {
                continue
            }
            outlineView.reloadItem(row)
            if detailChanged,
               Self.hasDetail(old.detailOf[id]) != Self.hasDetail(new.detailOf[id]) {
                heightChangedIdentities.append(id)
            }
        }

        outlineView.endUpdates()

        // noteHeightOfRows needs final row indexes, so resolve them after
        // the structural batch has settled.
        if !heightChangedIdentities.isEmpty {
            var indexes = IndexSet()
            for id in heightChangedIdentities {
                guard let row = rowCache[id] else { continue }
                let rowIndex = outlineView.row(forItem: row)
                if rowIndex >= 0 {
                    indexes.insert(rowIndex)
                }
            }
            if !indexes.isEmpty {
                outlineView.noteHeightOfRows(withIndexesChanged: indexes)
            }
        }
    }

    // TreeShape.detailOf yields a doubly-optional (dictionary lookup of
    // an optional value); flatten it to "is there a non-empty detail."
    private static func hasDetail(_ value: String??) -> Bool {
        guard let inner = value, let detail = inner else { return false }
        return !detail.isEmpty
    }

    private func sessionState(for session: PTYSession) -> SessionState {
        let state = WorkgroupIntrospection.state(for: session)
        return state == .unknown ? .idle : state
    }

    private func cockpitWindowTitle(for terminal: PseudoTerminal) -> String {
        // NSWindow.title in iTerm2 tracks the active session's name, so
        // a one-session window's title equals that session's name. The
        // window-N prefix makes the top-level row visibly a window even
        // when its derived title would otherwise read as a session name
        // (and a session row by the same name lives inside it).
        let prefix = cockpitWindowTitlePrefix(for: terminal)
        let raw = terminal.window?.title ?? ""
        if raw.isEmpty || raw == prefix {
            return prefix
        }
        return "\(prefix): \(raw)"
    }

    // The live "detail" string a session publishes via its tab status
    // (OSC 21337 detail=…). Empty / missing reads as no detail so the
    // row stays single-line.
    private func cockpitDetailText(for session: PTYSession) -> String? {
        guard let detail = session.tabStatus?.detailText, !detail.isEmpty else {
            return nil
        }
        return detail
    }

    private func cockpitSessionTitle(for session: PTYSession) -> String {
        let baseName = session.name.isEmpty ? session.guid : session.name
        let prefix = cockpitSessionRolePrefix(for: session)
        guard let prefix, prefix != baseName else { return baseName }
        // Role / non-regular mode goes in front: "Diff: name" reads as
        // "this is the Diff peer" at a glance, which is the bit users
        // need to identify a peer when their live session names are all
        // the running command's idea of a title.
        return "\(prefix): \(baseName)"
    }

    // Peer / non-peer role labeling:
    //   - Peers (workgroup root and peer-port participants) are
    //     identified by their workgroup role; their live session name
    //     is whatever the running command set it to and isn't enough
    //     for the user to tell two peers apart in the outline. Always
    //     surface the role name.
    //   - Non-peer hosts (split/tab children) only need extra labeling
    //     when their behavioral mode is something other than .regular,
    //     i.e. .diff or .codeReview. Otherwise the session name alone
    //     is fine.
    // Returns nil when there's nothing useful to add.
    private func cockpitSessionRolePrefix(for session: PTYSession) -> String? {
        guard let instance = session.workgroupInstance else { return nil }
        guard let (config, displayName) = memberInfo(
                forSession: session,
                in: instance) else { return nil }
        switch config.kind {
        case .root, .peer:
            return displayName.isEmpty ? nil : displayName
        case .split, .tab:
            if config.mode == .regular { return nil }
            return config.mode.localizedTitle
        }
    }

    private func memberInfo(
        forSession session: PTYSession,
        in instance: iTermWorkgroupInstance
    ) -> (config: iTermWorkgroupSessionConfig, displayName: String)? {
        for member in instance.resolvedMembers() {
            if member.session === session {
                guard let config = instance.workgroup.sessions.first(where: {
                    $0.uniqueIdentifier == member.roleID
                }) else {
                    return nil
                }
                return (config, member.displayName)
            }
        }
        return nil
    }

    // positionInWindow is the 1-based index of the tab in its window's
    // tab bar (i.e. what the user reads on the tab itself). Don't fall
    // back to tab.uniqueId here: that's a process-wide monotonic
    // counter (gNextId in PTYTab.m) used for restorable-session
    // matching, so after a session has churned for a while it has no
    // relationship to the position the user can see.
    private func cockpitTabTitle(for tab: PTYTab, positionInWindow: Int) -> String {
        if let title = tab.title, !title.isEmpty {
            return title
        }
        return "Tab \(positionInWindow)"
    }

    private func cockpitWindowTitlePrefix(for terminal: PseudoTerminal) -> String {
        return "Window \(terminal.number)"
    }

    private func cockpitWorkgroupTitle(for instance: iTermWorkgroupInstance) -> String {
        let name = instance.workgroup.name
        return name.isEmpty ? instance.instanceUniqueIdentifier : name
    }
}

// MARK: - Search

extension CockpitWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        filter = field.stringValue
        // refresh() rebuilds the tree, then rebuildRows applies the
        // prune; identity-stable row reuse keeps expansion / selection
        // across filter edits.
        refresh()
    }
}

