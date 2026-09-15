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
// Window semantics match the global-search panel: an NSPanel at
// NSFloatingWindowLevel, becomesKeyOnlyIfNeeded, hidesOnDeactivate.
// That gives a calm floater that stays above iTerm2 windows while
// iTerm2 is foremost but disappears when another app takes over,
// instead of overlapping everything across the system. We do NOT
// use isFloatingPanel or the nonactivatingPanel styleMask; both
// turn the cockpit into a system-wide always-on-top overlay.
//
// The panel uses the utility-window style mask (set in Cockpit.xib).
// A utility panel keeps its active appearance while iTerm2 is the
// active app even when it isn't the key window, the way the system
// Fonts/Colors palettes do. Without it the titlebar, toolbar, and the
// source-list sidebar all dimmed whenever focus moved to a terminal
// (which is most of the time for a floater) and snapped back to the
// active look on click, which read as distracting flicker.
@objc(iTermCockpitWindowController)
class CockpitWindowController: NSWindowController {

    // One cockpit per app instance. Lazy: loads the nib the first
    // time someone calls show().
    @objc static let shared = CockpitWindowController()

    @IBOutlet private var outlineView: NSOutlineView!
    @IBOutlet private var settingsToolbarItem: NSToolbarItem!
    // Real button backing the settings toolbar item, so the settings
    // popover has a view to anchor to.
    private var settingsButton: NSButton?
    @IBOutlet private var searchToolbarItem: NSSearchToolbarItem!
    @IBOutlet private var groupModeToolbarItem: NSToolbarItem!
    @IBOutlet private var notifyToolbarItem: NSToolbarItem!

    // The real iTerm2 composer (a multi-cursor text view), embedded and
    // docked along the bottom as the cockpit's command bar. At-mention
    // support and chrome-hiding are opt-in hooks on the composer that
    // leave its behavior everywhere else unchanged. Sending resolves any
    // leading @-mention tokens to their sessions.
    private let composerVC = iTermMinimalComposerViewController()
    // Height of the docked composer strip: a fixed 12 lines of the
    // profile's ASCII font.
    private var composerBarHeight: CGFloat = 0
    // Height of the hint line reserved below the composer.
    private var composerTipHeight: CGFloat = 0
    // The hint line under the composer; also shows transient send
    // status (in place of a screen-center toast).
    private var composerTipLabel: NSTextField!
    private var tipResetItem: DispatchWorkItem?
    private static let defaultCockpitTip = String(localized: "Cockpit.DefaultTip", defaultValue: "Type @ to choose sessions to write to", comment: "Default hint line shown under the cockpit composer")
    // Local (NoSync) autosave for the list/composer divider position.
    private static let splitAutosaveName = "NoSyncCockpitSplit"
    // The document range of the @-run the picker is currently editing,
    // so a chosen session replaces exactly that text with a token.
    private var activeMentionRange: NSRange?

    // Guards the two-way binding between composer @-mention chips and
    // outline row selection so an update in one doesn't bounce back.
    private var isSyncingTargets = false

    // The AI chat's @-mention session picker, reused: a window > tab >
    // pane > peer outline with a live session preview, driven from the
    // composer so it never steals key focus. Unlike chat, the cockpit
    // lets you pick a whole window or tab (fans out to its sessions).
    private lazy var mentionPicker: ChatMentionPickerController = {
        let picker = ChatMentionPickerController()
        picker.allowsContainerSelection = true
        return picker
    }()

    // How rows are organized at the top of the outline. Persisted in
    // NoSync user defaults so a relaunch comes back in the same mode
    // the user left it in.
    private var groupMode: CockpitGroupMode = CockpitGroupMode.loadPersisted() {
        didSet {
            if oldValue == groupMode { return }
            CockpitGroupMode.persist(groupMode)
            scheduleRefresh()
            updateSettingsButtonEnabled()
        }
    }

    // Empty = no filter, show the grouped tree as built. Non-empty =
    // post-rebuild prune: keep only session leaves whose title contains
    // the filter (case-insensitive), drop intermediate rows that no
    // longer have any matching descendant. Keeps the structure the user
    // chose (group mode), just narrower.
    private var filter: String = ""

