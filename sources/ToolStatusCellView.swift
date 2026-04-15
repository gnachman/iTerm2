//
//  ToolStatusCellView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

class ToolStatusCellView: NSTableCellView {
    private let dotView = NSImageView()
    private var nameLabel = iTermSwiftyStringTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    private let margin: CGFloat = 4
    private let dotSize: CGFloat = 10
    private let dotNameSpacing: CGFloat = 4
    private let rowSpacing: CGFloat = 1
    // Detail text hangs one indent level in from the status row.
    private let detailIndent: CGFloat = 14
    private let maxDetailLines = 3

    override init(frame: NSRect) {
        let font = NSFont.it_toolbelt()

        super.init(frame: frame)

        dotView.imageScaling = .scaleProportionallyDown
        addSubview(dotView)

        nameLabel.font = font
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)

        shortcutLabel.font = font
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.lineBreakMode = .byClipping
        addSubview(shortcutLabel)

        statusLabel.font = font
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)

        detailLabel.font = font
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = maxDetailLines
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.cell?.wraps = true
        detailLabel.cell?.isScrollable = false
        detailLabel.cell?.truncatesLastVisibleLine = true
        detailLabel.usesSingleLineMode = false
        detailLabel.isHidden = true
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    var currentShortcut: String { shortcutLabel.stringValue }

    override var isFlipped: Bool { true }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateShortcutColor()
        }
    }

    private func updateShortcutColor() {
        if backgroundStyle == .emphasized {
            shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        } else {
            shortcutLabel.textColor = .tertiaryLabelColor
        }
    }

    private var textLeft: CGFloat {
        let dotWidth = dotView.isHidden ? 0 : (dotSize + dotNameSpacing)
        return margin + dotWidth
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutManually()
    }

    private func layoutManually() {
        let width = bounds.width
        let textX = textLeft
        let textWidth = max(0, width - textX - margin)
        var y: CGFloat = margin / 2

        // Shortcut label — measure first so we can reserve space
        var shortcutWidth: CGFloat = 0
        if !shortcutLabel.isHidden {
            shortcutLabel.sizeToFit()
            shortcutWidth = shortcutLabel.frame.width
        }

        // Name label
        let nameWidth = max(0, textWidth - (shortcutWidth > 0 ? shortcutWidth + dotNameSpacing : 0))
        nameLabel.frame = NSRect(x: textX, y: y, width: nameWidth, height: 0)
        nameLabel.sizeToFit()
        nameLabel.frame = NSRect(x: textX, y: y,
                                 width: nameWidth,
                                 height: nameLabel.frame.height)

        // Place shortcut label right-aligned on the name row
        if !shortcutLabel.isHidden {
            let shortcutX = width - margin - shortcutWidth
            shortcutLabel.frame = NSRect(x: shortcutX, y: y,
                                         width: shortcutWidth,
                                         height: nameLabel.frame.height)
        }

        // Dot — vertically centered with name label
        if !dotView.isHidden {
            let dotY = y + (nameLabel.frame.height - dotSize) / 2
            dotView.frame = NSRect(x: margin, y: dotY, width: dotSize, height: dotSize)
        }

        y += nameLabel.frame.height + rowSpacing

        // Status label
        if !statusLabel.isHidden {
            statusLabel.frame = NSRect(x: textX, y: y, width: textWidth, height: 0)
            statusLabel.sizeToFit()
            statusLabel.frame = NSRect(x: textX, y: y,
                                       width: textWidth,
                                       height: statusLabel.frame.height)
            y += statusLabel.frame.height + rowSpacing
        }

        // Detail label — indented one additional level from the status row,
        // word-wrapped up to maxDetailLines, tail-truncated if it overflows.
        if !detailLabel.isHidden {
            let detailX = textX + detailIndent
            let detailWidth = max(0, width - detailX - margin)
            let font = detailLabel.font ?? NSFont.it_toolbelt()
            let textBounds = (detailLabel.stringValue as NSString).boundingRect(
                with: CGSize(width: detailWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font])
            let lineHeight = ceil(font.boundingRectForFont.height)
            let maxHeight = lineHeight * CGFloat(maxDetailLines)
            let measuredHeight = ceil(textBounds.height)
            let h = min(measuredHeight, maxHeight)
            detailLabel.preferredMaxLayoutWidth = detailWidth
            detailLabel.frame = NSRect(x: detailX, y: y, width: detailWidth, height: h)
        }
    }

    override var fittingSize: NSSize {
        layoutManually()
        var maxY: CGFloat = nameLabel.frame.maxY
        if !statusLabel.isHidden {
            maxY = statusLabel.frame.maxY
        }
        if !detailLabel.isHidden {
            maxY = detailLabel.frame.maxY
        }
        return NSSize(width: bounds.width, height: maxY + margin / 2)
    }

    func configure(scope: iTermVariableScope,
                   dotImage: NSImage?,
                   shortcut: String?,
                   statusText: String?,
                   statusColor: NSColor?,
                   detail: String?) {
        nameLabel.set(interpolatedString: #"\(iterm2.private.session_name(session: id))"#, scope: scope)
        dotView.image = dotImage
        dotView.isHidden = dotImage == nil

        shortcutLabel.stringValue = shortcut ?? ""
        shortcutLabel.isHidden = (shortcut ?? "").isEmpty

        statusLabel.stringValue = statusText ?? ""
        if let statusColor {
            statusLabel.textColor = statusColor
        } else {
            statusLabel.textColor = .secondaryLabelColor
        }
        statusLabel.isHidden = (statusText ?? "").isEmpty

        if let detail, !detail.isEmpty {
            detailLabel.stringValue = detail
            detailLabel.isHidden = false
        } else {
            detailLabel.stringValue = ""
            detailLabel.isHidden = true
        }

        layoutManually()
    }
}
