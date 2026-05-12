//
//  MomentermFileTreeVC.swift
//  iTerm2
//
//  File tree panel — shows project files in a tree and allows inline editing.
//  Appears to the right of the sidebar when "세부 파일보기" is triggered.
//  Rules: no Auto Layout, autoresizingMask only, it_fatalError not fatalError.
//

import AppKit

// MARK: - Delegate

@objc protocol MomentermEmbeddedFileTreeDelegate: AnyObject {
    func fileTreeDidRequestClose()
    func fileTreeDidRequestOpenEditorAtPath(_ path: String)
}

// MARK: - FileNode (private model)

private final class FileNode {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?   // nil = not yet loaded; [] = loaded, empty

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var displayName: String { url.lastPathComponent }
}

// MARK: - Smart filter

private let kFilteredDirs: Set<String> = [
    "node_modules", ".git", ".svn", ".hg",
    "dist", "build", ".build", "Pods", "DerivedData",
    ".next", ".nuxt", "__pycache__", ".tox", "vendor",
    ".idea", ".vscode", ".expo", "coverage", ".nyc_output"
]

private let kFilteredFileNames: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini"]
private let kFilteredExtensions: Set<String> = ["pyc", "o", "class", "a", "dylib", "so"]

private func shouldFilterNode(url: URL, isDirectory: Bool) -> Bool {
    let name = url.lastPathComponent
    if name.hasPrefix(".") && isDirectory { return kFilteredDirs.contains(name) }
    if isDirectory { return kFilteredDirs.contains(name) }
    if kFilteredFileNames.contains(name) { return true }
    if name.hasSuffix(".swp") || name.hasSuffix(".swo") { return true }
    return kFilteredExtensions.contains(url.pathExtension.lowercased())
}

// MARK: - View Controller

@objc final class MomentermFileTreeVC: NSViewController {

    @objc weak var fileTreeDelegate: MomentermEmbeddedFileTreeDelegate?

    // MARK: - Layout constants
    private let kPanelW: CGFloat   = 240
    private let kHeaderH: CGFloat  = 36
    private let kSepH: CGFloat     = 1
    private let kEditorBarH: CGFloat = 28
    private let kEditorBodyH: CGFloat = 172
    private var editorTotalH: CGFloat { editorIsOpen ? kEditorBarH + kEditorBodyH : 0 }

    // MARK: - UI refs
    private var headerView: NSView!
    private var headerSeparator: NSBox!
    private var titleLabel: NSTextField!
    private var closeButton: NSButton!
    private var treeScrollView: NSScrollView!
    private var outlineView: NSOutlineView!
    private var editorSeparator: NSBox!
    private var editorBar: NSView!
    private var editorFileLabel: NSTextField!
    private var editorSaveBtn: NSButton!
    private var editorCloseBtn: NSButton!
    private var editorScrollView: NSScrollView!
    private var textView: NSTextView!
    private var leftBorderBox: NSBox!
    private var rightBorderBox: NSBox!

    // MARK: - State
    private var rootNode: FileNode!
    private var currentFileURL: URL?
    private var isDirty = false
    private var editorIsOpen = false
    private let rootPath: String
    private let projectName: String

    // MARK: - Floating editor panel state
    private var floatingPanel: NSPanel?
    private var floatingFilenameLabel: NSTextField!
    private var floatingSaveBtn: NSButton!
    private var floatingTextView: NSTextView!
    private var floatingCurrentURL: URL?
    private var floatingIsDirty = false

    // MARK: - Init

