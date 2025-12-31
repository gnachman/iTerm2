//
//  ExpressionBindingIconView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/31/25.
//

import Foundation

class ExpressionBindingIconView: NSView {
    private var iconView: NSImageView?

    private var iconSize: NSSize {
        NSSize(width: 10, height: 10)
    }
    private var iconContainerInset: CGFloat { 2.0 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let inset = iconContainerInset
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.masksToBounds = true
        layer?.cornerRadius = frame.size.width / 2
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.gray.cgColor

        // Create icon view inside container
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconSize.height * 0.8,
                                                       weight: .regular)
        let image = NSImage(
            systemSymbolName: "link",
            accessibilityDescription: "Expression Binding")?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.frame = NSRect(x: inset,
                                 y: inset,
                                 width: iconSize.width,
                                 height: iconSize.height)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .black

        addSubview(imageView)
        self.iconView = imageView
    }

    static var preferredSize: NSSize {
        let iconSize = NSSize(width: 10, height: 10)
        let inset: CGFloat = 2.0
        return NSSize(width: iconSize.width + inset * 2,
                      height: iconSize.height + inset * 2)
    }
}
