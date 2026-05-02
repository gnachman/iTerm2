//
//  CodeReviewPromptManagerWindowController.swift
//  iTerm2SharedARC
//
//  Manages the user’s saved Code Review prompts. CRUD-style master/
//  detail UI built programmatically (no nib): a CompetentTableView on
//  the left lists prompt names; an editable text view on the right
//  shows the body of the selected prompt and writes back as you type.
//

import AppKit

@objc(iTermCodeReviewPromptManagerWindowController)
final class CodeReviewPromptManagerWindowController: NSWindowController {
    @objc static let shared = CodeReviewPromptManagerWindowController()

    private var promptTable: CompetentTableView!
    private var addRemove: NSSegmentedControl!
    private var bodyTextView: NSTextView!
    private var bodyScrollView: NSScrollView!
    private var nameField: NSTextField!
    private var emptyLabel: NSTextField!

    fileprivate var crudController: CRUDTableViewController<CodeReviewPromptManagerWindowController>?
    private var dataProvider: PromptDataProvider!

    // Suppresses the bodyTextView’s textDidChange feedback loop while
    // we’re reloading the editor from the model (e.g. on selection
    // change). Without this, programmatic .string = … fires the
    // delegate which would write the just-loaded text back to the
    // store, defeating undo and burning a no-op save.
    private var isLoadingBody = false
    private var isLoadingName = false

    // Bumped while the manager itself is mutating the store. The
    // store’s didChange notification is observed for *external*
    // writes (e.g. the overlay’s “Save Current as New…”); reacting
    // to our own writes would race CRUD’s animated removeRows /
    // insertRows, which expect the table’s cached row count to
    // still match the *pre-mutation* value when they run.
    private var localMutationDepth = 0

    fileprivate func performLocalMutation(_ block: () -> Void) {
        localMutationDepth += 1
        block()
        localMutationDepth -= 1
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Code Review Prompts"
        window.setFrameAutosaveName("CodeReviewPromptManager")
        window.minSize = NSSize(width: 560, height: 320)
        super.init(window: window)
        buildContentView()
        // Only react to structural changes — body-only mutations
        // already came from this controller, and reloading on each
        // keystroke would clobber the body editor’s cursor.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: CodeReviewPromptStore.structureDidChangeNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) is not supported")
    }

    // Defaults key NSWindow uses for the autosaved frame string.
    // We peek at it to decide whether to center on first-ever open;
    // setFrameAutosaveName itself silently leaves the window at its
    // initial (0,0) contentRect when no saved frame exists.
    private static let autosaveDefaultsKey =
        "NSWindow Frame CodeReviewPromptManager"