    @objc init(rootPath: String, projectName: String) {
        self.rootPath = rootPath
        self.projectName = projectName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { it_fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func loadView() {
        rootNode = FileNode(url: URL(fileURLWithPath: rootPath), isDirectory: true)
        loadChildren(of: rootNode)
        let frame = NSRect(x: 0, y: 0, width: kPanelW, height: 400)
        view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildSubviews()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        outlineView.reloadData()
        if rootNode.children?.isEmpty == false {
            outlineView.expandItem(rootNode)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyLayout()
    }

    // MARK: - Build

    private func buildSubviews() {
        let w = kPanelW

        // ── Header ──────────────────────────────────────────
        let header = NSView(frame: NSRect(x: 0, y: 0, width: w, height: kHeaderH))
        header.autoresizingMask = [.width, .minYMargin]

        titleLabel = NSTextField(labelWithString: projectName)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.autoresizingMask = .width
        header.addSubview(titleLabel)

        closeButton = NSButton(frame: .zero)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "닫기")
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.autoresizingMask = [.minXMargin]
        header.addSubview(closeButton)
        view.addSubview(header)
        headerView = header

        // ── Separator ────────────────────────────────────────
        headerSeparator = NSBox()
        headerSeparator.boxType = .separator
        headerSeparator.autoresizingMask = [.width, .minYMargin]
        view.addSubview(headerSeparator)

        // ── Outline (file tree) ──────────────────────────────
        outlineView = NSOutlineView()
        outlineView.style = .sourceList
        outlineView.rowHeight = 20
        outlineView.indentationPerLevel = 10
        outlineView.headerView = nil
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(fileClicked)
        outlineView.intercellSpacing = NSSize(width: 0, height: 1)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileCol"))
        col.isEditable = false
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        treeScrollView = NSScrollView()
        treeScrollView.hasVerticalScroller = true
        treeScrollView.autohidesScrollers = true
        treeScrollView.drawsBackground = false
        treeScrollView.documentView = outlineView
        view.addSubview(treeScrollView)

        // ── Editor separator ─────────────────────────────────
        editorSeparator = NSBox()
        editorSeparator.boxType = .separator
        editorSeparator.autoresizingMask = [.width, .minYMargin]
        editorSeparator.isHidden = true
        view.addSubview(editorSeparator)

        // ── Editor bar ───────────────────────────────────────
        editorBar = NSView()
        editorBar.autoresizingMask = [.width, .minYMargin]
        editorBar.isHidden = true

        editorFileLabel = NSTextField(labelWithString: "")
        editorFileLabel.font = .systemFont(ofSize: 11, weight: .medium)
        editorFileLabel.lineBreakMode = .byTruncatingMiddle
        editorFileLabel.autoresizingMask = .width

        editorSaveBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 54, height: 20))
        editorSaveBtn.title = "저장"
        editorSaveBtn.bezelStyle = .rounded
        editorSaveBtn.controlSize = .small
        editorSaveBtn.keyEquivalent = "s"
        editorSaveBtn.keyEquivalentModifierMask = [.command]
        editorSaveBtn.target = self
        editorSaveBtn.action = #selector(saveTapped)
        editorSaveBtn.autoresizingMask = [.minXMargin]

        editorCloseBtn = NSButton(frame: .zero)
        editorCloseBtn.isBordered = false
        editorCloseBtn.imagePosition = .imageOnly
        editorCloseBtn.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "편집 닫기")
        editorCloseBtn.contentTintColor = .secondaryLabelColor
        editorCloseBtn.target = self
        editorCloseBtn.action = #selector(closeEditor)
        editorCloseBtn.autoresizingMask = [.minXMargin]

        editorBar.addSubview(editorFileLabel)
        editorBar.addSubview(editorSaveBtn)
        editorBar.addSubview(editorCloseBtn)
        view.addSubview(editorBar)

