//
//  HorizontalFileListView.swift
//  iTerm2
//
//  Created by George Nachman on 6/2/25.
//

import Cocoa

fileprivate let filenameLabelWidth = CGFloat(80)

@objc class HorizontalFileListView: NSView {
    var files: [String] = [] {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.collectionView.reloadData()

                // Force layout update
                self.collectionView.needsLayout = true
                self.collectionView.layoutSubtreeIfNeeded()

                // Update scroll view content size
                self.scrollView.needsLayout = true
                self.scrollView.layoutSubtreeIfNeeded()

                // Update intrinsic size and parent layout
                self.invalidateIntrinsicContentSize()
                self.needsLayout = true
            }
        }
    }

    var allowsMultipleSelection: Bool = true {
        didSet {
            collectionView.allowsMultipleSelection = allowsMultipleSelection
        }
    }
    var allowsEmptySelection: Bool = true {
        didSet {
            collectionView.allowsEmptySelection = allowsEmptySelection
        }
    }

    // Selection callback
    var onSelectionChanged: (([String]) -> Void)?

    // Deletion callback - called when items are about to be removed
    var onItemsWillBeDeleted: (([String]) -> Bool)? // Return true to allow deletion
    var onDidDeleteItems: (() -> ())?

    private let scrollView: NSScrollView
    private let collectionView: NSCollectionView
    private let flowLayout: NSCollectionViewFlowLayout

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        // Create flow layout
        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: filenameLabelWidth, height: 100)
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // Create collection view
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [NSColor.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = allowsMultipleSelection
        collectionView.allowsEmptySelection = allowsEmptySelection

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

        super.init(frame: frameRect)

        setupView()
        setupCollectionView()
    }

    required init?(coder: NSCoder) {
        // Create flow layout
        flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = NSSize(width: filenameLabelWidth, height: 100)
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        // Create collection view
        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = flowLayout
        collectionView.backgroundColors = [NSColor.clear]
        collectionView.isSelectable = true

        // Create scroll view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

        super.init(coder: coder)

        setupView()
        setupCollectionView()
    }

    // MARK: - Setup

    private func setupView() {
        addSubview(scrollView)

        // Auto Layout
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupCollectionView() {
        // Register the item class
        collectionView.register(FileItemView.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("FileItem"))

        // Set data source and delegate
        collectionView.dataSource = self
        collectionView.delegate = self

        // Ensure the collection view is ready
        collectionView.reloadData()
        collectionView.needsLayout = true
    }

    // MARK: - Key Event Handling

    override var acceptsFirstResponder: Bool {
        return true
    }

    private func deleteSelectedItems() {
        guard !collectionView.selectionIndexes.isEmpty else { return }

        // Ask for permission to delete if callback is provided
        if let onItemsWillBeDeleted = onItemsWillBeDeleted {
            if !onItemsWillBeDeleted(selectedFiles) {
                return // Deletion not allowed
            }
        }

        // Remove items in reverse order to maintain index validity
        let sortedIndexes = collectionView.selectionIndexes.sorted(by: >)
        var newFiles = files

        for index in sortedIndexes {
            if index < newFiles.count {
                newFiles.remove(at: index)
            }
        }

        files = newFiles

        onDidDeleteItems?()
        notifySelectionChanged()
    }

    // MARK: - NSResponder

    override func selectAll(_ sender: Any?) {
        collectionView.selectAll(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        deleteSelectedItems()
    }
    // MARK: - Public Methods

    private func updateSelectionAppearance() {
        for i in 0..<files.count {
            let indexPath = IndexPath(item: i, section: 0)
            if let item = collectionView.item(at: indexPath) as? FileItemView {
                item.setSelected(collectionView.selectionIndexes.contains(i))
            }
        }
    }
    private var selectedFiles: [String] {
        collectionView.selectionIndexes.compactMap { index in
            return files[index]
        }
    }

    private func notifySelectionChanged() {
        onSelectionChanged?(selectedFiles)
        updateSelectionAppearance()
    }

    // MARK: - Intrinsic Content Size
    override var intrinsicContentSize: NSSize {
        let height = flowLayout.itemSize.height + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom

        // Return a reasonable default width or NSView.noIntrinsicMetric for width
        // Since this view is designed to scroll horizontally, it shouldn't dictate its container's width
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

// MARK: - NSCollectionViewDataSource

extension HorizontalFileListView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return files.count
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("FileItem"), for: indexPath) as! FileItemView
        let filePath = files[indexPath.item]
        item.configure(with: filePath)
        item.setSelected(collectionView.selectionIndexes.contains(indexPath.item))

        item.onDeleteRequested = { [weak self] in
            self?.deleteItem(at: indexPath.item)
        }
        
        return item
    }
}

