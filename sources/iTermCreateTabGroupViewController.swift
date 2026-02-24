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

    private var selectedColorIndex: Int = 0
    private var nameField: NSTextField!
    private var swatchButtons: [NSButton] = []
    private var doneButton: NSButton!

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 180))
        self.view = container

        let titleLabel = NSTextField(labelWithString: "Create Tab Group")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        let nameLabel = NSTextField(labelWithString: "Name")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        nameField = NSTextField()
        nameField.placeholderString = "Example: Work"
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.delegate = self
        container.addSubview(nameField)

        let swatchRow = buildSwatchRow()
        swatchRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(swatchRow)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(cancelButton)

        doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked(_:)))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.isEnabled = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(doneButton)

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
            swatchRow.widthAnchor.constraint(equalToConstant: CGFloat(swatchColors.count) * swatchDiameter + CGFloat(swatchColors.count - 1) * swatchSpacing),
            swatchRow.heightAnchor.constraint(equalToConstant: swatchDiameter),

            cancelButton.topAnchor.constraint(equalTo: swatchRow.bottomAnchor, constant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

            doneButton.topAnchor.constraint(equalTo: swatchRow.bottomAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            doneButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        updateSwatchSelection()
    }

    private func buildSwatchRow() -> NSView {
        let container = NSView()
        for (index, (color, _)) in swatchColors.enumerated() {
            let button = NSButton()
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
        return container
    }

    private func updateSwatchSelection() {
        for (index, button) in swatchButtons.enumerated() {
            button.layer?.borderWidth = index == selectedColorIndex ? 2.5 : 0
            button.layer?.borderColor = NSColor.white.cgColor
        }
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        selectedColorIndex = sender.tag
        updateSwatchSelection()
    }

    @objc private func cancelClicked(_ sender: Any?) {
        completion(nil)
    }

    @objc private func doneClicked(_ sender: Any?) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        completion((name, swatchColors[selectedColorIndex].0))
    }
}

extension iTermCreateTabGroupViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        doneButton.isEnabled = !nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