        // ── Editor text view ─────────────────────────────────
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: kPanelW, height: kEditorBodyH))
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: kEditorBodyH)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: kPanelW, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self

        editorScrollView = NSScrollView()
        editorScrollView.hasVerticalScroller = true
        editorScrollView.autohidesScrollers = true
        editorScrollView.documentView = textView
        editorScrollView.isHidden = true
        view.addSubview(editorScrollView)

        // Left border — separates file tree from sidebar
        leftBorderBox = NSBox()
        leftBorderBox.boxType = .custom
        leftBorderBox.borderWidth = 0
        leftBorderBox.fillColor = NSColor.gridColor
        view.addSubview(leftBorderBox)

        // Right border — separates file tree from terminal area
        rightBorderBox = NSBox()
        rightBorderBox.boxType = .custom
        rightBorderBox.borderWidth = 0
        rightBorderBox.fillColor = NSColor.gridColor
        view.addSubview(rightBorderBox)
    }

    private func applyLayout() {
        let w = view.bounds.width
        let h = view.bounds.height

        // Header at top
        headerView.frame = NSRect(x: 0, y: h - kHeaderH, width: w, height: kHeaderH)
        titleLabel.frame = NSRect(x: 10, y: (kHeaderH - 16) / 2, width: w - 40, height: 16)
        closeButton.frame = NSRect(x: w - 28, y: (kHeaderH - 20) / 2, width: 20, height: 20)

        // Separator just below header
        headerSeparator.frame = NSRect(x: 0, y: h - kHeaderH - kSepH, width: w, height: kSepH)

        let treeBottom: CGFloat = editorTotalH
        let treeTop: CGFloat = h - kHeaderH - kSepH

        // Tree scroll view
        treeScrollView.frame = NSRect(x: 0, y: treeBottom, width: w, height: max(0, treeTop - treeBottom))
        outlineView.tableColumns.first?.width = w - 4

        // Left and right borders framing the panel
        leftBorderBox.frame  = NSRect(x: 0,     y: 0, width: 1, height: h)
        rightBorderBox.frame = NSRect(x: w - 1, y: 0, width: 1, height: h)

        // Editor section
        if editorIsOpen {
            editorSeparator.frame = NSRect(x: 0, y: editorTotalH - kSepH, width: w, height: kSepH)
            editorBar.frame = NSRect(x: 0, y: editorTotalH - kSepH - kEditorBarH, width: w, height: kEditorBarH)
            editorFileLabel.frame = NSRect(x: 8, y: (kEditorBarH - 14) / 2, width: w - 108, height: 14)
            editorSaveBtn.frame = NSRect(x: w - 84, y: (kEditorBarH - 20) / 2, width: 56, height: 20)
            editorCloseBtn.frame = NSRect(x: w - 26, y: (kEditorBarH - 20) / 2, width: 20, height: 20)
            editorScrollView.frame = NSRect(x: 0, y: 0, width: w, height: kEditorBodyH)
        }
    }

    private func setEditorOpen(_ open: Bool) {
        editorIsOpen = open
        editorSeparator.isHidden = !open
        editorBar.isHidden = !open
        editorScrollView.isHidden = !open
        view.needsLayout = true
        applyLayout()
    }

    // MARK: - File loading

    private func loadChildren(of node: FileNode) {
        guard node.isDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: node.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            node.children = []
            return
        }
        var nodes: [FileNode] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if shouldFilterNode(url: url, isDirectory: isDir) { continue }
            nodes.append(FileNode(url: url, isDirectory: isDir))
        }
        // Directories first, then alphabetical
        node.children = nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        if isDirty {
            let a = NSAlert()
            a.messageText = "저장하지 않은 내용이 있습니다."
            a.informativeText = "파일 트리를 닫으면 변경 내용이 손실됩니다."
            a.addButton(withTitle: "저장하고 닫기")
            a.addButton(withTitle: "버리고 닫기")
            a.addButton(withTitle: "취소")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { saveCurrentFile() }
            else if r == .alertThirdButtonReturn { return }
        }
        fileTreeDelegate?.fileTreeDidRequestClose()
    }

    @objc private func fileClicked() {
        let row = outlineView.clickedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode,
              !node.isDirectory else { return }
        fileTreeDelegate?.fileTreeDidRequestOpenEditorAtPath(node.url.path)
    }

    private func openEditorForURL(_ url: URL) {
        // If switching files with unsaved changes, ask
        if isDirty, currentFileURL != url {
            let a = NSAlert()
            a.messageText = "저장하지 않은 내용이 있습니다."
            a.informativeText = "\u{201C}\(currentFileURL?.lastPathComponent ?? "")\u{201D}의 변경 내용을 저장하시겠습니까?"
            a.addButton(withTitle: "저장")
            a.addButton(withTitle: "버리기")
            a.addButton(withTitle: "취소")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { saveCurrentFile() }
            else if r == .alertThirdButtonReturn { return }
            isDirty = false
        }
        currentFileURL = url
        textView.string = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        editorFileLabel.stringValue = url.lastPathComponent
        editorSaveBtn.title = "저장"
        isDirty = false
        if !editorIsOpen { setEditorOpen(true) }
    }

    @objc private func saveTapped() {
        saveCurrentFile()
    }

    private func saveCurrentFile() {
        guard let url = currentFileURL else { return }
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            editorSaveBtn.title = "저장됨 ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.editorSaveBtn.title = "저장"
            }
        } catch {
            let a = NSAlert()
            a.messageText = "저장 실패"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    @objc private func closeEditor() {
        if isDirty {
            let a = NSAlert()
            a.messageText = "저장하지 않은 내용이 있습니다."
            a.addButton(withTitle: "저장")
            a.addButton(withTitle: "버리기")
            a.addButton(withTitle: "취소")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { saveCurrentFile() }
            else if r == .alertThirdButtonReturn { return }
        }
        isDirty = false
        currentFileURL = nil
        setEditorOpen(false)
    }
}

