
//
//  iTermBookmarkTagEditorWindowController.swift
//  iTerm2
//
//  Created by Claude on 6/23/25.
//

import Cocoa

@MainActor
@objc protocol iTermBookmarkTagEditorDelegate: AnyObject {
    func bookmarkTagEditorWillClose(_ controller: iTermBookmarkTagEditorWindowController)
}

@MainActor
@objc
class iTermBookmarkTagEditorWindowController: NSWindowController {
    weak var delegate: iTermBookmarkTagEditorDelegate?
    private var user: iTermBrowserUser!

    private var bookmarkURL: String = ""
    private var bookmarkTitle: String = ""
    private var currentTags: Set<String> = []
    private var allTags: [String] = []

    @IBOutlet var titleLabel: NSTextField!
    @IBOutlet var urlLabel: NSTextField!
    @IBOutlet var tagsTokenField: NSTokenField!
    @IBOutlet var deleteButton: NSButton!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var saveButton: NSButton!

    convenience init(user: iTermBrowserUser,
                     url: String,
                     title: String?,
                     delegate: iTermBookmarkTagEditorDelegate?) {
        self.init()
        self.user = user
        self.bookmarkURL = url
        self.bookmarkTitle = title ?? url
        self.delegate = delegate

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        panel.title = String(localized: "BookmarkTagEditorWindowController_EditBookmark", defaultValue: "Edit Bookmark", comment: "Title in bookmarkTagEditorWillClose")
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.center()

        self.window = panel
        setupUI()
        loadData()
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.delegate = self
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Create and configure UI elements
        titleLabel = NSTextField(labelWithString: String(localized: "BookmarkTagEditorWindowController_Title", defaultValue: "Title:", comment: "Title in setupUI"))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleValueLabel = NSTextField(labelWithString: bookmarkTitle)
        titleValueLabel.translatesAutoresizingMaskIntoConstraints = false
        titleValueLabel.font = NSFont.systemFont(ofSize: 13)
        titleValueLabel.textColor = .secondaryLabelColor
        titleValueLabel.lineBreakMode = .byTruncatingTail

        urlLabel = NSTextField(labelWithString: String(localized: "BookmarkTagEditorWindowController_Url", defaultValue: "URL:", comment: "Label text in setupUI"))
        urlLabel.translatesAutoresizingMaskIntoConstraints = false

        let urlValueLabel = NSTextField(labelWithString: bookmarkURL)
        urlValueLabel.translatesAutoresizingMaskIntoConstraints = false
        urlValueLabel.font = NSFont.systemFont(ofSize: 13)
        urlValueLabel.textColor = .secondaryLabelColor
        urlValueLabel.lineBreakMode = .byTruncatingTail

        let tagsLabel = NSTextField(labelWithString: String(localized: "BookmarkTagEditorWindowController_Tags", defaultValue: "Tags:", comment: "Label text in setupUI"))
        tagsLabel.translatesAutoresizingMaskIntoConstraints = false

        tagsTokenField = NSTokenField()
        tagsTokenField.translatesAutoresizingMaskIntoConstraints = false
        tagsTokenField.delegate = self
        tagsTokenField.placeholderString = String(localized: "BookmarkTagEditorWindowController_EnterTags", defaultValue: "Enter tags...", comment: "Placeholder text in setupUI")

        // Buttons
        deleteButton = NSButton(title: String(localized: "BookmarkTagEditorWindowController_DeleteBookmark", defaultValue: "Delete Bookmark", comment: "Delete Bookmark button title in setupUI"), target: self, action: #selector(deleteBookmark))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.bezelStyle = .rounded

        cancelButton = NSButton(title: String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Cancel bookmark editing button title in setupUI"), target: self, action: #selector(cancel))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape key

        saveButton = NSButton(title: String(localized: "COMMON_SAVE", defaultValue: "Save", comment: "Save bookmark button title in setupUI"), target: self, action: #selector(saveChanges))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        // Add views
        contentView.addSubview(titleLabel)
        contentView.addSubview(titleValueLabel)
        contentView.addSubview(urlLabel)
        contentView.addSubview(urlValueLabel)
        contentView.addSubview(tagsLabel)
        contentView.addSubview(tagsTokenField)
        contentView.addSubview(deleteButton)
        contentView.addSubview(cancelButton)
        contentView.addSubview(saveButton)

        // Set up constraints
        NSLayoutConstraint.activate([
            // Title
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.widthAnchor.constraint(equalToConstant: 50),

            titleValueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            titleValueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            titleValueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            // URL
            urlLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            urlLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),

            urlValueLabel.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 10),
            urlValueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            urlValueLabel.centerYAnchor.constraint(equalTo: urlLabel.centerYAnchor),

            // Tags
            tagsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            tagsLabel.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 12),
            tagsLabel.widthAnchor.constraint(equalTo: titleLabel.widthAnchor),

            tagsTokenField.leadingAnchor.constraint(equalTo: tagsLabel.trailingAnchor, constant: 10),
            tagsTokenField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tagsTokenField.centerYAnchor.constraint(equalTo: tagsLabel.centerYAnchor),
            tagsTokenField.heightAnchor.constraint(equalToConstant: 22),

            // Buttons
            deleteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            deleteButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -12),
            cancelButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor)
        ])
    }

    private func loadData() {
        Task {
            await loadTagsAndBookmarkData()
        }
    }

    private func loadTagsAndBookmarkData() async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        // Load all available tags for autocomplete
        allTags = await database.getAllTags()

        // Load existing tags for this bookmark
        let tags = await database.getTagsForBookmark(url: bookmarkURL)
        currentTags = Set(tags)

        await MainActor.run {
            tagsTokenField.objectValue = Array(currentTags)
        }
    }

    @objc private func saveChanges() {
        let newTags = Set((tagsTokenField.objectValue as? [String]) ?? [])

        Task {
            await updateBookmarkTags(newTags: newTags)
            await MainActor.run {
                self.close()
            }
        }
    }

    private func updateBookmarkTags(newTags: Set<String>) async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        // Remove tags that are no longer present
        for tag in currentTags.subtracting(newTags) {
            _ = await database.removeTagFromBookmark(url: bookmarkURL, tag: tag)
        }

        // Add new tags
        for tag in newTags.subtracting(currentTags) {
            _ = await database.addTagToBookmark(url: bookmarkURL, tag: tag)
        }

        // Clean up unused tags
        await cleanupUnusedTags()
    }

    private func cleanupUnusedTags() async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        // Get all tags that are no longer used by any bookmark
        let allCurrentTags = await database.getAllTags()

        // Update our cached list
        await MainActor.run {
            self.allTags = allCurrentTags
        }
    }

    @objc private func deleteBookmark() {
        let alert = NSAlert()
        alert.messageText = String(localized: "BookmarkTagEditorWindowController_DeleteBookmark", defaultValue: "Delete Bookmark", comment: "Alert title in deleteBookmark")
        alert.informativeText = String(localized: "BookmarkTagEditorWindowController_AreYouSureYouWantToDelete", defaultValue: "Are you sure you want to delete this bookmark?", comment: "Alert explanatory text in deleteBookmark")
        alert.addButton(withTitle: String(localized: "COMMON_DELETE", defaultValue: "Delete", comment: "Button title in deleteBookmark"))
        alert.addButton(withTitle: String(localized: "COMMON_CANCEL", defaultValue: "Cancel", comment: "Button title in deleteBookmark"))
        alert.alertStyle = .warning

        alert.beginSheetModal(for: window!) { response in
            if response == .alertFirstButtonReturn {
                Task {
                    await self.performDeleteBookmark()
                }
            }
        }
    }

    private func performDeleteBookmark() async {
        guard let database = await BrowserDatabase.instance(for: user) else { return }

        let success = await database.removeBookmark(url: bookmarkURL)

        await MainActor.run {
            if success {
                ToastWindowController.showToast(withMessage: String(localized: "BOOKMARK_TAG_EDITOR_BOOKMARK_DELETED_TOAST", defaultValue: "Bookmark Deleted", comment: "Toast confirming a bookmark was deleted"))
            }
            self.close()
        }
    }

    @objc private func cancel() {
        close()
    }

    func closeFromNavigation() {
        close()
    }
}

// MARK: - NSTokenFieldDelegate
extension iTermBookmarkTagEditorWindowController: NSTokenFieldDelegate {
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int, indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? {
        let filteredTags = allTags.filter { tag in
            tag.localizedCaseInsensitiveHasPrefix(substring)
        }
        return filteredTags
    }

    func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
        // Allow adding any token (including new tags)
        return tokens
    }
}

// MARK: - NSWindowDelegate
extension iTermBookmarkTagEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        delegate?.bookmarkTagEditorWillClose(self)
    }
}
