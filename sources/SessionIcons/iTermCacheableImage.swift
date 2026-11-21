//
//  iTermCacheableImage.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/18.
//

import AppKit

// A one-entry cache of an image loaded from a file, scaled to a size and
// optionally flipped. A session uses one for its custom tab icon.
@objc(iTermCacheableImage)
class iTermCacheableImage: NSObject {
    private var path: NSString?
    private var image: NSImage?
    private var size = NSSize.zero
    private var flipped = false

    @objc(imageAtPath:ofSize:flipped:)
    func image(atPath path: String?, of size: NSSize, flipped: Bool) -> NSImage? {
        it_betaAssert(Thread.isMainThread, "iTermCacheableImage is used on the main thread only")
        let key = path.map { $0 as NSString }
        // -isEqual: with an NSString argument is -isEqualToString:, which
        // compares UTF-16 units: precomposed and decomposed spellings differ.
        if let image,
           let key,
           let cached = self.path,
           key.isEqual(cached),
           NSEqualSizes(size, self.size),
           flipped == self.flipped {
            return image
        }

        self.path = key?.copy() as? NSString
        self.size = size
        self.flipped = flipped

        // AppKit declares the path of -initWithContentsOfFile: nonnull. It
        // returns nil for nil, so skipping the call for a nil path gives the
        // same result.
        image = path.flatMap { NSImage(contentsOfFile: $0) }
        if flipped {
            image = image?.it_verticallyFlipped()
        }
        if !NSEqualSizes(size, image?.size ?? .zero) {
            image = image?.it_image(of: size)
        }
        return image
    }
}
