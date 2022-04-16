//
//  PortholeContainerView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

class PortholeContainerView: NSView {
    static let margin = CGFloat(4.0)
    var closeCallback: (() -> ())? = nil
    let closeButton = SaneButton()
    var accessory: NSView? = nil {
        willSet {
            accessory?.removeFromSuperview()
        }
        didSet {
            if let accessory = accessory {
                addSubview(accessory)
            }
        }
    }

    var color = NSColor.textColor {
        didSet {
            layer?.borderColor = color.withAlphaComponent(0.5).cgColor
            closeButton.image = Self.closeButtonImage(color)
        }
    }
    var backgroundColor = NSColor.textBackgroundColor {
        didSet {
            let dimmed = backgroundColor.usingColorSpace(.sRGB)!.colorDimmed(by: 0.2,
                                                                             towardsGrayLevel: 0.5)
            layer?.backgroundColor = dimmed.cgColor
        }
    }

    static func closeButtonImage(_ color: NSColor) -> NSImage {
        if #available(macOS 11.0, *) {
            if let image = NSImage(systemSymbolName: "xmark.circle",
                                   accessibilityDescription: "Close markdown view") {
                return image.it_image(withTintColor: color)
            }
        }
        return NSImage.it_imageNamed("closebutton", for: Self.self)!.it_image(withTintColor: color)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        wantsLayer = true
        layer = CALayer()
        layer?.borderColor = NSColor.init(white: 0.5, alpha: 0.5).cgColor
        layer?.backgroundColor = NSColor.init(white: 0.5, alpha: 0.1).cgColor
        layer?.borderWidth = 1.0
        layer?.cornerRadius = 4
        autoresizesSubviews = false

        closeButton.image = Self.closeButtonImage(NSColor.textColor)
        closeButton.sizeToFit()
        closeButton.target = self
        closeButton.action = #selector(close(_:))
        closeButton.isBordered = false
        closeButton.title = ""
        closeButton.autoresizingMask = []
        closeButton.alphaValue = 0.5
        addSubview(closeButton)


        _ = layoutSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func setContentSize(_ size: NSSize) {
        guard subviews.count > 0 else {
            return
        }
        var frame = NSRect.zero
        var adjustedSize = size
        adjustedSize.height -= Self.margin * 2
        adjustedSize.height = max(0, adjustedSize.height)
        frame.size = adjustedSize
        frame.origin.x = (bounds.width - size.width) / 2
        frame.origin.y = (bounds.height - size.height) / 2
        subviews[0].frame = frame
        _ = layoutSubviews()
    }

    @objc func close(_ sender: AnyObject?) {
        closeCallback?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        DLog("\(it_addressString): set frame size to \(newSize)")
        super.setFrameSize(newSize)
        let ok = layoutSubviews()
        if !ok {
            closeCallback?()
            closeCallback = nil
        }
    }

    func layoutSubviews() -> Bool {
        closeButton.sizeToFit()
        let ok = layoutCloseButton()
        if let accessory = accessory {
            layoutAccessory(accessory)
        }
        layoutChild()
        return ok
    }

    private func layoutCloseButton() -> Bool {
        var frame = closeButton.frame
        let margin = 2.0
        frame.origin.x = bounds.width - closeButton.frame.width - margin
        frame.origin.y = bounds.height - closeButton.frame.height - margin
        closeButton.frame = frame
        DLog("\(it_addressString) Set close button frame to \(frame). My bounds is \(bounds)")

        return bounds.height >= frame.maxY + margin && frame.minY >= margin
    }

    private func layoutChild() {
        guard let child = subviews.first else {
            return
        }
        var frame = child.frame
        frame.size.width = bounds.width;
        frame.size.height = max(0, bounds.height - Self.margin * 2)
        frame.origin.y = Self.margin
        subviews[0].frame = frame
    }

    private func layoutAccessory(_ accessory: NSView) {
        let margin = CGFloat(4)
        var frame = accessory.frame
        frame.origin.x = closeButton.frame.minX - frame.width - margin
        let topMargin = CGFloat(2)
        let dh = max(0, closeButton.frame.height - accessory.frame.height)
        frame.origin.y = bounds.height - accessory.frame.height - topMargin + dh / 2
        accessory.frame = frame
    }
}

extension PortholeContainerView: iTermMetalDisabling {
    func viewDisablesMetal() -> Bool {
        return true
    }
}


