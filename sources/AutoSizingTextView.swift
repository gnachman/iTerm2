//
//  AutoSizingTextView.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//

class AutoSizingTextView: ClickableTextView {
    override var intrinsicContentSize: NSSize {
        guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else {
            return super.intrinsicContentSize
        }

        // Fix: Ensure text container width matches view bounds
        if bounds.width > 0 && abs(textContainer.size.width - bounds.width) > 1.0 {
            textContainer.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)

            // Force layout recalculation with new container size
            layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0),
                                           actualCharacterRange: nil)
        }

        layoutManager.ensureLayout(for: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        let size = NSSize(width: ceil(rect.maxX) + textContainerInset.width * 2,
                          height: ceil(bounding.maxY) + textContainerInset.height * 2)

        return size
    }
}