    // Status filter: nil shows all; otherwise only session rows whose
    // status text matches survive. The status list is dynamic; a
    // segmented control is used when the options fit horizontally, else
    // a popup button.
    private var statusFilter: String?
    private var statusFilterSegmented: NSSegmentedControl!
    private var statusFilterButton: NSPopUpButton!
    // Shared ordered items backing both controls: All (status == nil)
    // followed by each present status. Index maps 1:1 to segment / menu
    // item index.
    private var statusFilterItems: [(title: String, status: String?)] = []
    private var stateFilterBarHeight: CGFloat = 0
    // Session counts per status text (pre-filter), for the filter labels.
    private var statusCounts: [String: Int] = [:]

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
        configureNotifyToolbarItem()
        configureSettingsToolbarItem()
        configureOutlineView()
        configureSearch()
        configureStateFilterBar()
        configureCommandBar()
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
            RLog("Cockpit: window is not an NSPanel; check Cockpit.xib custom class")
            return
        }
        // Mirror iTermGlobalSearchWindowController: float above iTerm2
        // windows but only while iTerm2 is the active app, and stay out
        // of the user's way the rest of the time. hidesOnDeactivate is
        // what stops the panel from overlapping unrelated apps.
        panel.level = .floating
        // The cockpit is interactive (outline selection + composer), so a
        // click anywhere should make it key. becomesKeyOnlyIfNeeded=YES
        // (the global-search panel's setting) only grants key to views
        // that report needing it (a text field), so clicking the outline
        // selected a row without ever making the panel key/active.
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
    }

    private func configureToolbar() {
        window?.toolbarStyle = .unifiedCompact
    }

    private func configureOutlineView() {
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        // Single click just selects (which drives composer targeting via
        // the two-way binding); double click reveals/jumps to the backing
        // session so selecting a target doesn't pull focus away.
        outlineView.doubleAction = #selector(rowDoubleClicked(_:))
        // Multi-select so the command bar can fan a command out to
        // several chosen sessions at once (e.g. three of seven agents).
        outlineView.allowsMultipleSelection = true
        outlineView.headerView = nil
        // Defensive: isGroupItem returns false for every row today, so
        // there are no group rows to float, but if a future change
        // re-introduces source-list group items we don't want the
        // first one to render as a pinned floating header (which
        // shows a different background and looks inconsistent).
        outlineView.floatsGroupRows = false
        // The source-list table style backs the scroll view with a vibrant
        // NSVisualEffectView, which looks out of place here. The modern
        // .inset style drops that VEV (opaque background, inset rows with a
        // rounded selection) while still reading as a contemporary list.
        outlineView.style = .inset
        outlineView.selectionHighlightStyle = .regular
        configureListContainer()
    }

    // Give the session list a modern rounded "card" look matching the
    // composer. Rounding the scroll view itself with masksToBounds clips the
    // border stroke at the corners (they look shaved off), so instead a
    // lightweight container draws the rounded fill + border with a bezier
    // path (crisp corners) and hosts a transparent scroll view. The scroll
    // view fills the container and paints no background of its own, so the
    // container's rounded fill shows through at the corners with nothing
    // square poking out. The container is inset 8pt inside its split pane so
    // its card lines up with the composer's card (which is inset 8pt too).
    private func configureListContainer() {
        guard let scrollView = outlineView.enclosingScrollView,
              let pane = scrollView.superview else {
            return
        }
        let container = CockpitListContainerView(frame: pane.bounds.insetBy(dx: 8, dy: 8))
        container.autoresizingMask = [.width, .height]
        pane.addSubview(container)
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        container.addSubview(scrollView)
        // Transparent so the container's rounded fill is the visible surface;
        // otherwise the scroll view's square opaque background would cover
        // the rounded corners.
        scrollView.drawsBackground = false
        outlineView.backgroundColor = .clear
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

    // The bell toolbar item arms/disarms notify-on-status-change for the
    // selected window or session row, mirroring the Session Status tool's
    // bell. Its image and enabled state track the current selection.
    private func configureNotifyToolbarItem() {
        notifyToolbarItem.target = self
        notifyToolbarItem.action = #selector(toggleNotify(_:))
        // We drive isEnabled from the selection ourselves; autovalidation
        // would re-enable it whenever the target responds to the action.
        notifyToolbarItem.autovalidates = false
        updateNotifyToolbarItem()
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

    // A thin bar pinned along the top of the content view holding the
    // status filter ("All" + whatever statuses sessions currently
    // report, with counts). Insets the split view down so it doesn't
    // overlap. Uses a segmented control when it fits and a popup button
    // when there are more statuses than fit across the bar.
    private func configureStateFilterBar() {
        guard let contentView = window?.contentView else { return }
        let barHeight: CGFloat = 30
        stateFilterBarHeight = barHeight
        let width = contentView.bounds.width

        if let tree = contentView.subviews.first {
            var frame = tree.frame
            frame.size.height -= barHeight
            tree.frame = frame
        }

        let bar = CockpitFilterBar(frame: NSRect(x: 0,
                                                 y: contentView.bounds.height - barHeight,
                                                 width: width,
                                                 height: barHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.onResize = { [weak self] in self?.layoutStatusFilterControl() }

        let segmented = NSSegmentedControl()
        segmented.trackingMode = .selectOne
        segmented.controlSize = .small
        segmented.target = self
        segmented.action = #selector(statusFilterSegmentChanged(_:))
        segmented.isHidden = true
        statusFilterSegmented = segmented
        bar.addSubview(segmented)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        popup.target = self
        popup.action = #selector(statusFilterPopupChanged(_:))
        popup.isHidden = true
        statusFilterButton = popup
        bar.addSubview(popup)

        let separator = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        separator.boxType = .separator
        separator.autoresizingMask = [.width, .maxYMargin]
        bar.addSubview(separator)

        contentView.addSubview(bar)
        updateStatusFilter()
    }

    @objc private func statusFilterSegmentChanged(_ sender: NSSegmentedControl) {
        applyStatusFilter(atIndex: sender.selectedSegment)
    }

    @objc private func statusFilterPopupChanged(_ sender: NSPopUpButton) {
        applyStatusFilter(atIndex: sender.indexOfSelectedItem)
    }

    private func applyStatusFilter(atIndex index: Int) {
        guard index >= 0, index < statusFilterItems.count else { return }
        statusFilter = statusFilterItems[index].status
        refresh()
    }

    // Rebuild the shared item list from the live statuses (preserving
    // the current selection when its status still exists), populate both
    // controls, then choose which one to show.
    private func updateStatusFilter() {
        let total = statusCounts.values.reduce(0, +)
        let statuses = statusCounts.keys.sorted { statusSortKey($0) < statusSortKey($1) }
        // Drop a filter whose status vanished.
        if let statusFilter, !statuses.contains(statusFilter) {
            self.statusFilter = nil
        }
        // Localize the no-status sentinel for display only; the filter key stays stable.
        let noStatusHeader = String(localized: "Cockpit.NoStatusHeader", defaultValue: "No status", comment: "Cockpit group header for sessions that have no status")
        statusFilterItems = [(title: String(localized: "Cockpit.FilterAll", defaultValue: "All (\(total))", comment: "Status filter menu item showing the total count of all sessions"), status: nil)]
            + statuses.map { status in
                let displayStatus = (status == Self.noStatusLabel) ? noStatusHeader : status
                return (title: "\(displayStatus) (\(statusCounts[status] ?? 0))", status: status)
            }

        let selectedIndex = statusFilterItems.firstIndex { $0.status == statusFilter } ?? 0

        if let segmented = statusFilterSegmented {
            segmented.segmentCount = statusFilterItems.count
            for (i, item) in statusFilterItems.enumerated() {
                segmented.setLabel(item.title, forSegment: i)
            }
            segmented.selectedSegment = selectedIndex
            segmented.sizeToFit()
        }
        if let popup = statusFilterButton {
            popup.removeAllItems()
            popup.addItems(withTitles: statusFilterItems.map { $0.title })
            popup.selectItem(at: selectedIndex)
            popup.sizeToFit()
        }
        layoutStatusFilterControl()
    }

    // Show the segmented control if it fits across the bar; otherwise the
    // popup button. Called on refresh and on bar resize.
    private func layoutStatusFilterControl() {
        guard let segmented = statusFilterSegmented,
              let popup = statusFilterButton,
              let bar = segmented.superview else {
            return
        }
        let leading: CGFloat = 8
        let available = bar.bounds.width - leading * 2
        let fits = segmented.frame.width <= available
        segmented.isHidden = !fits
        popup.isHidden = fits
        let control: NSView = fits ? segmented : popup
        let height = control.frame.height
        control.frame = NSRect(x: leading,
                               y: (bar.bounds.height - height) / 2.0,
                               width: fits ? segmented.frame.width : max(160, popup.frame.width),
                               height: height)
    }

    // The profile's ASCII font, used for the composer per the request
    // that it match a terminal. Falls back to a fixed-pitch system font.
    private func profileASCIIFont() -> NSFont {
        // KEY_NORMAL_FONT ("Normal Font") is a #define not visible to
        // Swift; the key string is stable across releases.
        let profile = ProfileModel.sharedInstance()?.defaultProfile()
        if let desc = profile?["Normal Font"] as? String,
           let font = ITAddressBookMgr.font(withDesc: desc, ligaturesEnabled: false) {
            return font
        }
        return NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
    }

    // Dock the real composer along the bottom of the content view, 12
    // lines tall, and inset the tree above it. The panel uses
    // autoresizing masks (see Cockpit.xib), not auto layout, so the
    // composer pins to the bottom with a flexible top margin and the
    // tree keeps a fixed bottom inset while it grows to fill the rest.
    private func configureCommandBar() {
        guard let contentView = window?.contentView else {
            RLog("Cockpit: no content view; cannot build command bar")
            return
        }
        let font = profileASCIIFont()
        let lineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        // 12 text lines plus the composer's own vertical insets and the
        // accessory row (top 11 + bottom 19 in standard mode) so the tip
        // sits below a full 12 visible lines.
        composerBarHeight = ceil(lineHeight * 12) + 40
        composerTipHeight = 20
        let width = contentView.bounds.width

        // The split view (the XIB's first subview) now hosts BOTH the list
        // and the composer as draggable panes, so it only has to clear the
        // bottom tip line. Full width; each pane insets its own content 8pt
        // so the list card and composer card line up.
        guard let splitView = contentView.subviews.first as? NSSplitView else {
            RLog("Cockpit: first subview is not the split view; cannot build command bar")
            return
        }
        // Span the full width, from just above the tip line to just below the
        // filter bar. (Set absolutely rather than adjusting the XIB frame so
        // the bottom lands exactly on the tip line.)
        splitView.frame = NSRect(x: 0,
                                 y: composerTipHeight,
                                 width: width,
                                 height: contentView.bounds.height - stateFilterBarHeight - composerTipHeight)

        // A hint line pinned along the very bottom, under the split view.
        // Doubles as the send-status line.
        let tip = NSTextField(labelWithString: Self.defaultCockpitTip)
        tip.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        tip.textColor = .secondaryLabelColor
        tip.alignment = .center
        tip.lineBreakMode = .byTruncatingTail
        tip.frame = NSRect(x: 8, y: 0, width: width - 16, height: composerTipHeight)
        tip.autoresizingMask = [.width, .maxYMargin]
        composerTipLabel = tip
        contentView.addSubview(tip)

        composerVC.delegate = self
        composerVC.isAutoComposer = false
        // Opt in to the cockpit-only hooks; harmless everywhere else.
        composerVC.forwardsTextChangesAlways = true
        _ = composerVC.view  // force the nib to load before configuring
        composerVC.setFont(font)
        composerVC.setDockedChromeHidden(true)
        composerVC.setTextColor(.labelColor, cursorColor: .labelColor)
        // Let @-mention chips (NSTextAttachments) survive editing; the
        // composer is plain-text by default and would strip them.
        composerVC.setComposerRichTextEnabled(true)
        composerVC.setComposerPlaceholder(String(localized: "Cockpit.ComposerPlaceholder", defaultValue: "Type here to write to selected sessions…", comment: "Placeholder text in the cockpit composer field"))
        // No host/scope: the cockpit has no shell, and suggestions are
        // suppressed (see minimalComposerShouldFetchSuggestions), so the
        // shell-completion path that would use them is never reached.

        // Add the composer as the bottom pane. configureSplitView sets
        // arrangesAllSubviews=true so both direct subviews (the list's pane,
        // already present, and this composer) are laid out as panes; without
        // that the XIB's arrangesAllSubviews=NO left the composer floating,
        // overlapping the list.
        composerVC.view.autoresizingMask = [.width, .height]
        splitView.addSubview(composerVC.view)
        configureSplitView(splitView)
        composerVC.updateFrame()
    }

    // Turn the XIB's (single-pane, vertical) split view into a horizontal
    // one with a draggable divider so the user can trade vertical space
    // between the session list (top) and the composer (bottom). Uses the
    // classic frame-based split-view API to match the rest of this window.
    private func configureSplitView(_ splitView: NSSplitView) {
        // Treat every direct subview as a pane (the XIB set this NO, which
        // left the composer floating over the list).
        splitView.arrangesAllSubviews = true
        splitView.isVertical = false
        splitView.dividerStyle = .paneSplitter
        splitView.delegate = self
        // When the window grows vertically, the list absorbs the extra space
        // and the composer keeps the height the user set (higher holding
        // priority resists resizing).
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 0)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)
        // Persist the user's divider position locally (NoSync: it's UI state,
        // not a real setting). Only seed a default the first time, so a saved
        // position is never clobbered.
        splitView.autosaveName = Self.splitAutosaveName
        let autosaveKey = "NSSplitView Subview Frames \(Self.splitAutosaveName)"
        if UserDefaults.standard.object(forKey: autosaveKey) == nil {
            let total = splitView.bounds.height
            let position = total - composerBarHeight - splitView.dividerThickness
            if position > 0 {
                splitView.setPosition(position, ofDividerAt: 0)
            }
        }
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

    // The menu/hotkey entry point: bring the panel forward and land the
    // caret directly in the command bar so directing a message is
    // keyboard-only from the first keystroke.
    @objc func showAndFocusCommand() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        composerVC.makeFirstResponder()
    }

    // MARK: - Toolbar actions

    // Give the settings item a real bordered button (so the popover has
    // a view to anchor to; the XIB reserves it as a plain placeholder),
    // then reflect the current mode. The button stays in place across
    // mode switches, so nothing in the toolbar shifts.
    private func configureSettingsToolbarItem() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: SFSymbol.gearshape.rawValue,
                               accessibilityDescription: String(localized: "Cockpit.SettingsAccessibility", defaultValue: "Settings", comment: "Accessibility description for the settings toolbar button"))
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(showSettings(_:))
        settingsButton = button
        settingsToolbarItem.view = button
        updateSettingsButtonEnabled()
    }

    // The settings popover only configures status-priority ordering, so
    // it's meaningful only in Session Status grouping; disable it (in
    // place, no layout shift) in the other modes.
    private func updateSettingsButtonEnabled() {
        settingsButton?.isEnabled = (groupMode == .byStatus)
    }

    // Open the shared status-priority settings popover (the same one the
    // Session Status tool the cockpit mirrors uses), anchored to the
    // settings button.
    @IBAction func showSettings(_ sender: Any?) {
        guard let anchor = (sender as? NSView) ?? settingsButton else {
            return
        }
        StatusPrioritySettings.shared.showSettingsPopover(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .maxY)
    }

    @IBAction func groupModeChanged(_ sender: Any?) {
        guard let segmented = sender as? NSSegmentedControl,
              let mode = CockpitGroupMode(rawValue: segmented.selectedSegment) else {
            return
        }
        groupMode = mode
    }

    // Toggle notify-on-status-change for the selected row's entity. Window
    // rows toggle the per-window watch; session rows toggle the per-session
    // watch. The controller posts a change notification that drives the
    // row indicators and this item's appearance.
    @IBAction func toggleNotify(_ sender: Any?) {
        let controller = NotifyOnStatusChangeController.instance
        switch selectedRow()?.kind {
        case .window(let guid):
            controller.toggleWindowArmed(forGuid: guid)
        case .session(let guid):
            controller.toggleSessionArmed(forGuid: guid)
        default:
            break
        }
        updateNotifyToolbarItem()
    }

    // The selected row, or nil if nothing (or a non-selectable row) is
    // selected.
    private func selectedRow() -> CockpitRow? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? CockpitRow
    }

    // Bell image reflects whether the selected entity is armed; the item is
    // disabled when the selection isn't a window or session.
    private func updateNotifyToolbarItem() {
        let controller = NotifyOnStatusChangeController.instance
        let armed: Bool
        let enabled: Bool
        switch selectedRow()?.kind {
        case .window(let guid):
            armed = controller.isWindowArmed(forGuid: guid)
            enabled = true
        case .session(let guid):
            armed = controller.isSessionArmed(forGuid: guid)
            enabled = true
        default:
            armed = false
            enabled = false
        }
        let symbol: SFSymbol = armed ? .bellBadge : .bell
        notifyToolbarItem.image = NSImage(systemSymbolName: symbol.rawValue,
                                          accessibilityDescription: String(localized: "Cockpit.NotifyAccessibility", defaultValue: "Notify on status change", comment: "Accessibility description for the notify toolbar button"))
        notifyToolbarItem.isEnabled = enabled
        notifyToolbarItem.toolTip = armed
            ? String(localized: "Cockpit.NotifyWatchingTooltip", defaultValue: "Watching for a status change on the selected item. An alert will appear on the next change, then turn this off.", comment: "Tooltip for the notify button when it is armed and watching for a status change")
            : String(localized: "Cockpit.NotifyTooltip", defaultValue: "Notify with an alert when the selected window or session’s status changes.", comment: "Tooltip for the notify button when it is not armed")
    }

    @objc private func notifyArmedDidChange(_ notification: Notification) {
        // Armed state changed somewhere (here, the Window menu, the Status
        // tool, or a fired alert). Refresh row indicators and the bell.
        scheduleRefresh()
        updateNotifyToolbarItem()
    }

    // MARK: - Selection

    @objc private func rowDoubleClicked(_ sender: Any?) {
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
        // vs inactive peers here. (The controller's
        // revealSession(withGUID:) is nowadays the same lookup + reveal;
        // resolving the session here just lets us bail explicitly when
        // the guid no longer exists.)
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

    // MARK: - Command bar

    // Sessions under the outline's current row selection (the mouse
    // path), walking the model tree so a collapsed window/tab/workgroup
    // row still targets every session beneath it. Deduped. Used only as
    // the fallback target when the command carries no @-mention.
    private func selectedRowSessions() -> [PTYSession] {
        var guids: [String] = []
        var seen = Set<String>()
        for index in outlineView.selectedRowIndexes {
            guard let row = outlineView.item(atRow: index) as? CockpitRow else {
                continue
            }
            collectSessionGuids(row, into: &guids, seen: &seen)
        }
        return resolveGuids(guids)
    }

    private func collectSessionGuids(_ row: CockpitRow,
                                     into guids: inout [String],
                                     seen: inout Set<String>) {
        if case .session(let guid) = row.kind, seen.insert(guid).inserted {
            guids.append(guid)
        }
        for child in row.children {
            collectSessionGuids(child, into: &guids, seen: &seen)
        }
    }

    // Every session the cockpit currently lists. Walks the model tree,
    // so it honors the active group mode and search filter: @all and
    // @working address exactly what the user sees, not a hidden superset.
    private func allModelSessions() -> [PTYSession] {
        var guids: [String] = []
        var seen = Set<String>()
        for row in rootRows {
            collectSessionGuids(row, into: &guids, seen: &seen)
        }
        return resolveGuids(guids)
    }

    private func resolveGuids(_ guids: [String]) -> [PTYSession] {
        let controller = iTermController.sharedInstance()
        return guids.compactMap { controller?.anySession(withGUID: $0) }
    }

    private func modelSessions(inState state: SessionState) -> [PTYSession] {
        return allModelSessions().filter { sessionState(for: $0) == state }
    }

    // Resolve one @-token (leading '@' included) to its sessions.
    // Case-insensitive keywords (@all / @working / @waiting / @idle)
    // fan out; anything else is a session reference (a stableID inserted
    // by the picker, or a legacy guid) resolved through
    // anySession(forReference:). Empty means the token matched nothing.
    private func sessions(forToken token: String) -> [PTYSession] {
        let body = String(token.dropFirst())
        switch body.lowercased() {
        case "all": return allModelSessions()
        case "working": return modelSessions(inState: .working)
        case "waiting": return modelSessions(inState: .waiting)
        case "idle": return modelSessions(inState: .idle)
        default:
            break
        }
        // A tab mention fans out to every pane; a window mention to every
        // session in the window.
        if body.hasPrefix("tab:"), let uniqueId = Int(body.dropFirst(4)) {
            return sessions(inTabWithUniqueId: uniqueId)
        }
        if body.hasPrefix("win:") {
            return sessions(inWindowWithGuid: String(body.dropFirst(4)))
        }
        if let session = iTermController.sharedInstance()?.anySession(forReference: body) {
            return [session]
        }
        return []
    }

    private func sessions(inTabWithUniqueId uniqueId: Int) -> [PTYSession] {
        for terminal in iTermController.sharedInstance()?.terminals() ?? [] {
            if let tab = terminal.tab(withUniqueId: Int32(uniqueId)) {
                return tab.sessions()
            }
        }
        return []
    }

    private func sessions(inWindowWithGuid guid: String) -> [PTYSession] {
        guard let terminal = terminal(forGuid: guid) else {
            return []
        }
        return terminal.allSessions()
    }

    private func resolveTargets(_ tokens: [String]) -> (sessions: [PTYSession], unknown: [String]) {
        var result: [PTYSession] = []
        var seen = Set<String>()
        var unknown: [String] = []
        for token in tokens {
            let matched = sessions(forToken: token)
            if matched.isEmpty {
                unknown.append(token)
                continue
            }
            for session in matched where seen.insert(session.guid).inserted {
                result.append(session)
            }
        }
        return (result, unknown)
    }

    // Show a transient message in the tip line under the composer (in
    // place of a screen-center toast), reverting to the default hint
    // after a few seconds. Errors are tinted red.
    private func setCockpitStatus(_ message: String, isError: Bool) {
        guard let label = composerTipLabel else { return }
        tipResetItem?.cancel()
        label.stringValue = message
        label.textColor = isError ? .systemRed : .secondaryLabelColor
        let item = DispatchWorkItem { [weak self] in
            self?.composerTipLabel?.stringValue = Self.defaultCockpitTip
            self?.composerTipLabel?.textColor = .secondaryLabelColor
        }
        tipResetItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    // CR matches what pressing Return sends and is what raw-mode TUIs
    // (the agents this panel exists for) require.
    private func commandByAppendingTerminator(_ command: String) -> String {
        if command.hasSuffix("\n") || command.hasSuffix("\r") {
            return command
        }
        return command + "\r"
    }

    // Send the command view's contents. Mention chips are targets no
    // matter where they sit and are stripped from the command entirely;
    // the command is the typed (non-chip) text, sent verbatim (a typed
    // "@x" that never became a chip is literal text, not a target). With no
    // chips, the command goes to the selected rows. On success the view
    // clears (chips repopulated from the selection). Anything that would
    // send to nowhere reports a status and leaves the text in place.
    fileprivate func sendCommandFieldContents() {
        mentionPicker.hide()

        // Split the composer into chip targets (anywhere) and the typed
        // text, so a chip embedded mid-text never leaks into the command.
        let attributed = composerVC.attributedStringValue
        let ns = attributed.string as NSString
        var chipTokens: [String] = []
        var typed = ""
        attributed.enumerateAttribute(.attachment,
                                      in: NSRange(location: 0, length: attributed.length),
                                      options: []) { value, range, _ in
            if let mention = value as? ChatSessionMentionAttachment {
                chipTokens.append("@" + mention.guid)
            } else if value == nil {
                typed += ns.substring(with: range)
            }
        }

        // Only chips are targets; every typed character (including any
        // literal '@x' that never became a chip) is sent verbatim.
        let command = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        DLog("Cockpit send: chips=\(chipTokens) command=\(command)")

        let sessions: [PTYSession]
        if chipTokens.isEmpty {
            guard !command.isEmpty else { return }
            sessions = selectedRowSessions()
            guard !sessions.isEmpty else {
                setCockpitStatus(String(localized: "Cockpit.PickSessionStatus", defaultValue: "Type @ to pick a session, or select rows first", comment: "Cockpit status prompting the user to choose target sessions"), isError: true)
                return
            }
        } else {
            let (resolved, unknown) = resolveTargets(chipTokens)
            guard unknown.isEmpty else {
                setCockpitStatus(String(localized: "Cockpit.UnknownTargetStatus", defaultValue: "Unknown target \(unknown.joined(separator: " "))", comment: "Cockpit status listing unrecognized @mention targets"), isError: true)
                return
            }
            guard !command.isEmpty else {
                setCockpitStatus(String(localized: "Cockpit.AddCommandStatus", defaultValue: "Add a command after the @mention", comment: "Cockpit status prompting the user to type a command after the @mention"), isError: true)
                return
            }
            guard !resolved.isEmpty else {
                setCockpitStatus(String(localized: "Cockpit.NoMatchingSessions", defaultValue: "No matching sessions", comment: "Cockpit status shown when the targets resolve to no sessions"), isError: true)
                return
            }
            sessions = resolved
        }

        let terminated = commandByAppendingTerminator(command)
        var sent = 0
        for session in sessions where !session.exited {
            session.writeTaskNoBroadcast(terminated)
            sent += 1
        }
        guard sent > 0 else {
            setCockpitStatus(String(localized: "Cockpit.NoRunningSessions", defaultValue: "No running sessions to send to", comment: "Cockpit status shown when there are no running sessions to send a command to"), isError: true)
            return
        }
        DLog("Cockpit sent command to \(sent) session(s)")
        clearCommandView()
        setCockpitStatus(String(localized: "Cockpit.SentToSessions", defaultValue: "Sent to \(sent) sessions", comment: "Cockpit status; %lld is the number of sessions a command was sent to"), isError: false)
    }

    // After a send, drop the command text but keep the mention chips
    // (the row selection persists, so the two stay in sync and you can
    // fire again at the same targets without re-picking them).
    private func clearCommandView() {
        let chips = mentionChips(for: selectedTargets())
        let length = composerVC.attributedStringValue.length
        isSyncingTargets = true
        composerVC.replace(NSRange(location: 0, length: length), with: chips)
        isSyncingTargets = false
        activeMentionRange = nil
    }

    // A run of chips (each followed by a space) for the given targets.
    private func mentionChips(for targets: [(token: String, name: String)]) -> NSAttributedString {
        let font = profileASCIIFont()
        let result = NSMutableAttributedString()
        for target in targets {
            result.append(ChatSessionMentionAttachment.attributedString(
                guid: target.token,
                displayName: target.name,
                font: font,
                color: NSColor.linkColor,
                symbolName: symbolName(forToken: target.token)))
            result.append(NSAttributedString(string: " ",
                                             attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        }
        return result
    }

    // MARK: - @-mention session picker (reuses ChatMentionPickerController)

    // The composer supports multiple cursors, so several @-runs can be
    // in flight at once. Per the routing rule, auto-completion is always
    // aimed at the FIRST at-mention in the document: the earliest '@'
    // that starts a word and is followed by a run of non-whitespace,
    // non-token characters. Returns that run's range and the query typed
    // after '@'. nil means there is no at-mention to complete.
    private func firstMentionContext() -> (range: NSRange, query: String)? {
        let ns = composerVC.attributedStringValue.string as NSString
        let length = ns.length
        var i = 0
        while i < length {
            let c = ns.character(at: i)
            let startsWord = (i == 0) || isMentionBoundary(ns.character(at: i - 1))
            if c == UInt16(UnicodeScalar("@").value) && startsWord {
                var end = i + 1
                while end < length && !isMentionBoundary(ns.character(at: end)) {
                    end += 1
                }
                let queryRange = NSRange(location: i + 1, length: end - (i + 1))
                return (NSRange(location: i, length: end - i), ns.substring(with: queryRange))
            }
            i += 1
        }
        return nil
    }

    private func isMentionBoundary(_ c: unichar) -> Bool {
        if c == 0xFFFC { return true }  // object replacement char: an existing token
        guard let scalar = UnicodeScalar(c) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    // Drive the shared picker for the first at-mention, or hide it when
    // there is none. Called on every composer text change.
    fileprivate func updateMentionPicker() {
        guard window != nil, let context = firstMentionContext() else {
            activeMentionRange = nil
            mentionPicker.hide()
            return
        }
        activeMentionRange = context.range
        if mentionPicker.isVisible {
            mentionPicker.update(query: context.query)
        } else {
            mentionPicker.show(anchorView: composerVC.completionAnchorView,
                               query: context.query) { [weak self] guid, displayName in
                self?.insertMention(guid: guid, displayName: displayName)
            }
        }
    }

    // The chip icon for a target token: window, tab, or (default)
    // session. Matches the window/tab/pane glyphs used elsewhere (the
    // Companion app's session tree): macwindow / folder / terminal.
    private func symbolName(forToken token: String) -> String {
        if token.hasPrefix("win:") {
            return SFSymbol.macwindow.rawValue
        }
        if token.hasPrefix("tab:") {
            return SFSymbol.folder.rawValue
        }
        return SFSymbol.terminal.rawValue
    }

    // Replace the first at-mention run with an atomic chip token.
    private func insertMention(guid: String, displayName: String) {
        guard let range = firstMentionContext()?.range ?? activeMentionRange else { return }
        let font = profileASCIIFont()
        let mention = NSMutableAttributedString(
            attributedString: ChatSessionMentionAttachment.attributedString(
                guid: guid,
                displayName: displayName,
                font: font,
                color: NSColor.linkColor,
                symbolName: symbolName(forToken: guid)))
        mention.append(NSAttributedString(string: " ",
                                          attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        composerVC.replace(range, with: mention)
        activeMentionRange = nil
    }

    // MARK: - Two-way binding: composer @-mentions <-> row selection

    // The sessions currently @-mentioned as chips in the composer, in
    // document order, deduped.
    // The target tokens currently @-mentioned as chips (the chip guid,
    // e.g. a session stableID, "tab:<uid>", or "win:<guid>"), in
    // document order, deduped.
    private func composerTokens() -> [String] {
        let attr = composerVC.attributedStringValue
        var tokens: [String] = []
        var seen = Set<String>()
        attr.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: attr.length)) { value, _, _ in
            if let mention = value as? ChatSessionMentionAttachment, seen.insert(mention.guid).inserted {
                tokens.append(mention.guid)
            }
        }
        return tokens
    }

    // The (token, display name) targets for the current row selection. A
    // window or tab row is a single container target; a session row is a
    // session target; a status/workgroup group expands to its sessions.
    private func selectedTargets() -> [(token: String, name: String)] {
        let controller = iTermController.sharedInstance()
        var out: [(token: String, name: String)] = []
        var seen = Set<String>()
        func add(_ token: String, _ name: String) {
            if seen.insert(token).inserted {
                out.append((token, name))
            }
        }
        for index in outlineView.selectedRowIndexes {
            guard let row = outlineView.item(atRow: index) as? CockpitRow else { continue }
            switch row.kind {
            case .window(let guid):
                add("win:\(guid)", row.title)
            case .tab(let uniqueId):
                add("tab:\(uniqueId)", row.title)
            case .session(let guid):
                if let session = controller?.anySession(withGUID: guid) {
                    add(session.stableID, ChatMentionDisplay.displayName(for: session))
                }
            case .group, .buriedRoot, .workgroup:
                var guids: [String] = []
                var innerSeen = Set<String>()
                collectSessionGuids(row, into: &guids, seen: &innerSeen)
                for guid in guids {
                    if let session = controller?.anySession(withGUID: guid) {
                        add(session.stableID, ChatMentionDisplay.displayName(for: session))
                    }
                }
            }
        }
        return out
    }

    // Composer chips changed -> select the rows those targets name. Only
    // acts when the target set actually differs, so a container-row
    // selection whose expansion matches isn't needlessly rewritten.
    fileprivate func syncSelectionFromComposer() {
        guard !isSyncingTargets else { return }
        let chips = Set(composerTokens())
        guard chips != Set(selectedTargets().map { $0.token }) else { return }
        let controller = iTermController.sharedInstance()
        var desired = IndexSet()
        for row in 0..<outlineView.numberOfRows {
            guard let item = outlineView.item(atRow: row) as? CockpitRow else { continue }
            let matches: Bool
            switch item.kind {
            case .window(let guid):
                matches = chips.contains("win:\(guid)")
            case .tab(let uniqueId):
                matches = chips.contains("tab:\(uniqueId)")
            case .session(let guid):
                matches = (controller?.anySession(withGUID: guid)?.stableID).map { chips.contains($0) } ?? false
            case .group, .buriedRoot, .workgroup:
                matches = false
            }
            if matches {
                desired.insert(row)
            }
        }
        isSyncingTargets = true
        outlineView.selectRowIndexes(desired, byExtendingSelection: false)
        isSyncingTargets = false
    }

    // Row selection changed -> rewrite the composer's chips to match,
    // preserving the typed command. Only fires when the target set
    // actually differs, so it never clobbers the command or caret on a
    // no-op reselection.
    fileprivate func syncComposerFromSelection() {
        guard !isSyncingTargets else { return }
        let targets = selectedTargets()
        guard Set(targets.map { $0.token }) != Set(composerTokens()) else { return }
        isSyncingTargets = true
        setComposerMentions(targets)
        isSyncingTargets = false
    }

    // Replace the composer's contents with chips for `targets` (in
    // order) followed by the existing command text (everything that
    // isn't a mention chip, with leading whitespace trimmed).
    private func setComposerMentions(_ targets: [(token: String, name: String)]) {
        let attr = composerVC.attributedStringValue
        let ns = attr.string as NSString
        let command = NSMutableString()
        attr.enumerateAttribute(.attachment,
                                in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            if value == nil {
                command.append(ns.substring(with: range))
            }
        }
        let commandText = String(command).drop { $0 == " " || $0 == "\t" }
        let font = profileASCIIFont()
        let result = NSMutableAttributedString(attributedString: mentionChips(for: targets))
        result.append(NSAttributedString(string: String(commandText),
                                         attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
        composerVC.replace(NSRange(location: 0, length: attr.length), with: result)
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
        // A status bucket in byStatus mode. `status` is the session's
        // arbitrary reported status text (or a "No status" sentinel).
        case group(scope: String, status: String)
        case session(guid: String)
    }
    enum Identity: Hashable {
        case window(String)
        case buriedRoot
        case workgroup(String)
        case tab(Int)
        case group(String, String)
        case session(String)
    }
    let identity: Identity
    let kind: Kind
    var title: String
    // Secondary line shown under the title in a smaller, dimmer font:
    // the session's live detail string. Shown for session rows in every
    // grouping mode; nil elsewhere (a plain single-line row).
    var detail: String?
    // The session's live, arbitrary status text (e.g. "Waiting",
    // "Testing") and its color, for the trailing status word and the
    // status filter. nil for non-session rows / no reported status.
    var status: String?
    var statusColor: NSColor?
    // True when this window or session has notify-on-status-change armed.
    // The cell shows a trailing bell when set. Only window and session
    // rows ever set it.
    var armed: Bool = false
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
        case .byStatus: return String(localized: "Cockpit.GroupByStatusLabel", defaultValue: "Status", comment: "Short label for the group-by-status option in the cockpit")
        case .byWindow: return String(localized: "Cockpit.GroupByWindowLabel", defaultValue: "Window", comment: "Short label for the group-by-window option in the cockpit")
        case .byWorkgroup: return String(localized: "Cockpit.GroupByWorkgroupLabel", defaultValue: "Workgroup", comment: "Short label for the group-by-workgroup option in the cockpit")
        }
    }

    var tooltip: String {
        switch self {
        case .byStatus:
            return String(localized: "Cockpit.GroupByStatusTooltip", defaultValue: "Group sessions by status (Waiting / Working / Idle), within each window.", comment: "Tooltip for the group-by-status option in the cockpit")
        case .byWindow:
            return String(localized: "Cockpit.GroupByWindowTooltip", defaultValue: "Group sessions by window, then by tab and split pane.", comment: "Tooltip for the group-by-window option in the cockpit")
        case .byWorkgroup:
            return String(localized: "Cockpit.GroupByWorkgroupTooltip", defaultValue: "Show only sessions in a workgroup, grouped by workgroup.", comment: "Tooltip for the group-by-workgroup option in the cockpit")
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
// Indicator-only image view that never intercepts mouse clicks, so a
// click on (or near) the bell still selects/reveals the row the same as
// clicking the text.
fileprivate final class CockpitPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

// The status filter bar. Calls `onResize` when its width changes so the
// controller can switch between the segmented control and the popup
// depending on whether the options fit.
fileprivate final class CockpitFilterBar: NSView {
    var onResize: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize.width != frame.width
        super.setFrameSize(newSize)
        if changed {
            onResize?()
        }
    }
}

// The rounded "card" behind the session list. Draws its own fill + border
// with a bezier path so the corners stay crisp (masksToBounds on a scroll
// view shaves the border stroke at the corners). Its scroll view child is
// transparent, so this fill is what shows through, including at the rounded
// corners.
fileprivate final class CockpitListContainerView: NSView {
    private static let cornerRadius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        // Inset by half a point so the 1pt stroke sits fully inside the
        // bounds (a stroke straddles its path, so an un-inset path would
        // clip the outer half).
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: Self.cornerRadius,
                                yRadius: Self.cornerRadius)
        NSColor.textBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

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

    // Shows a trailing bell when the row's window/session has notify-on-
    // change armed.
    var cockpitArmed: Bool = false {
        didSet {
            if cockpitArmed != oldValue {
                bellView?.isHidden = !cockpitArmed
                applyText()
                needsLayout = true
            }
        }
    }

    // Leading kind icon (window / tab / session / …). nil hides it.
    var cockpitIconSymbolName: String? {
        didSet {
            if cockpitIconSymbolName != oldValue {
                updateIcon()
                needsLayout = true
            }
        }
    }

    // Trailing status word for a session row (state), tinted by state
    // color. nil hides it.
    var cockpitState: (text: String, color: NSColor)? {
        didSet {
            if cockpitState?.text != oldValue?.text || cockpitState?.color != oldValue?.color {
                updateStateLabel()
                needsLayout = true
            }
        }
    }

    private var detailField: NSTextField?
    private var renderedDetail: NSAttributedString?
    private var bellView: NSImageView?
    private var iconView: NSImageView?
    private var stateLabel: NSTextField?
    private static let bellSize: CGFloat = 14
    private static let bellGap: CGFloat = 4
    private static let iconSize: CGFloat = 15
    private static let iconGap: CGFloat = 5
    private static let stateLabelFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private static let stateLabelTrailing: CGFloat = 8

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

    // The title field comes from the xib; the detail field and bell
    // indicator are added programmatically. All are positioned by hand in
    // layout() (no auto layout), so opt them out of constraint generation
    // and clear the xib's autoresizing so our frames are authoritative.
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

        let bell = CockpitPassthroughImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        bell.image = NSImage(systemSymbolName: SFSymbol.bellBadge.rawValue,
                             accessibilityDescription: String(localized: "Cockpit.NotifyArmedAccessibility", defaultValue: "Notify on status change armed", comment: "Accessibility description for the armed notify indicator on a row"))?
            .withSymbolConfiguration(config)
        bell.imageScaling = .scaleProportionallyDown
        bell.isHidden = true
        bell.translatesAutoresizingMaskIntoConstraints = true
        bell.autoresizingMask = []
        addSubview(bell)
        bellView = bell

        let icon = CockpitPassthroughImageView()
        icon.imageScaling = .scaleProportionallyDown
        icon.isHidden = true
        icon.translatesAutoresizingMaskIntoConstraints = true
        icon.autoresizingMask = []
        addSubview(icon)
        iconView = icon

        let state = NSTextField(labelWithString: "")
        state.font = Self.stateLabelFont
        state.alignment = .right
        state.lineBreakMode = .byClipping
        state.isHidden = true
        state.translatesAutoresizingMaskIntoConstraints = true
        state.autoresizingMask = []
        addSubview(state)
        stateLabel = state
    }

    private func updateStateLabel() {
        guard let stateLabel else { return }
        if let state = cockpitState {
            stateLabel.stringValue = state.text
            stateLabel.textColor = state.color
            stateLabel.isHidden = false
        } else {
            stateLabel.stringValue = ""
            stateLabel.isHidden = true
        }
    }

    private var stateLabelWidth: CGFloat {
        guard let stateLabel, !stateLabel.isHidden else { return 0 }
        return ceil(stateLabel.intrinsicContentSize.width)
    }

    private func updateIcon() {
        guard let iconView else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        if let name = cockpitIconSymbolName,
           let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            iconView.image = image
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        applyIconTint()
    }

    private func applyIconTint() {
        iconView?.contentTintColor = (backgroundStyle == .emphasized)
            ? .alternateSelectedControlTextColor
            : .controlAccentColor
    }

    override func layout() {
        super.layout()
        guard let textField else { return }
        // Leading run: the kind icon, then (when armed) the notify bell,
        // then the text pushed right to make room for both.
        let hasIcon = (iconView?.isHidden == false)
        let iconLeading = hasIcon ? (Self.iconSize + Self.iconGap) : 0
        let armed = (bellView?.isHidden == false)
        let bellLeading = armed ? (Self.bellSize + Self.bellGap) : 0
        let leading = iconLeading + bellLeading
        // Reserve room at the trailing edge for the state word.
        let stateWidth = stateLabelWidth
        let trailing = stateWidth > 0 ? (stateWidth + Self.stateLabelTrailing * 2) : 0
        let width = max(0, bounds.width - leading - trailing)
        let titleHeight = ceil(textField.intrinsicContentSize.height)
        let titleTop: CGFloat
        if let detailField, !detailField.isHidden {
            let detailHeight = ceil(detailField.intrinsicContentSize.height)
            let total = titleHeight + Self.detailSpacing + detailHeight
            titleTop = max(0, (bounds.height - total) / 2)
            textField.frame = NSRect(x: leading, y: titleTop, width: width, height: titleHeight)
            detailField.frame = NSRect(x: leading,
                                       y: titleTop + titleHeight + Self.detailSpacing,
                                       width: width,
                                       height: detailHeight)
        } else {
            titleTop = (bounds.height - titleHeight) / 2
            textField.frame = NSRect(x: leading, y: titleTop, width: width, height: titleHeight)
        }
        // Vertically center the icon/bell on the title line, not the whole
        // cell, so they line up with the name even with a detail line.
        if hasIcon, let iconView {
            iconView.frame = NSRect(x: 0,
                                    y: titleTop + (titleHeight - Self.iconSize) / 2,
                                    width: Self.iconSize,
                                    height: Self.iconSize)
        }
        if let bellView, armed {
            bellView.frame = NSRect(x: iconLeading,
                                    y: titleTop + (titleHeight - Self.bellSize) / 2,
                                    width: Self.bellSize,
                                    height: Self.bellSize)
        }
        if stateWidth > 0, let stateLabel {
            let labelHeight = ceil(stateLabel.intrinsicContentSize.height)
            stateLabel.frame = NSRect(x: bounds.width - stateWidth - Self.stateLabelTrailing,
                                      y: titleTop + (titleHeight - labelHeight) / 2,
                                      width: stateWidth,
                                      height: labelHeight)
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
        bellView?.contentTintColor = emphasized
            ? .alternateSelectedControlTextColor
            : .controlAccentColor
        applyIconTint()
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

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateNotifyToolbarItem()
        syncComposerFromSelection()
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
        cell.cockpitArmed = row.armed
        cell.cockpitIconSymbolName = iconSymbolName(for: row.kind)
        cell.cockpitState = row.status.map {
            (text: $0, color: row.statusColor ?? .secondaryLabelColor)
        }
        return cell
    }

    // Leading icon per row kind, matching the chip glyphs and the
    // Companion app's session tree (macwindow / folder / terminal).
    // Status-bucket group rows are sub-headers and get no icon.
    private func iconSymbolName(for kind: CockpitRow.Kind) -> String? {
        switch kind {
        case .window:
            return SFSymbol.macwindow.rawValue
        case .tab:
            return SFSymbol.folder.rawValue
        case .session:
            return SFSymbol.terminal.rawValue
        case .workgroup:
            return SFSymbol.rectangle3Group.rawValue
        case .buriedRoot:
            return SFSymbol.archivebox.rawValue
        case .group:
            return nil
        }
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
        // Notify-on-change arming updates both the row indicators and the
        // bell toolbar item, so it gets its own handler.
        center.addObserver(self,
                           selector: #selector(notifyArmedDidChange(_:)),
                           name: NotifyOnStatusChangeController.armedDidChangeNotification,
                           object: nil)
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
        updateStatusFilter()
        // With a filter active the surviving matches must be visible, so
        // expand every container (otherwise a collapsed window hides the
        // sessions the filter kept).
        if !filter.isEmpty || statusFilter != nil {
            outlineView.expandItem(nil, expandChildren: true)
        }
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
        statusCounts = Self.countStatuses(in: rebuiltRoots)
        let pruned = (filter.isEmpty && statusFilter == nil)
            ? rebuiltRoots
            : Self.prune(rebuiltRoots, needle: filter.lowercased(), status: statusFilter, keptCache: &freshCache)
        rowCache = freshCache
        rootRows = pruned
    }

    // Session counts keyed by status text (no-status folded under the
    // sentinel), for the filter menu.
    private static func countStatuses(in roots: [CockpitRow]) -> [String: Int] {
        var counts: [String: Int] = [:]
        func walk(_ row: CockpitRow) {
            if case .session = row.kind {
                counts[row.status ?? Self.noStatusLabel, default: 0] += 1
            }
            for child in row.children {
                walk(child)
            }
        }
        roots.forEach(walk)
        return counts
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
                              needle: String,
                              status: String?,
                              keptCache: inout [CockpitRow.Identity: CockpitRow]) -> [CockpitRow] {
        var kept: [CockpitRow] = []
        for row in rows {
            if let surviving = pruneRow(row, needle: needle, status: status, keptCache: &keptCache) {
                kept.append(surviving)
            }
        }
        return kept
    }

    private static func pruneRow(_ row: CockpitRow,
                                 needle: String,
                                 status: String?,
                                 keptCache: inout [CockpitRow.Identity: CockpitRow]) -> CockpitRow? {
        switch row.kind {
        case .session:
            let textOk = needle.isEmpty || row.title.lowercased().contains(needle)
            let statusOk = status == nil || (row.status ?? Self.noStatusLabel) == status
            if textOk && statusOk {
                return row
            }
            keptCache.removeValue(forKey: row.identity)
            return nil
        case .window, .buriedRoot, .workgroup, .tab, .group:
            var keptChildren: [CockpitRow] = []
            for child in row.children {
                if let survivor = pruneRow(child, needle: needle, status: status, keptCache: &keptCache) {
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
            windowRow.armed = NotifyOnStatusChangeController.instance.isWindowArmed(forGuid: windowGuid)
            freshCache[windowIdentity] = windowRow
            let expanded = expandWithPeers(terminal.allSessions(),
                                            alreadySeen: &alreadySeen)
            windowRow.children = bucketSessionsByStatus(
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
                              title: String(localized: "Cockpit.BuriedSessions", defaultValue: "Buried Sessions", comment: "Title of the row grouping buried sessions in the cockpit"))
            buriedRow.title = String(localized: "Cockpit.BuriedSessions", defaultValue: "Buried Sessions", comment: "Title of the row grouping buried sessions in the cockpit")
            buriedRow.armed = false
            freshCache[identity] = buriedRow
            buriedRow.children = bucketSessionsByStatus(
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
            windowRow.armed = NotifyOnStatusChangeController.instance.isWindowArmed(forGuid: windowGuid)
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
                              title: String(localized: "Cockpit.BuriedSessions", defaultValue: "Buried Sessions", comment: "Title of the row grouping buried sessions in the cockpit"))
            buriedRow.title = String(localized: "Cockpit.BuriedSessions", defaultValue: "Buried Sessions", comment: "Title of the row grouping buried sessions in the cockpit")
            buriedRow.armed = false
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
            row.armed = false
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
            // The session's self-reported detail and state are shown in
            // every grouping mode now, not just byStatus.
            row.detail = cockpitDetailText(for: session)
            let status = cockpitStatus(for: session)
            row.status = status?.text
            row.statusColor = status?.color
            row.armed = NotifyOnStatusChangeController.instance.isSessionArmed(forGuid: session.guid)
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

    private func bucketSessionsByStatus(_ sessions: [PTYSession],
                                        scope: String,
                                        freshCache: inout [CockpitRow.Identity: CockpitRow]) -> [CockpitRow] {
        var bucketed: [String: [CockpitRow]] = [:]
        for session in sessions {
            let status = cockpitStatus(for: session)
            let bucketKey = status?.text ?? Self.noStatusLabel
            let identity = CockpitRow.Identity.session(session.guid)
            let title = cockpitSessionTitle(for: session)
            let row = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .session(guid: session.guid),
                              title: title)
            row.title = title
            row.detail = cockpitDetailText(for: session)
            row.status = status?.text
            row.statusColor = status?.color
            row.armed = NotifyOnStatusChangeController.instance.isSessionArmed(forGuid: session.guid)
            row.children = []
            freshCache[identity] = row
            bucketed[bucketKey, default: []].append(row)
        }

        var groupRows: [CockpitRow] = []
        for status in bucketed.keys.sorted(by: { statusSortKey($0) < statusSortKey($1) }) {
            let members = bucketed[status] ?? []
            if members.isEmpty { continue }
            let identity = CockpitRow.Identity.group(scope, status)
            // Localize the no-status sentinel for display only; the bucket key stays stable.
            let displayStatus = (status == Self.noStatusLabel)
                ? String(localized: "Cockpit.NoStatusHeader", defaultValue: "No status", comment: "Cockpit group header for sessions that have no status")
                : status
            let label = "\(displayStatus) · \(members.count)"
            let groupRow = rowCache[identity]
                ?? CockpitRow(identity: identity,
                              kind: .group(scope: scope, status: status),
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
        var armedOf: [CockpitRow.Identity: Bool] = [:]
        var statusOf: [CockpitRow.Identity: String?] = [:]
        // The status text can stay the same while its color changes (e.g. a
        // tool flips from an indicator color to a red statusTextColor), so
        // the color is snapshotted separately; comparing text alone would
        // miss those and leave the old color rendered.
        var statusColorOf: [CockpitRow.Identity: NSColor?] = [:]
    }

    private func snapshotTreeShape(of roots: [CockpitRow]) -> TreeShape {
        var shape = TreeShape()
        for (i, root) in roots.enumerated() {
            shape.all.insert(root.identity)
            shape.indexOf[root.identity] = i
            shape.titleOf[root.identity] = root.title
            shape.detailOf[root.identity] = root.detail
            shape.armedOf[root.identity] = root.armed
            shape.statusOf[root.identity] = root.status
            shape.statusColorOf[root.identity] = root.statusColor
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
            shape.armedOf[child.identity] = child.armed
            shape.statusOf[child.identity] = child.status
            shape.statusColorOf[child.identity] = child.statusColor
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
            let armedChanged = old.armedOf[id] != new.armedOf[id]
            let statusChanged = old.statusOf[id] != new.statusOf[id]
                || old.statusColorOf[id] != new.statusColorOf[id]
            guard titleChanged || detailChanged || armedChanged || statusChanged,
                  let row = rowCache[id] else {
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

    // Sentinel bucket/filter key for sessions that report no status.
    // Localization unneeded: a stable sentinel used as a bucket dictionary key and in == comparisons.
    // The displayed form is localized where the group-header label is built.
    static let noStatusLabel = "No status"

    // The session's live, arbitrary status text and its color, straight
    // from the tab status (the same source the Session Status tool uses).
    // nil when the session reports no status.
    private func cockpitStatus(for session: PTYSession) -> (text: String, color: NSColor)? {
        guard let status = session.tabStatus,
              let raw = status.statusText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        let color: NSColor
        if status.hasStatusTextColor {
            color = Self.nsColor(from: status.statusTextColor)
        } else if status.hasIndicator {
            color = Self.nsColor(from: status.indicatorColor)
        } else {
            color = .secondaryLabelColor
        }
        return (raw, color)
    }

    private static func nsColor(from c: iTermSRGBColor) -> NSColor {
        return NSColor(srgbRed: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }

    // Order statuses the way the Session Status tool does (its priority
    // list), so the byStatus buckets and the filter menu read the same.
    // No-status sorts last.
    private func statusSortKey(_ status: String) -> (Int, String) {
        if status == Self.noStatusLabel {
            return (Int.max, status)
        }
        return (StatusPrioritySettings.shared.priority(for: status), status.lowercased())
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
        return String(localized: "Cockpit.TabTitle", defaultValue: "Tab \(positionInWindow)", comment: "Default title for a tab row in the cockpit; the number is the tab position in the window")
    }

    private func cockpitWindowTitlePrefix(for terminal: PseudoTerminal) -> String {
        return String(localized: "Cockpit.WindowTitle", defaultValue: "Window \(terminal.number)", comment: "Default title for a window row in the cockpit; the number is the window number")
    }

    private func cockpitWorkgroupTitle(for instance: iTermWorkgroupInstance) -> String {
        let name = instance.workgroup.name
        return name.isEmpty ? instance.instanceUniqueIdentifier : name
    }
}

// MARK: - Search

extension CockpitWindowController: NSSplitViewDelegate {
    // Minimum height for the top (list) pane: keep a few rows visible.
    private static let listMinHeight: CGFloat = 100
    // Minimum height for the bottom (composer) pane: enough for a couple of
    // lines plus the accessory row so the send tip stays visible.
    private static let composerMinHeight: CGFloat = 110

    func splitView(_ splitView: NSSplitView,
                   constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Divider position is measured from the top, so the minimum position
        // is the list pane's minimum height.
        return proposedMinimumPosition + Self.listMinHeight
    }

    func splitView(_ splitView: NSSplitView,
                   constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        // The remaining space below the divider is the composer; cap the
        // divider so the composer never shrinks past its minimum.
        return proposedMaximumPosition - Self.composerMinHeight
    }
}

extension CockpitWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField != nil else { return }
        filter = searchToolbarItem.searchField.stringValue
        // refresh() rebuilds the tree, then rebuildRows applies the
        // prune; identity-stable row reuse keeps expansion / selection
        // across filter edits.
        refresh()
    }
}

extension CockpitWindowController: iTermMinimalComposerViewControllerDelegate {
    // The composer's cockpit-only text-change hook: drive the @-mention
    // picker for the first at-mention. This is where auto-completion is
    // routed to the first at-mentioned run.
    func minimalComposerTextDidChange(_ composer: iTermMinimalComposerViewController) {
        updateMentionPicker()
        syncSelectionFromComposer()
    }

    // Send (Shift-Return) and cancel (Esc). Esc arrives as an empty
    // command with dismiss=YES; treat that as "just close the picker,"
    // never a send, and never actually dismiss the docked composer.
    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         sendCommand command: String,
                         addNewline: Bool,
                         dismiss: Bool) {
        if command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mentionPicker.hide()
            return
        }
        sendCommandFieldContents()
    }

    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         enqueueCommand command: String,
                         dismiss: Bool) {
        sendCommandFieldContents()
    }

    // Route arrow / Return to the picker while it is open. Reached before
    // the composer moves its cursor (see ComposerTextView.keyDown), so
    // navigation drives the list instead of the text.
    func minimalComposerHandleKeyDown(_ event: NSEvent) -> Bool {
        guard mentionPicker.isVisible else { return false }
        switch event.specialKey {
        case NSEvent.SpecialKey.upArrow:
            mentionPicker.moveSelectionUp()
            return true
        case NSEvent.SpecialKey.downArrow:
            mentionPicker.moveSelectionDown()
            return true
        default:
            break
        }
        if event.keyCode == 36 || event.characters == "\r" {
            mentionPicker.commitSelection()
            return true
        }
        return false
    }

    // Docked geometry: a fixed 12-line strip along the bottom.
    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         frameForHeight desiredHeight: CGFloat) -> NSRect {
        let width = window?.contentView?.bounds.width ?? composer.view.frame.width
        return NSRect(x: 0, y: composerTipHeight, width: width, height: composerBarHeight)
    }

    func minimalComposerMaximumHeight(_ composer: iTermMinimalComposerViewController) -> CGFloat {
        return composerBarHeight
    }

    func minimalComposerLineHeight(_ composer: iTermMinimalComposerViewController) -> CGFloat {
        return ceil(NSLayoutManager().defaultLineHeight(for: profileASCIIFont()))
    }

    func minimalComposerClear(_ composer: iTermMinimalComposerViewController) {
        clearCommandView()
    }

    // No shell here, so never fetch shell completions; this also keeps
    // the composer off the host/scope-dependent path.
    func minimalComposerShouldFetchSuggestions(_ composer: iTermMinimalComposerViewController,
                                               forHost remoteHost: VT100RemoteHostReading,
                                               tmuxController: TmuxController) -> Bool {
        return false
    }

    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         syntaxHighlighterFor attributedString: NSMutableAttributedString) -> SyntaxHighlighting {
        return CockpitNoopSyntaxHighlighter()
    }

    func minimalComposerNextResponder() -> NSResponder? {
        return nil
    }

    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         valueOfEnvironmentVariable name: String) -> String? {
        return nil
    }

    // Everything below is inert in the docked cockpit composer.
    func minimalComposer(_ composer: iTermMinimalComposerViewController, sendControl control: String) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, sendToAdvancedPaste content: String) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, frameDidChangeTo newFrame: NSRect) {}
    func minimalComposerOpenHistory(_ composer: iTermMinimalComposerViewController, prefix: String, forSearch: Bool) {}
    func minimalComposerShowCompletions(_ completions: [String]) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, wantsKeyEquivalent event: NSEvent) -> Bool { false }
    func minimalComposer(_ composer: iTermMinimalComposerViewController, performFindPanelAction sender: Any) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController, desiredHeightDidChange desiredHeight: CGFloat) {}
    func minimalComposerAutoComposerTextDidChange(_ composer: iTermMinimalComposerViewController) {}
    func minimalComposerShouldForwardCopy(_ composer: iTermMinimalComposerViewController) -> Bool { false }
    func minimalComposerForwardMenuItem(_ menuItem: NSMenuItem) {}
    func minimalComposerPreferredOffset(fromTopDidChange composer: iTermMinimalComposerViewController) {}
    func minimalComposerDidBecomeFirstResponder(_ composer: iTermMinimalComposerViewController) {}
    func minimalComposer(_ composer: iTermMinimalComposerViewController,
                         fetchSuggestions request: SuggestionRequest,
                         byUserRequest: Bool) {}
}

// A do-nothing syntax highlighter for the cockpit composer, which has
// no shell/color-map context to highlight against.
@MainActor
private final class CockpitNoopSyntaxHighlighter: NSObject, SyntaxHighlighting {
    func highlight(range: NSRange) {}
}