// MARK: - NSCollectionViewDelegate

extension HorizontalFileListView: NSCollectionViewDelegate {
    // Replace the existing didSelectItemsAt method with this enhanced version:
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        notifySelectionChanged()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        notifySelectionChanged()
    }
}

// MARK: - File Item View

@objc
class FileItemContainerView: NSView {
    weak var fileItemView: FileItemView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    private func updateTrackingArea() {
        // Remove existing tracking areas
        trackingAreas.forEach { removeTrackingArea($0) }

        // Add new tracking area with current bounds
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)

        if let window {
            let mouseLocation = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(mouseLocation) {
                if let event = NSEvent.enterExitEvent(
                    with: .mouseEntered,
                    location: convert(window.mouseLocationOutsideOfEventStream, from: nil),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    trackingNumber: 0,
                    userData: nil
                ) {
                    mouseEntered(with: event)
                }
            }
        }
    }

    // Handle mouse events and forward to FileItemView
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        fileItemView?.handleMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        fileItemView?.handleMouseExited()
    }
}

extension NSRect {
    mutating func set(midX: CGFloat) {
        origin.x = midX - width / 2
    }
}

class FileItemView: NSCollectionViewItem {
    class NameLabel: NSTextField {
        override var frame: CGRect {
            set {
                // Auto layout literally does not work. I promise this was my last resort. It insists
                // on making the label 4 pts larger than the requested size.
                var newFrame = newValue
                newFrame.size.width = min(filenameLabelWidth, newFrame.width)
                newFrame.set(midX: newValue.midX)
                super.frame = newFrame
            }
            get {
                super.frame
            }
        }
    }
    private let iconImageView: NSImageView
    private let nameLabel: NameLabel
    private let containerView: FileItemContainerView
    private let iconSelectionOverlay: iTermLayerBackedSolidColorView
    private let deleteButton: NSButton // NEW

    private var isItemSelected: Bool = false
    private var originalFileName: String = "" // Store original filename

    var onDeleteRequested: (() -> Void)?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        iconImageView = NSImageView()
        nameLabel = NameLabel()
        containerView = FileItemContainerView()
        iconSelectionOverlay = iTermLayerBackedSolidColorView()
        deleteButton = NSButton() // NEW

        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        setupViews()
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    func refreshTracking() {
        deleteButton.alphaValue = 0
        containerView.updateTrackingAreas()
    }

    override func loadView() {
        view = containerView
    }

