//
//  SFSymbolsHelpers.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/25/24.
//

import AppKit

@objc(iTermTintedImage)
class TintedImage: NSObject {
    private(set) var original: NSImage
    private var size: NSSize?
    private var color: NSColor?
    private var cached: NSImage?

    @objc(initWithImage:)
    init(original: NSImage) {
        self.original = original
    }

    required init(_ original: TintedImage) {
        self.original = original.original
        self.size = original.size
        self.color = original.color
        self.cached = original.cached
    }

    @objc(imageTintedWithColor:size:)
    func tintedImage(color: NSColor, size: NSSize) -> NSImage {
        if let cached, color == self.color, size == self.size {
            return cached
        }
        let tinted = original.it_image(withTintColor: color, size: size)!
        self.size = size
        self.color = color
        cached = tinted
        return tinted
    }

    func clone() -> Self {
        return Self(self)
    }
}

@objc(iTermCompositeImageBuilder)
class CompositeImageBuilder: NSObject {
    private var images = [NSImage]()
    private let size: NSSize

    @objc(initWithSize:)
    init(size: NSSize) {
        self.size = size
        super.init()
    }

    @objc(addImage:)
    func add(image: NSImage) {
        images.append(image)
    }

    @objc
    var image: NSImage {
        let size = self.size
        let images = self.images
        let composite = NSImage(size: size, flipped: false) { _ in
            for image in images {
                image.it_draw(in: NSRect(x: (size.width - image.size.width) / 2,
                                         y: (size.height - image.size.height) / 2,
                                         width: image.size.width,
                                         height: image.size.height),
                              virtualOffset: 0)
            }
            return true
        }
        return composite
    }
}
