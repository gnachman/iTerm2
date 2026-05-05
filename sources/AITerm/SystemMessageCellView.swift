//
//  SystemMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/24/25.
//

class SystemMessageCellView: RegularMessageCellView {
    override func bubbleOriginX(bubbleWidth: CGFloat) -> CGFloat {
        let centered = floor((bounds.width - bubbleWidth) / 2)
        return max(Self.bubbleEdgePadding, centered)
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
