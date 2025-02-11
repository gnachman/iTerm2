//
//  SystemMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/24/25.
//

class SystemMessageCellView: RegularMessageCellView {
    override func addHorizontalAlignmentConstraints(_ rendition: MessageRendition) {
        add(constraint: bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor))
        add(constraint: bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8))
        add(constraint: bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8))
    }

    override func backgroundColorPair(_ rendition: MessageRendition) -> (NSColor, NSColor) {
        return (NSColor(fromHexString: "#ffffc0")!,
                NSColor(fromHexString: "#202020")!)
    }

    override func setupViews() {
        super.setupViews()
        bubbleView.layer?.borderColor = NSColor.gray.cgColor
        bubbleView.layer?.borderWidth = 1.0
    }
}