    @objc
    func showWindow(parent: NSWindow?) {
        // Float above the prompt overlay’s window so the manager
        // doesn’t fall behind when the user clicks back into the
        // overlay to keep editing.
        if let parent {
            window?.level = parent.level
        }
        let firstOpen = iTermUserDefaults.userDefaults()
            .string(forKey: Self.autosaveDefaultsKey) == nil
        showWindow(nil)
        if firstOpen {
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        crudController?.reload()
        syncSelectionWithStore()
        updateDetailEnabled()
    }

    private func buildContentView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        container.autoresizingMask = [.width, .height]

        let margin: CGFloat = 12
        let leftWidth: CGFloat = 220
        let segmentHeight: CGFloat = 24

        // ------ Left: list of prompt names + add/remove
        let leftScrollY = margin + segmentHeight + 6
        let leftScrollHeight = container.bounds.height - margin - leftScrollY
        let leftScroll = NSScrollView(frame: NSRect(
            x: margin,
            y: leftScrollY,
            width: leftWidth,
            height: leftScrollHeight))
        leftScroll.hasVerticalScroller = true
        leftScroll.borderType = .bezelBorder
        leftScroll.autoresizingMask = [.height, .maxXMargin]

        let table = CompetentTableView(frame: leftScroll.bounds)
        table.headerView = nil
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        // Match the cell’s natural height so the (vertically padded)
        // text field inside iTermTableCellViewWithTextField doesn’t
        // get stretched into a tall row that pulls the baseline off
        // center. Other CRUD users either configure this in IB or
        // hard-code a value (e.g. StatusPriorityViewController).
        table.rowHeight = NSTableView.heightForTextCell(
            using: .systemFont(ofSize: NSFont.systemFontSize))

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = "Name"
        nameColumn.isEditable = true
        nameColumn.width = leftWidth - 4
        table.addTableColumn(nameColumn)

        leftScroll.documentView = table
        container.addSubview(leftScroll)
        promptTable = table

        let segmented = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "plus",
                     accessibilityDescription: "Add")!,
            NSImage(systemSymbolName: "minus",
                     accessibilityDescription: "Remove")!
        ], trackingMode: .momentary, target: nil, action: nil)
        segmented.frame = NSRect(x: margin, y: margin,
                                  width: 60, height: segmentHeight)
        segmented.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(segmented)
        addRemove = segmented

        // ------ Right: name + body editor
        let rightX = margin + leftWidth + margin
        let rightWidth = container.bounds.width - rightX - margin

        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.frame = NSRect(x: rightX,
                                  y: container.bounds.height - margin - 18,
                                  width: rightWidth,
                                  height: 16)
        nameLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(nameLabel)

        let nameInput = NSTextField(frame: NSRect(
            x: rightX,
            y: nameLabel.frame.minY - 24,
            width: rightWidth,
            height: 22))
        nameInput.placeholderString = "Untitled"
        nameInput.autoresizingMask = [.width, .minYMargin]
        nameInput.delegate = self
        container.addSubview(nameInput)
        nameField = nameInput

        let bodyLabel = NSTextField(labelWithString: "Prompt:")
        bodyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.frame = NSRect(x: rightX,
                                  y: nameInput.frame.minY - 22,
                                  width: rightWidth,
                                  height: 16)
        bodyLabel.autoresizingMask = [.width, .minYMargin]
        container.addSubview(bodyLabel)

        let bodyScroll = NSScrollView(frame: NSRect(
            x: rightX,
            y: margin,
            width: rightWidth,
            height: bodyLabel.frame.minY - 4 - margin))
        bodyScroll.hasVerticalScroller = true
        bodyScroll.borderType = .bezelBorder
        bodyScroll.autoresizingMask = [.width, .height]

        let body = NSTextView(frame: bodyScroll.bounds)
        body.isRichText = false
        body.isEditable = true
        body.isSelectable = true
        body.allowsUndo = true
        body.font = .userFixedPitchFont(ofSize: NSFont.systemFontSize)
        body.minSize = .zero
        body.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                               height: CGFloat.greatestFiniteMagnitude)
        body.isVerticallyResizable = true
        body.isHorizontallyResizable = false
        body.autoresizingMask = [.width]
        body.textContainer?.widthTracksTextView = true
        body.delegate = self
        bodyScroll.documentView = body
        container.addSubview(bodyScroll)

        bodyTextView = body
        bodyScrollView = bodyScroll

        let placeholder = NSTextField(wrappingLabelWithString:
            "Select a prompt on the left to edit it, or click + to add a new prompt.")
        placeholder.font = .systemFont(ofSize: NSFont.systemFontSize)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.frame = bodyScroll.frame
        placeholder.autoresizingMask = [.width, .height]
        placeholder.isHidden = true
        container.addSubview(placeholder)
        emptyLabel = placeholder

        window?.contentView = container

        // Wire up CRUD after subviews exist.
        let provider = PromptDataProvider()
        provider.controller = self
        dataProvider = provider
        let schema = CRUDSchema(columns: [CRUDColumn(type: .string)],
                                 dataProvider: provider)
        crudController = CRUDTableViewController(tableView: table,
                                                  addRemove: segmented,
                                                  schema: schema)
        crudController?.delegate = self
    }

    // MARK: - Selection

    @objc
    private func storeDidChange(_ note: Notification) {
        // Skip writes we initiated ourselves: CRUD will animate the
        // table to match the new state on its own, and reloading
        // here would invalidate the cached row count it relies on
        // (causing crashes in removeRows/insertRows). External
        // writes — typically the overlay’s “Save Current as New…”
        // — fall through and refresh the table list.
        guard localMutationDepth == 0 else { return }
        crudController?.reload()
    }

    fileprivate func syncSelectionWithStore() {
        let store = CodeReviewPromptStore.shared
        if let uuid = store.lastSelectedUUID,
           let row = store.index(ofUUID: uuid) {
            promptTable.selectRowIndexes(IndexSet(integer: row),
                                          byExtendingSelection: false)
            promptTable.scrollRowToVisible(row)
        } else if !store.prompts.isEmpty {
            promptTable.selectRowIndexes(IndexSet(integer: 0),
                                          byExtendingSelection: false)
        }
        loadDetailFromSelection()
    }

    private func loadDetailFromSelection() {
        let store = CodeReviewPromptStore.shared
        let row = promptTable.selectedRow
        if row < 0 || row >= store.prompts.count {
            isLoadingBody = true
            isLoadingName = true
            bodyTextView.string = ""
            nameField.stringValue = ""
            isLoadingBody = false
            isLoadingName = false
            updateDetailEnabled()
            return
        }
        let prompt = store.prompts[row]
        isLoadingBody = true
        isLoadingName = true
        bodyTextView.string = prompt.text
        nameField.stringValue = prompt.name
        isLoadingBody = false
        isLoadingName = false
        store.lastSelectedUUID = prompt.uuid
        updateDetailEnabled()
    }

    private func updateDetailEnabled() {
        let hasSelection = promptTable.numberOfSelectedRows == 1
        nameField.isEnabled = hasSelection
        bodyTextView.isEditable = hasSelection
        emptyLabel.isHidden = hasSelection
        bodyScrollView.isHidden = !hasSelection
    }

    // Called from the data provider after a fresh prompt is appended.
    // Selecting the row picks up the right detail content via the
    // standard selection-changed path; pulling focus into the name
    // field — and selecting all of the seeded "New Prompt" text —
    // lets the user type a real name immediately.
    fileprivate func selectRowAndFocusName(_ row: Int) {
        guard row >= 0, row < promptTable.numberOfRows else { return }
        promptTable.selectRowIndexes(IndexSet(integer: row),
                                      byExtendingSelection: false)
        promptTable.scrollRowToVisible(row)
        if let window {
            window.makeFirstResponder(nameField)
            // The shared field editor, now installed on nameField,
            // owns the selection.
            (window.firstResponder as? NSText)?.selectAll(nil)
        }
    }
}