// MARK: - NSOutlineViewDataSource

extension MomentermFileTreeVC: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let node = (item as? FileNode) ?? rootNode
        if node?.children == nil { loadChildren(of: node!) }
        return node?.children?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let node = (item as? FileNode) ?? rootNode!
        if node.children == nil { loadChildren(of: node) }
        return node.children![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }
}

// MARK: - NSOutlineViewDelegate

extension MomentermFileTreeVC: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let id = NSUserInterfaceItemIdentifier("MtFileCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = reused
            cell.subviews.forEach { $0.removeFromSuperview() }
        } else {
            cell = NSTableCellView()
        }
        cell.identifier = id

        let icon = NSImageView(frame: NSRect(x: 2, y: 2, width: 14, height: 14))
        icon.autoresizingMask = []
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        icon.image = NSImage(systemSymbolName: symbolName(for: node), accessibilityDescription: nil)
        icon.contentTintColor = node.isDirectory ? .controlAccentColor : .secondaryLabelColor
        cell.addSubview(icon)

        let label = NSTextField(labelWithString: node.displayName)
        label.font = .systemFont(ofSize: 11)
        label.autoresizingMask = .width
        label.frame = NSRect(x: 20, y: 2,
                              width: max(0, outlineView.bounds.width - 20), height: 16)
        label.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(label)
        cell.textField = label

        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return !node.isDirectory
    }

    private func symbolName(for node: FileNode) -> String {
        if node.isDirectory { return "folder.fill" }
        switch node.url.pathExtension.lowercased() {
        case "swift":                      return "swift"
        case "m", "h", "c", "cpp", "cc":  return "c.square"
        case "js", "jsx":                  return "j.square"
        case "ts", "tsx":                  return "t.square"
        case "json":                       return "curlybraces"
        case "md", "markdown":             return "doc.text"
        case "sh", "zsh", "bash":          return "terminal"
        case "png", "jpg", "jpeg",
             "gif", "svg", "ico",
             "webp":                       return "photo"
        case "pdf":                        return "doc.richtext"
        default:
            let name = node.url.lastPathComponent.lowercased()
            if name.hasPrefix(".env") { return "key.fill" }
            return "doc"
        }
    }
}

// MARK: - NSTextViewDelegate

extension MomentermFileTreeVC: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if (notification.object as? NSTextView) === floatingTextView {
            floatingIsDirty = true
        } else {
            isDirty = true
        }
    }
}

// MARK: - Floating Editor Panel

extension MomentermFileTreeVC: NSWindowDelegate {

