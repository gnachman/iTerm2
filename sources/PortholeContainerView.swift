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
    var wideCallback: (() -> ())? = nil
    let closeButton = SaneButton()
    let wideButton: SaneButton
    var scrollView: NestableScrollView? = nil
    var wideMode: Bool {
        return wideButton.state == .on
    }
    var scrollViewOverhead: CGFloat {
        guard let scrollView = scrollView else {
            return 0
        }
        let k = CGFloat(100)
        return NestableScrollView.frameSize(forContentSize: NSMakeSize(k, k),
                                            horizontalScrollerClass: NSScroller.self,
                                            verticalScrollerClass: nil,
                                            borderType: scrollView.borderType,
                                            controlSize: .regular,
                                            scrollerStyle: scrollView.scrollerStyle).height - k + closeButton.frame.height + 2 * Self.margin
    }
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
        wideButton = SaneButton(checkboxWithTitle: "Wide", target: nil, action: #selector(toggleWide(_:)))

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

        wideButton.controlSize = .mini
        wideButton.sizeToFit()
        wideButton.target = self
        wideButton.autoresizingMask = []
        addSubview(wideButton)

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

    @objc func toggleWide(_ sender: AnyObject?) {
        if let scrollView = scrollView,
           let documentView = scrollView.documentView {
            documentView.removeFromSuperview()
            insertSubview(documentView, at: 0)
            scrollView.removeFromSuperview()
            self.scrollView = nil
        } else if scrollView == nil {
            guard let child = subviews.first else {
                return
            }
            child.removeFromSuperview()

            let scrollView = NestableScrollView(frame: child.frame)
            self.scrollView = scrollView
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = true
            scrollView.documentView = child
            scrollView.drawsBackground = false
            insertSubview(scrollView, at: 0)
        }
        wideCallback?()
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
        layoutWideButton()
        layoutChild()
        return ok
    }

    private func layoutWideButton() {
        let margin = 2.0
        var frame = accessory?.frame ?? closeButton.frame
        frame.origin.y = frame.minY + round((frame.height - wideButton.frame.height) / 2.0)
        frame.size = wideButton.frame.size
        frame.origin.x -= frame.width + margin
        wideButton.frame = frame
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
        if wideMode {
            frame.size.height -= closeButton.frame.height + 2 * Self.margin
        }
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


// https://stackoverflow.com/questions/8623785/nsscrollview-inside-another-nsscrollview
// 😘 AppKit
class NestableScrollView: NSScrollView {
    private var scrollingHoriontally = false

    override func scrollWheel(with event: NSEvent) {
        if event.phase == [.mayBegin] {
            super.scrollWheel(with: event)
            nextResponder?.scrollWheel(with: event)
            return
        }
        if event.phase == [.began] || event.phase == [] && event.momentumPhase == [] {
            scrollingHoriontally = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        if scrollingHoriontally {
            super.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }
}