// MARK: - Text editing

extension CodeReviewPromptManagerWindowController: NSTextViewDelegate, NSTextFieldDelegate {
    func textDidChange(_ notification: Notification) {
        if isLoadingBody { return }
        guard notification.object as? NSTextView === bodyTextView else { return }
        let row = promptTable.selectedRow
        guard row >= 0, row < CodeReviewPromptStore.shared.prompts.count else { return }
        performLocalMutation {
            crudController?.undoable {
                CodeReviewPromptStore.shared.updateText(bodyTextView.string,
                                                         at: row)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if isLoadingName { return }
        guard obj.object as? NSTextField === nameField else { return }
        let row = promptTable.selectedRow
        guard row >= 0, row < CodeReviewPromptStore.shared.prompts.count else { return }
        performLocalMutation {
            crudController?.undoable {
                CodeReviewPromptStore.shared.updateName(nameField.stringValue,
                                                         at: row)
            }
        }
        crudController?.reload(row: row)
    }
}

// MARK: - CRUD delegate

extension CodeReviewPromptManagerWindowController: CRUDTableViewControllerDelegate {
    typealias CRUDState = [CodeReviewSavedPrompt]

    var crudState: [CodeReviewSavedPrompt] {
        get { CodeReviewPromptStore.shared.prompts }
        set {
            performLocalMutation {
                CodeReviewPromptStore.shared.restore(newValue)
            }
            loadDetailFromSelection()
        }
    }

    func crudTableSelectionDidChange(
        _ sender: CRUDTableViewController<CodeReviewPromptManagerWindowController>,
        selectedRows: IndexSet) {
        loadDetailFromSelection()
    }

    func crudTextFieldDidChange(
        _ sender: CRUDTableViewController<CodeReviewPromptManagerWindowController>,
        row: Int,
        column: Int,
        newValue: String) {
        performLocalMutation {
            crudController?.undoable {
                CodeReviewPromptStore.shared.updateName(newValue, at: row)
            }
        }
        if row == promptTable.selectedRow {
            isLoadingName = true
            nameField.stringValue = newValue
            isLoadingName = false
        }
    }

    func crudDoubleClick(
        _ sender: CRUDTableViewController<CodeReviewPromptManagerWindowController>,
        row: Int,
        column: Int) {
        // Inline editing handles rename; nothing to do.
    }
}

// MARK: - Data provider

private final class PromptDataProvider: CRUDDataProvider {
    weak var controller: CodeReviewPromptManagerWindowController?

    var count: Int { CodeReviewPromptStore.shared.prompts.count }
    var supportsReorder: Bool { true }
    var supportsInlineEditing: Bool { true }

    private struct Row: CRUDRow {
        var prompt: CodeReviewSavedPrompt
        func format(column: Int) -> CRUDFormatted {
            return .string(prompt.name)
        }
    }

    subscript(index: Int) -> CRUDRow {
        Row(prompt: CodeReviewPromptStore.shared.prompts[index])
    }

    func delete(_ indexes: IndexSet) {
        controller?.performLocalMutation {
            CodeReviewPromptStore.shared.remove(at: indexes)
        }
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        guard let controller else { return }
        let name = uniqueName(basedOn: "New Prompt")
        var newIndex = -1
        controller.performLocalMutation {
            controller.crudController?.undoable {
                newIndex = CodeReviewPromptStore.shared.add(name: name, text: "")
                completion(newIndex)
            }
        }
        if newIndex >= 0 {
            controller.selectRowAndFocusName(newIndex)
        }
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        controller?.performLocalMutation {
            CodeReviewPromptStore.shared.reorder(from: sourceIndex,
                                                  to: destinationIndex)
        }
    }

    private func uniqueName(basedOn base: String) -> String {
        let existing = Set(CodeReviewPromptStore.shared.prompts.map { $0.name })
        if !existing.contains(base) { return base }
        var i = 2
        while existing.contains("\(base) \(i)") { i += 1 }
        return "\(base) \(i)"
    }
}
