//
//  FileAttachmentSubpartView.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

import Cocoa

class FileAttachmentSubpartView: NSView {
    private let icon: NSImage
    private let filename: NSAttributedString
    private let id: String
    private let file: LLM.Message.Attachment.AttachmentType.File?
    private let name: String
    private let attachment: LLM.Message.Attachment
    private var timer: Timer?

    private let iconImageView = NSImageView()
    private let filenameLabel = NSTextField()
    private var dragTimer: Timer?

    init(icon: NSImage, filename: NSAttributedString, id: String, name: String, file: LLM.Message.Attachment.AttachmentType.File?) {
        self.icon = icon
        self.id = id
        self.filename = filename
        self.name = name
        self.file = file
        if let file {
            self.attachment = LLM.Message.Attachment(inline: false, id: id, type: .file(file))
        } else {
            self.attachment = LLM.Message.Attachment(inline: false, id: id, type: .fileID(id: id, name: name))
        }
        super.init(frame: .zero)

        setupView()
        setupLayout()
        setupDragAndDrop()
        setupContextMenu()
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        } else {
            return nil
        }
    }

    private func setupView() {
        // Configure the main view
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.cornerRadius = 3
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.controlColor.cgColor

        // Configure icon
        iconImageView.image = icon
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        // Configure filename label
        filenameLabel.attributedStringValue = filename
        filenameLabel.isEditable = false
        filenameLabel.isSelectable = false
        filenameLabel.isBordered = false
        filenameLabel.backgroundColor = .clear
        filenameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconImageView)
        addSubview(filenameLabel)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            // Icon constraints
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),

            // Filename label constraints
            filenameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            filenameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            filenameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Height constraint for the whole view
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupDragAndDrop() {
        // Register for drag operations
        registerForDraggedTypes([.fileURL])
    }

    private func setupContextMenu() {
        let menu = NSMenu()

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        let openItem = NSMenuItem(title: "Open", action: #selector(openFile), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        self.menu = menu
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Handle double-click to open file
            timer?.invalidate()
            timer = nil
            dragTimer?.invalidate()
            dragTimer = nil
            openFile()
        } else {
            // Delay drag initiation to allow for potential double-click
            timer = Timer.scheduledTimer(timeInterval: NSEvent.doubleClickInterval,
                                         target: self,
                                         selector: #selector(initiateDrag(with:)),
                                         userInfo: event,
                                         repeats: false)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Handle right-click for context menu
        if let menu = self.menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    @objc private func initiateDrag(with timer: Timer) {
        let event = timer.userInfo as! NSEvent
        // Handle single click for drag initiation
        let dragImage = createDragImage()

        // Ensure file exists and get its path
        let filePath = attachment.localPathCreatingIfNeeded()
        let fileURL = URL(fileURLWithPath: filePath)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: dragImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func createDragImage() -> NSImage {
        // Create a drag image that looks like the view
        let dragImage = NSImage(size: bounds.size)
        dragImage.lockFocus()

        // Draw the background
        NSColor.white.withAlphaComponent(0.25).setFill()
        let backgroundRect = NSRect(origin: .zero, size: bounds.size)
        let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 6, yRadius: 6)
        backgroundPath.fill()

        // Draw the border
        NSColor.controlColor.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()

        // Draw the icon
        let iconRect = NSRect(x: 8, y: (bounds.height - 16) / 2, width: 16, height: 16)
        icon.draw(in: iconRect)

        // Draw the filename
        let textRect = NSRect(x: 30, y: (bounds.height - 20) / 2, width: bounds.width - 38, height: 20)
        filename.draw(in: textRect)

        dragImage.unlockFocus()
        return dragImage
    }

    // MARK: - Context Menu Actions

    @objc private func revealInFinder() {
        let filePath = attachment.localPathCreatingIfNeeded()
        let fileURL = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
    }

    @objc private func openFile() {
        let filePath = attachment.localPathCreatingIfNeeded()
        let fileURL = URL(fileURLWithPath: filePath)
        NSWorkspace.shared.open(fileURL)
    }
}

// MARK: - NSDraggingSource

extension FileAttachmentSubpartView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // Optional: Add visual feedback when drag begins
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Optional: Clean up after drag ends
    }
}
