//
//  SystemMessageCellView.swift
//  iTerm2
//
//  Created by George Nachman on 2/24/25.
//

class SystemMessageCellView: RegularMessageCellView {
    override func bubbleOriginX(bubbleWidth: CGFloat) -> CGFloat {
        return Self.bubbleEdgePadding
    }

    override func backgroundColorPair(_ rendition: MessageRendition) -> (NSColor, NSColor) {
        return (NSColor(fromHexString: "p3#e9e9eb")!,
                NSColor(fromHexString: "p3#2f3033")!)
    }

    override func shouldDrawBubbleChrome(for rendition: MessageRendition) -> Bool {
        return false
    }
}
