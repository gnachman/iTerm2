//
//  iTermUploadIndicator.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/11/26.
//

import AppKit

@objc(iTermUploadIndicator)
class iTermUploadIndicator: NSView {
    private let label = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton()
    private var onCancel: (() -> Void)?

    private let padding: CGFloat = 12
    private let spacing: CGFloat = 8
    private let verticalPadding: CGFloat = 8

    @objc init(filename: String, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        // Configure label
        label.stringValue = "Uploading \u{201C}\(filename)\u{201D}…"
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false

        // Configure progress indicator
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.startAnimation(nil)

        // Configure cancel button
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        addSubview(progressIndicator)
        addSubview(label)
        addSubview(cancelButton)

        layoutSubviews()
    }

    private func layoutSubviews() {
        // Size the controls
        progressIndicator.sizeToFit()
        label.sizeToFit()
        cancelButton.sizeToFit()

        // Limit label width
        let maxLabelWidth: CGFloat = 200
        var labelSize = label.frame.size
        if labelSize.width > maxLabelWidth {
            labelSize.width = maxLabelWidth
        }

        // Calculate total width and height
        let totalWidth = padding + progressIndicator.frame.width + spacing +
                         labelSize.width + spacing + cancelButton.frame.width + padding
        let contentHeight = max(progressIndicator.frame.height,
                               max(labelSize.height, cancelButton.frame.height))
        let totalHeight = verticalPadding + contentHeight + verticalPadding

        // Set our frame
        frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Position subviews (left to right, vertically centered)
        let centerY = totalHeight / 2

        var x = padding

        progressIndicator.frame.origin = NSPoint(
            x: x,
            y: centerY - progressIndicator.frame.height / 2
        )
        x += progressIndicator.frame.width + spacing

        label.frame = NSRect(
            x: x,
            y: centerY - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )
        x += labelSize.width + spacing

        cancelButton.frame.origin = NSPoint(
            x: x,
            y: centerY - cancelButton.frame.height / 2
        )
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc func animateInFromTopLeft(in superview: NSView) {
        let finalX: CGFloat = 20
        let finalY = superview.bounds.height - frame.height - 20
        let finalFrame = NSRect(x: finalX, y: finalY, width: frame.width, height: frame.height)

        // Start above the view
        var startFrame = finalFrame
        startFrame.origin.y = superview.bounds.height + frame.height
        self.frame = startFrame

        superview.addSubview(self)
        // Pin to top-left: flexible margin on right and below the view
        autoresizingMask = [.maxXMargin, .minYMargin]

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().frame = finalFrame
        }
    }

    @objc func animateOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            var frame = self.frame
            frame.origin.y = (self.superview?.bounds.height ?? 0) + self.frame.height
            self.animator().frame = frame
        } completionHandler: {
            self.removeFromSuperview()
            completion()
        }
    }
}
