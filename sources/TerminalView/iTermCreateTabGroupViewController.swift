import Cocoa

@objc class iTermCreateTabGroupViewController: NSViewController {
    var completion: ((String, NSColor)?) -> Void = { _ in }

    private let swatchDiameter: CGFloat = 24
    private let swatchSpacing: CGFloat = 8

    private let swatchColors: [(NSColor, String)] = [
        (NSColor(srgbRed: 0.259, green: 0.522, blue: 0.957, alpha: 1), "#4285F4"),
        (NSColor(srgbRed: 0.612, green: 0.153, blue: 0.690, alpha: 1), "#9C27B0"),
        (NSColor(srgbRed: 0.000, green: 0.537, blue: 0.482, alpha: 1), "#00897B"),
        (NSColor(srgbRed: 0.902, green: 0.318, blue: 0.000, alpha: 1), "#E65100"),
        (NSColor(srgbRed: 0.961, green: 0.498, blue: 0.090, alpha: 1), "#F57F17"),
        (NSColor(srgbRed: 0.678, green: 0.078, blue: 0.341, alpha: 1), "#AD1457"),
        (NSColor(srgbRed: 0.180, green: 0.490, blue: 0.196, alpha: 1), "#2E7D32"),
        (NSColor(srgbRed: 0.329, green: 0.431, blue: 0.478, alpha: 1), "#546E7A"),
        (NSColor(srgbRed: 0.776, green: 0.157, blue: 0.157, alpha: 1), "#C62828"),
    ]

    private let customColorIndex: Int
    private var selectedColorIndex: Int = 0
    private var nameField: NSTextField!
    private var swatchButtons: [NSButton] = []
    private var customColorButton: NSButton!
    private var customColor: NSColor
    private var doneButton: NSButton!
    private var ownsColorPanel = false
    private let isEditMode: Bool
    private let isManageMode: Bool
    private let initialName: String

    // Manage-mode (popover) callbacks. Name and colour apply live as the user
    // edits; the action closures run the corresponding group operation. All are
    // ignored in the create/edit sheet, which commits via `completion` instead.
    var onNameChange: ((String) -> Void)?
    var onColorChange: ((NSColor) -> Void)?
    var onNewTabInGroup: (() -> Void)?
    var onUngroup: (() -> Void)?
    var onCloseGroup: (() -> Void)?

    init(initialColor: NSColor? = nil, initialName: String = "", editMode: Bool = false, manageMode: Bool = false) {
        customColorIndex = swatchColors.count
        customColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        isEditMode = editMode
        isManageMode = manageMode
        self.initialName = initialName
        super.init(nibName: nil, bundle: nil)
        guard let c = initialColor?.usingColorSpace(.sRGB) else { return }
        let matchIndex = swatchColors.enumerated().first { _, pair in
            guard let s = pair.0.usingColorSpace(.sRGB) else { return false }
            return abs(s.redComponent - c.redComponent) < 0.01
                && abs(s.greenComponent - c.greenComponent) < 0.01
                && abs(s.blueComponent - c.blueComponent) < 0.01
        }?.offset
        if let idx = matchIndex {
            selectedColorIndex = idx
        } else {
            customColor = c
            selectedColorIndex = customColorIndex
        }
    }

    required init?(coder: NSCoder) {
        customColorIndex = swatchColors.count
        customColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        isEditMode = false
        isManageMode = false
        initialName = ""
        super.init(coder: coder)
    }

    deinit {
        dismissColorPanel()
    }

