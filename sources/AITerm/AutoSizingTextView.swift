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

        // Ensure text container width matches view bounds
        if bounds.width > 0 && abs(textContainer.size.width - bounds.width) > 1.0 {
            textContainer.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
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

    // Size required to fully render the current text storage when wrapped
    // to the given content width. The text container is sized to the
    // requested width before measuring; layout is invalidated so the
    // result reflects the new width. Used by manual layout call sites that
    // need to pre-measure without round-tripping through bounds.
    func desiredSize(forContentWidth width: CGFloat) -> NSSize {
        guard let textContainer = self.textContainer,
              let layoutManager = self.layoutManager else {
            return .zero
        }
        let inset = textContainerInset
        let containerWidth = max(0, width - inset.width * 2)
        if abs(textContainer.size.width - containerWidth) > 1.0 {
            textContainer.size = NSSize(width: containerWidth,
                                        height: CGFloat.greatestFiniteMagnitude)
            layoutManager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0),
                actualCharacterRange: nil)
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        return NSSize(width: ceil(used.maxX) + inset.width * 2,
                      height: ceil(bounding.maxY) + inset.height * 2)
    }
}

