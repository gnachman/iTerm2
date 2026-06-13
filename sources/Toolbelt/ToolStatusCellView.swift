//
//  ToolStatusCellView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

// Indicator-only image view that never intercepts mouse clicks, so a
// click on the bell still selects/reveals the row like clicking the text.
private final class ToolStatusPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

class ToolStatusCellView: NSTableCellView {
    // Shown at the leading edge when this session has notify-on-change
    // armed, mirroring the Cockpit's row indicator.
    private let bellView = ToolStatusPassthroughImageView()
    private let dotView = NSImageView()
    // Optional peer-group label inserted between the dot and the
    // session name when the session belongs to a multi-peer workgroup.
    // Hidden for solo sessions.
    private let peerLabel = NSTextField(labelWithString: "")
    private var nameLabel = iTermSwiftyStringTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    private let margin: CGFloat = 4
    private let bellSize: CGFloat = 12
    private let bellSpacing: CGFloat = 3
    private let dotSize: CGFloat = 10
    private let dotNameSpacing: CGFloat = 4
    // Gap between the peer label and the session name.
    private let peerNameSpacing: CGFloat = 6
    private let rowSpacing: CGFloat = 1
    // Detail text hangs one indent level in from the status row.
    private let detailIndent: CGFloat = 14
    private let maxDetailLines = 3

    override init(frame: NSRect) {
        let font = NSFont.it_toolbelt()

        super.init(frame: frame)

        let bellConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        bellView.image = NSImage(systemSymbolName: SFSymbol.bellBadge.rawValue,
                                 accessibilityDescription: "Notify on status change armed")?
            .withSymbolConfiguration(bellConfig)
        bellView.imageScaling = .scaleProportionallyDown
        bellView.contentTintColor = .controlAccentColor
        bellView.isHidden = true
        addSubview(bellView)

        dotView.imageScaling = .scaleProportionallyDown
        addSubview(dotView)

        peerLabel.font = font
        peerLabel.textColor = .secondaryLabelColor
        peerLabel.lineBreakMode = .byTruncatingTail
        peerLabel.isHidden = true
        addSubview(peerLabel)

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

    override var isFlipped: Bool { true }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateShortcutColor()
        }
    }

    private func updateShortcutColor() {
        if backgroundStyle == .emphasized {
            shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.7)
            bellView.contentTintColor = .alternateSelectedControlTextColor
        } else {
            shortcutLabel.textColor = .tertiaryLabelColor
            bellView.contentTintColor = .controlAccentColor
        }
    }

    private var bellReserve: CGFloat {
        return bellView.isHidden ? 0 : (bellSize + bellSpacing)
    }

    private var textLeft: CGFloat {
        let dotWidth = dotView.isHidden ? 0 : (dotSize + dotNameSpacing)
        return margin + bellReserve + dotWidth
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
        let shortcutReserve = shortcutWidth > 0 ? shortcutWidth + dotNameSpacing : 0

        // Peer label — capped at half of what's left *after* the
        // shortcut reservation so the name is guaranteed at least as
        // much room as the peer label, even on narrow toolbelts where
        // a wide shortcut would otherwise crowd both out.
        var peerWidth: CGFloat = 0
        if !peerLabel.isHidden {
            peerLabel.sizeToFit()
            let peerBudget = max(0, textWidth - shortcutReserve) / 2
            peerWidth = min(peerLabel.frame.width, peerBudget)
        }

        // Name label gets whatever's left after the shortcut and
        // optional peer label.
        let peerReserve = peerWidth > 0 ? peerWidth + peerNameSpacing : 0
        let nameWidth = max(0, textWidth - shortcutReserve - peerReserve)
        let nameX = textX + peerReserve
        nameLabel.frame = NSRect(x: nameX, y: y, width: nameWidth, height: 0)
        nameLabel.sizeToFit()
        nameLabel.frame = NSRect(x: nameX, y: y,
                                 width: nameWidth,
                                 height: nameLabel.frame.height)

        // Place peer label between dot and name
        if peerWidth > 0 {
            peerLabel.frame = NSRect(x: textX, y: y,
                                     width: peerWidth,
                                     height: nameLabel.frame.height)
        }

        // Place shortcut label right-aligned on the name row
        if !shortcutLabel.isHidden {
            let shortcutX = width - margin - shortcutWidth
            shortcutLabel.frame = NSRect(x: shortcutX, y: y,
                                         width: shortcutWidth,
                                         height: nameLabel.frame.height)
        }

        // Bell — leading edge, vertically centered with the name row.
        if !bellView.isHidden {
            let bellY = y + (nameLabel.frame.height - bellSize) / 2
            bellView.frame = NSRect(x: margin, y: bellY, width: bellSize, height: bellSize)
        }

        // Dot — vertically centered with name label, after the bell.
        if !dotView.isHidden {
            let dotY = y + (nameLabel.frame.height - dotSize) / 2
            dotView.frame = NSRect(x: margin + bellReserve, y: dotY, width: dotSize, height: dotSize)
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
                   peerLabel: String?,
                   shortcut: String?,
                   statusText: String?,
                   statusColor: NSColor?,
                   detail: String?,
                   armed: Bool) {
        nameLabel.set(interpolatedString: #"\(iterm2.private.session_name(session: id))"#, scope: scope)
        bellView.isHidden = !armed
        dotView.image = dotImage
        dotView.isHidden = dotImage == nil

        let peerText = peerLabel ?? ""
        self.peerLabel.stringValue = peerText
        self.peerLabel.isHidden = peerText.isEmpty

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