    override func loadView() {
        if isManageMode {
            loadManageView()
            return
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
        self.view = container

        let titleLabel = NSTextField(labelWithString: isEditMode ? "Edit Tab Group" : "Create Tab Group")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        nameField = NSTextField()
        nameField.placeholderString = "Name this group (optional)"
        nameField.stringValue = initialName
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.delegate = self
        container.addSubview(nameField)

        let swatchRow = buildSwatchRow()
        swatchRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(swatchRow)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelButton)

        doneButton = NSButton(title: isEditMode ? "Save" : "Done", target: self, action: #selector(doneClicked(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.isEnabled = true
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(doneButton)

        let swatchRowWidth = CGFloat(customColorIndex) * swatchDiameter
            + CGFloat(customColorIndex - 1) * swatchSpacing
            + swatchSpacing + swatchDiameter

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            nameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            swatchRow.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            swatchRow.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            swatchRow.widthAnchor.constraint(equalToConstant: swatchRowWidth),
            swatchRow.heightAnchor.constraint(equalToConstant: swatchDiameter),

            cancelButton.topAnchor.constraint(equalTo: swatchRow.bottomAnchor, constant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            doneButton.topAnchor.constraint(equalTo: swatchRow.bottomAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        updateSwatchSelection()
        customColorButton.layer?.backgroundColor = customColor.cgColor
    }

    // Chrome-style management popover: name + colour swatches + group actions in
    // a single transient surface. Name and colour apply live; actions invoke the
    // corresponding closure (the presenter closes the popover).
    private func loadManageView() {
        let padding: CGFloat = 14
        let swatchRowWidth = CGFloat(customColorIndex) * swatchDiameter
            + CGFloat(customColorIndex - 1) * swatchSpacing
            + swatchSpacing + swatchDiameter
        let contentWidth = swatchRowWidth

        nameField = NSTextField()
        nameField.placeholderString = "Name this group (optional)"
        nameField.stringValue = initialName
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let swatchRow = buildSwatchRow()
        swatchRow.translatesAutoresizingMaskIntoConstraints = false

        let newTabButton = makeActionButton(title: "New tab in group",
                                             symbol: "plus.square.on.square",
                                             action: #selector(newTabInGroupClicked(_:)))
        let ungroupButton = makeActionButton(title: "Ungroup",
                                             symbol: "rectangle.dashed",
                                             action: #selector(ungroupClicked(_:)))
        let closeGroupButton = makeActionButton(title: "Close group",
                                                symbol: "xmark.square",
                                                action: #selector(closeGroupClicked(_:)))

        let topSeparator = makeSeparator()

        let stack = NSStackView(views: [
            nameField,
            swatchRow,
            topSeparator,
            newTabButton,
            ungroupButton,
            closeGroupButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(12, after: swatchRow)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        self.view = container
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),

            nameField.widthAnchor.constraint(equalToConstant: contentWidth),
            swatchRow.widthAnchor.constraint(equalToConstant: swatchRowWidth),
            swatchRow.heightAnchor.constraint(equalToConstant: swatchDiameter),
            topSeparator.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        updateSwatchSelection()
        customColorButton.layer?.backgroundColor = customColor.cgColor
        container.layoutSubtreeIfNeeded()
        preferredContentSize = container.fittingSize
    }

    private func makeActionButton(title: String, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: " \(title)", target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.alignment = .left
        button.imagePosition = .imageLeading
        button.contentTintColor = .labelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    @objc private func newTabInGroupClicked(_ sender: Any?) { onNewTabInGroup?() }
    @objc private func ungroupClicked(_ sender: Any?) { onUngroup?() }
    @objc private func closeGroupClicked(_ sender: Any?) { onCloseGroup?() }

    private func notifyColorChange() {
        guard isManageMode else { return }
        onColorChange?(selectedColorIndex == customColorIndex ? customColor : swatchColors[selectedColorIndex].0)
    }

    private func buildSwatchRow() -> NSView {
        let container = NSView()
        for (index, (color, _)) in swatchColors.enumerated() {
            let button = NSButton()
            button.title = ""
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = swatchDiameter / 2
            button.layer?.backgroundColor = color.cgColor
            button.tag = index
            button.target = self
            button.action = #selector(swatchClicked(_:))
            button.frame = NSRect(x: CGFloat(index) * (swatchDiameter + swatchSpacing),
                                  y: 0,
                                  width: swatchDiameter,
                                  height: swatchDiameter)
            container.addSubview(button)
            swatchButtons.append(button)
        }

        customColorButton = NSButton()
        customColorButton.title = ""
        customColorButton.isBordered = false
        customColorButton.wantsLayer = true
        customColorButton.layer?.cornerRadius = swatchDiameter / 2
        customColorButton.layer?.backgroundColor = customColor.cgColor
        if let icon = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Custom colour") {
            customColorButton.image = icon
            customColorButton.imagePosition = .imageOnly
            customColorButton.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        }
        customColorButton.tag = customColorIndex
        customColorButton.target = self
        customColorButton.action = #selector(customColorActivated(_:))
        customColorButton.frame = NSRect(x: CGFloat(customColorIndex) * (swatchDiameter + swatchSpacing),
                                         y: 0,
                                         width: swatchDiameter,
                                         height: swatchDiameter)
        container.addSubview(customColorButton)
        return container
    }

    private func updateSwatchSelection() {
        for (index, button) in swatchButtons.enumerated() {
            button.layer?.borderWidth = index == selectedColorIndex ? 2.5 : 0
            button.layer?.borderColor = NSColor.white.cgColor
        }
        customColorButton.layer?.borderWidth = selectedColorIndex == customColorIndex ? 2.5 : 0
        customColorButton.layer?.borderColor = NSColor.white.cgColor
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        selectedColorIndex = sender.tag
        updateSwatchSelection()
        notifyColorChange()
    }

    @objc private func customColorActivated(_ sender: NSButton) {
        selectedColorIndex = customColorIndex
        updateSwatchSelection()
        notifyColorChange()
        let panel = NSColorPanel.shared
        panel.color = customColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelColorChanged(_:)))
        ownsColorPanel = true
        panel.orderFront(nil)
    }

    @objc private func colorPanelColorChanged(_ sender: NSColorPanel) {
        customColor = sender.color
        customColorButton.layer?.backgroundColor = customColor.cgColor
        if selectedColorIndex == customColorIndex {
            updateSwatchSelection()
            notifyColorChange()
        }
    }

    @objc private func cancelClicked(_ sender: Any?) {
        dismissColorPanel()
        completion(nil)
    }

    @objc private func doneClicked(_ sender: Any?) {
        dismissColorPanel()
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let color: NSColor
        if selectedColorIndex == customColorIndex {
            color = customColor
        } else {
            color = swatchColors[selectedColorIndex].0
        }
        completion((name, color))
    }

    private func dismissColorPanel() {
        guard ownsColorPanel else { return }
        ownsColorPanel = false
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }
}

extension iTermCreateTabGroupViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard isManageMode else { return }
        onNameChange?(nameField.stringValue.trimmingCharacters(in: .whitespaces))
    }
}