    private func setupViews() {
        containerView.fileItemView = self

        // Configure icon selection overlay (light gray around just the icon)
        iconSelectionOverlay.color = NSColor.it_dynamicColor(forLightMode: .quaternaryLabelColor,
                                                             darkMode: .tertiaryLabelColor)
        iconSelectionOverlay.layer?.cornerRadius = 3
        iconSelectionOverlay.isHidden = true
        iconSelectionOverlay.translatesAutoresizingMaskIntoConstraints = false

        // Configure icon image view
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.imageAlignment = .alignCenter
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // NEW: Configure delete button
        setupDeleteButton()

        // Configure name label for multi-line display
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = NSColor.clear
        nameLabel.alignment = .center
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.usesSingleLineMode = false
        nameLabel.cell?.wraps = true
        nameLabel.cell?.isScrollable = false
        nameLabel.drawsBackground = false
        nameLabel.wantsLayer = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.layer?.cornerRadius = 3
        nameLabel.layer?.masksToBounds = true

        // Add subviews (icon selection overlay behind icon, then icon, then delete button, then label)
        containerView.addSubview(iconSelectionOverlay)
        containerView.addSubview(iconImageView)
        containerView.addSubview(deleteButton) // NEW
        containerView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            // Icon selection overlay constraints (just around the icon area)
            iconSelectionOverlay.centerXAnchor.constraint(equalTo: iconImageView.centerXAnchor),
            iconSelectionOverlay.centerYAnchor.constraint(equalTo: iconImageView.centerYAnchor),
            iconSelectionOverlay.widthAnchor.constraint(equalTo: iconImageView.widthAnchor, constant: 8),
            iconSelectionOverlay.heightAnchor.constraint(equalTo: iconImageView.heightAnchor, constant: 8),

            // Icon constraints
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 5),
            iconImageView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),

            // Label constraints - fixed height to accommodate 2 lines
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 5),
            nameLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
        ])

        let nameWidthConstraint = nameLabel.widthAnchor.constraint(equalToConstant: filenameLabelWidth)
        nameWidthConstraint.priority = .required
        NSLayoutConstraint.activate([nameWidthConstraint])
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Position delete button manually so its visibility doesn't affect label size.
        let iconFrame = iconImageView.frame
        deleteButton.frame = NSRect(
            x: iconFrame.maxX - 12,
            y: iconFrame.maxY - 12,
            width: 16,
            height: 16
        )
    }

    // NEW: Setup delete button
    private func setupDeleteButton() {
        deleteButton.wantsLayer = true
        deleteButton.isBordered = false
        deleteButton.bezelStyle = .circular
        deleteButton.title = ""
        deleteButton.target = self
        deleteButton.action = #selector(deleteButtonClicked)

        // Create the X symbol in a circle
        let buttonImage = createDeleteButtonImage()
        deleteButton.image = buttonImage

        // Style the button
        deleteButton.layer?.cornerRadius = 8
        deleteButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        deleteButton.layer?.borderWidth = 1
        deleteButton.layer?.borderColor = NSColor.black.cgColor

        // Initially hidden, will show on hover or selection
        deleteButton.alphaValue = 0
    }

    // NEW: Create delete button image
    private func createDeleteButtonImage() -> NSImage {
        let diameter = 16
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()

        // Draw white X
        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round

        // Draw X
        let inset = 5
        path.move(to: NSPoint(x: inset, y: inset))
        path.line(to: NSPoint(x: diameter - inset, y: diameter - inset))
        path.move(to: NSPoint(x: diameter - inset, y: inset))
        path.line(to: NSPoint(x: inset, y: diameter - inset))

        path.stroke()
        image.unlockFocus()

        return image
    }

    @objc private func deleteButtonClicked() {
        onDeleteRequested?()
    }

    func handleMouseEntered() {
        deleteButton.animator().alphaValue = 1
    }

    func handleMouseExited() {
        deleteButton.animator().alphaValue = 0
    }

    func configure(with filePath: String) {
        // Get file name without path
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        originalFileName = fileName // Store for later use

        // Configure text with custom Finder-style truncation
        setFinderStyleText(fileName)

        // Get file icon from system
        let icon = NSWorkspace.shared.icon(forFile: filePath)
        iconImageView.image = icon
        deleteButton.alphaValue = 0
    }

    private func setFinderStyleText(_ text: String) {
        let font = NSFont.systemFont(ofSize: 11)
        let color = isItemSelected ? NSColor.white : NSColor.labelColor
        let availableWidth: CGFloat = filenameLabelWidth - 10.0

        // Calculate if text fits on one line
        let singleLineSize = text.size(withAttributes: [.font: font])

        if singleLineSize.width <= availableWidth {
            // Fits on one line
            nameLabel.stringValue = text
        } else {
            // Need to wrap or truncate
            let components = text.componentsSeparatedLikeFinder

            if components.count == 1 {
                // Single word that's too long - use middle truncation
                let truncatedText = truncateMiddle(text, font: font, width: availableWidth * 2) // Allow for 2 lines
                nameLabel.stringValue = truncatedText
            } else {
                // Multiple words - try to wrap nicely
                let wrappedText = wrapTextForTwoLines(components, font: font, width: availableWidth)
                nameLabel.stringValue = wrappedText
            }
        }

        // Apply text color
        nameLabel.textColor = color
    }

    private func truncateMiddle(_ text: String, font: NSFont, width: CGFloat) -> String {
        let ellipsis = "…"
        let ellipsisWidth = ellipsis.size(withAttributes: [.font: font]).width
        let availableWidth = width - ellipsisWidth

        if text.size(withAttributes: [.font: font]).width <= width {
            return text
        }

        let halfWidth = availableWidth / 2
        var startIndex = text.startIndex
        var endIndex = text.endIndex

        // Find how much we can keep from the start
        while startIndex < text.endIndex {
            let nextIndex = text.index(after: startIndex)
            let substring = String(text[text.startIndex..<nextIndex])
            if substring.size(withAttributes: [.font: font]).width > halfWidth {
                break
            }
            startIndex = nextIndex
        }

        // Find how much we can keep from the end
        while endIndex > text.startIndex {
            let prevIndex = text.index(before: endIndex)
            let substring = String(text[prevIndex..<text.endIndex])
            if substring.size(withAttributes: [.font: font]).width > halfWidth {
                break
            }
            endIndex = prevIndex
        }

        let startPart = String(text[text.startIndex..<startIndex])
        let endPart = String(text[endIndex..<text.endIndex])

        return startPart + ellipsis + endPart
    }

    private func wrapTextForTwoLines(_ words: [SeparatedComponent], font: NSFont, width: CGFloat) -> String {
        let breakpoint = (0..<words.count).firstIndex { i in
            Array(words[0..<i]).joined().size(withAttributes: [.font: font]).width > width
        }
        guard let breakpoint else {
            return words.joined()
        }
        let firstLine: String
        if breakpoint == 0 {
            // The first word is too long
            firstLine = truncateMiddle(words[0].word, font: font, width: width)
        } else {
            firstLine = Array(words[0..<breakpoint]).joined()
        }
        let secondLineCandidate = Array(words[breakpoint...]).joined()
        if secondLineCandidate.size(withAttributes: [.font: font]).width <= width {
            return firstLine + "\n" + secondLineCandidate
        }
        return firstLine + "\n" + truncateMiddle(secondLineCandidate,
                                                 font: font,
                                                 width: width)
    }

    func setSelected(_ selected: Bool) {
        isItemSelected = selected

        // Show/hide the light gray overlay around just the icon
        iconSelectionOverlay.isHidden = !selected

        // NEW: Show delete button when selected
        if selected {
            deleteButton.isHidden = false
        }

        // Update label background color to match Finder's selection style
        if selected {
            nameLabel.backgroundColor = NSColor.selectedContentBackgroundColor
            nameLabel.drawsBackground = true
            nameLabel.wantsLayer = true
            nameLabel.layer?.cornerRadius = 4
        } else {
            nameLabel.backgroundColor = NSColor.clear
            nameLabel.drawsBackground = false
        }

        // Update text color by reconfiguring with original filename
        setFinderStyleText(originalFileName)
    }
}

