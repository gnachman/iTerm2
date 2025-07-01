//
//  iTermBrowserURLTextView.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

@available(macOS 11.0, *)
class iTermBrowserURLTextView: PlaceholderTextView {
    var willBecomeFirstResponder: (() -> ())?
    var willResignFirstResponder: (() -> ())?
    var shouldSelectAllOnMouseDown = true

    init(frame: NSRect, textContainer: NSTextContainer) {
        super.init(frame: frame, textContainer: textContainer)

        // allow width to grow and report its own size
        isHorizontallyResizable = true
        isVerticallyResizable = false
        textContainer.widthTracksTextView = false
        textContainer.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        // Disable focus ring since the containing view will draw it
        focusRingType = .none
    }

    @MainActor required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }
    
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        guard result && window?.firstResponder == self else {
            return result
        }
        willBecomeFirstResponder?()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        shouldSelectAllOnMouseDown = true
        willResignFirstResponder?()

        DispatchQueue.main.async {
            var range = self.selectedRange()
            range.location = range.upperBound
            range.length = 0
            self.setSelectedRange(range)
            self.discardCursorRects()
        }

        return result
    }

    override func mouseDown(with event: NSEvent) {
        let select = shouldSelectAllOnMouseDown
        shouldSelectAllOnMouseDown = false

        super.mouseDown(with: event)

        if select {
            selectAll(nil)
        }
    }

    // Invalidate when text changes
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else {
            return super.intrinsicContentSize
        }

        // Ensure text container width matches view bounds
        if bounds.width > 0 && abs(textContainer.size.width - bounds.width) > 1.0 {
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                        height: CGFloat.greatestFiniteMagnitude)
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
