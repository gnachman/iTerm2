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

    // When the text is selectable the text view (not the cell) is the hit
    // target for a right click, so AppKit shows NSTextView's default menu
    // instead of the cell's Edit/Copy/Fork/Delete menu. Graft the
    // message-level actions onto that default menu so they remain reachable.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let menu, let cell = enclosingMessageCellView {
            cell.augmentTextViewMenu(menu)
        }
        return menu
    }

    private var enclosingMessageCellView: MessageCellView? {
        var view = superview
        while let current = view {
            if let cell = current as? MessageCellView {
                return cell
            }
            view = current.superview
        }
        return nil
    }

    // A focused message text view otherwise claims performFindPanelAction:
    // for its own content, disabling Cmd-F for the conversation. Forward it
    // (and its validation) to the enclosing ChatViewController.
    override func performFindPanelAction(_ sender: Any?) {
        if let controller = enclosingChatViewController {
            controller.performFindPanelAction(sender)
        } else {
            super.performFindPanelAction(sender)
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action,
           let controller = enclosingChatViewController,
           controller.isFindAction(action) {
            return controller.validateFindAction(action, tag: item.tag)
        }
        return super.validateUserInterfaceItem(item)
    }

    // Report clicks so an open find bar can anchor Find Next/Previous to the
    // click location. super.mouseDown returns after the selection is set.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        enclosingChatViewController?.conversationTextViewDidReceiveClick(self)
    }
}