    func openFloatingEditor(for url: URL) {
        if floatingIsDirty, floatingCurrentURL != url {
            let a = NSAlert()
            a.messageText = "저장하지 않은 내용이 있습니다."
            a.informativeText = "\u{201C}\(floatingCurrentURL?.lastPathComponent ?? "")\u{201D}의 변경 내용을 저장하시겠습니까?"
            a.addButton(withTitle: "저장")
            a.addButton(withTitle: "버리기")
            a.addButton(withTitle: "취소")
            let r = a.runModal()
            if r == .alertFirstButtonReturn { saveFloatingFile() }
            else if r == .alertThirdButtonReturn { return }
            floatingIsDirty = false
        }

        if floatingPanel == nil { buildFloatingPanel() }

        floatingCurrentURL = url
        floatingFilenameLabel.stringValue = url.lastPathComponent
        floatingTextView.string = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        floatingSaveBtn.title = "저장"
        floatingIsDirty = false
        floatingPanel?.title = url.lastPathComponent
        floatingPanel?.makeKeyAndOrderFront(nil)
    }

    private func buildFloatingPanel() {
        let w: CGFloat = 640
        let h: CGFloat = 480
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.delegate = self

        guard let cv = panel.contentView else { return }

        // Top bar
        let barH: CGFloat = 32
        let bar = NSView(frame: NSRect(x: 0, y: h - barH, width: w, height: barH))
        bar.autoresizingMask = [.width, .minYMargin]

        let fnLabel = NSTextField(labelWithString: "")
        fnLabel.frame = NSRect(x: 8, y: 6, width: w - 100, height: 20)
        fnLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fnLabel.lineBreakMode = .byTruncatingMiddle
        fnLabel.autoresizingMask = .width
        bar.addSubview(fnLabel)
        floatingFilenameLabel = fnLabel

        let saveBtn = NSButton(frame: NSRect(x: w - 88, y: 5, width: 80, height: 22))
        saveBtn.title = "저장"
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "s"
        saveBtn.keyEquivalentModifierMask = [.command]
        saveBtn.target = self
        saveBtn.action = #selector(floatingSaveTapped)
        saveBtn.autoresizingMask = .minXMargin
        bar.addSubview(saveBtn)
        floatingSaveBtn = saveBtn
        cv.addSubview(bar)

        // Separator
        let sep = NSBox(frame: NSRect(x: 0, y: h - barH - 1, width: w, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width, .minYMargin]
        cv.addSubview(sep)

        // Text area
        let tvH = h - barH - 1
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: tvH))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: w, height: tvH))
        tv.autoresizingMask = [.width, .height]
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: tvH)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        scrollView.documentView = tv
        cv.addSubview(scrollView)
        floatingTextView = tv

        panel.center()
        floatingPanel = panel
    }

    @objc private func floatingSaveTapped() {
        saveFloatingFile()
    }

    private func saveFloatingFile() {
        guard let url = floatingCurrentURL else { return }
        do {
            try floatingTextView.string.write(to: url, atomically: true, encoding: .utf8)
            floatingIsDirty = false
            floatingSaveBtn.title = "저장됨 ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.floatingSaveBtn.title = "저장"
            }
        } catch {
            let a = NSAlert()
            a.messageText = "저장 실패"
            a.informativeText = error.localizedDescription
            a.runModal()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard floatingIsDirty else { return true }
        let a = NSAlert()
        a.messageText = "저장하지 않은 내용이 있습니다."
        a.informativeText = "\u{201C}\(floatingCurrentURL?.lastPathComponent ?? "")\u{201D}의 변경 내용을 저장하시겠습니까?"
        a.addButton(withTitle: "저장")
        a.addButton(withTitle: "버리기")
        a.addButton(withTitle: "취소")
        let r = a.runModal()
        if r == .alertFirstButtonReturn { saveFloatingFile(); return true }
        else if r == .alertSecondButtonReturn { floatingIsDirty = false; return true }
        return false
    }
}