extension HorizontalFileListView {
    private func deleteItem(at index: Int) {
        guard index >= 0 && index < files.count else { return }

        let fileToDelete = files[index]

        // Ask for permission to delete if callback is provided
        if let onItemsWillBeDeleted = onItemsWillBeDeleted {
            if !onItemsWillBeDeleted([fileToDelete]) {
                return // Deletion not allowed
            }
        }

        // Remove the item
        var newFiles = files
        newFiles.remove(at: index)

        // Update files (this will trigger the didSet and reload the collection view)
        files = newFiles

        onDidDeleteItems?()
        notifySelectionChanged()

        for item in collectionView.visibleItems() {
            (item as? FileItemView)?.refreshTracking()
        }
    }
}

struct SeparatedComponent {
    var word: String
    var separator: String?
}

extension String {
    var componentsSeparatedLikeFinder: [SeparatedComponent] {
        guard !isEmpty else { return [] }

        var components: [SeparatedComponent] = []
        var currentWord = ""
        var pendingWhitespace = ""

        let characters = Array(self)
        var i = 0

        while i < characters.count {
            let char = characters[i]

            if char.isWhitespace {
                // Collect whitespace
                if !currentWord.isEmpty {
                    // Add current word with collected whitespace as separator
                    components.append(SeparatedComponent(word: currentWord, separator: pendingWhitespace.isEmpty ? String(char) : pendingWhitespace + String(char)))
                    currentWord = ""
                    pendingWhitespace = ""
                } else {
                    pendingWhitespace += String(char)
                }
            } else {
                // Check if we need to split before adding this character
                if !currentWord.isEmpty && shouldSplitBefore(current: char, previous: characters[i-1], currentWord: currentWord) {
                    // Add the current word with empty separator (boundary split)
                    components.append(SeparatedComponent(word: currentWord, separator: ""))
                    currentWord = String(char)
                } else {
                    currentWord += String(char)
                }
            }

            i += 1
        }

        // Add the final word if it exists
        if !currentWord.isEmpty {
            components.append(SeparatedComponent(word: currentWord, separator: nil))
        }

        return components
    }

    private func shouldSplitBefore(current: Character, previous: Character, currentWord: String) -> Bool {
        // Rule 1: Split at boundary between letters/digits/punctuation
        let currentType = getCharacterType(current)
        let previousType = getCharacterType(previous)

        if currentType != previousType {
            return true
        }

        // Rule 2: Split when ALL CAPS meets Title Case (uppercase followed by lowercase)
        if currentType == .letter && previousType == .letter {
            if previous.isUppercase && current.isLowerCase {
                // Check if we have multiple uppercase letters before this
                // If currentWord has more than 1 character and the second-to-last is also uppercase
                if currentWord.count >= 2 {
                    let wordChars = Array(currentWord)
                    let secondToLast = wordChars[wordChars.count - 2]
                    if secondToLast.isUppercase {
                        return true
                    }
                }
            }
        }

        return false
    }

    private enum CharacterType {
        case letter
        case digit
        case punctuation
    }

    private func getCharacterType(_ char: Character) -> CharacterType {
        if char.isLetter {
            return .letter
        } else if char.isNumber {
            return .digit
        } else {
            return .punctuation
        }
    }
}

extension Character {
    var isLowerCase: Bool {
        return isLetter && self == self.lowercased().first
    }
}

extension Array where Element == SeparatedComponent {
    /// Joins an array of SeparatedComponent objects back into a single string
    func joined() -> String {
        return self.map { component in
            component.word + (component.separator ?? "")
        }.joined()
    }
}
