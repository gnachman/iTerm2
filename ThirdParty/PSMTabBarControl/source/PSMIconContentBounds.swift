//
//  PSMIconContentBounds.swift
//  iTerm2SharedARC
//
//  The part of an icon that is actually drawn. Some tab icons aren't
//  centered in their canvas (the new-output dot sits right of and below
//  center), which looks fine beside a title but not when the icon is centered
//  on a disc, as on a collapsed tab group's chip.
//

import AppKit

@objc(PSMIconContentBounds)
final class PSMIconContentBounds: NSObject {
    // Images are immutable once made, so measure each one once.
    private static let cache = NSMapTable<NSImage, NSValue>.weakToStrongObjects()

    // The bounds of the visible (not nearly transparent) pixels, in points,
    // measured from the image's top left. The whole canvas when nothing is
    // visible.
    @objc(visibleBoundsOfImage:)
    static func visibleBounds(of image: NSImage) -> NSRect {
        if let cached = cache.object(forKey: image) {
            return cached.rectValue
        }
        let result = measure(image)
        cache.setObject(NSValue(rect: result), forKey: image)
        return result
    }

    // Where to draw `image` at `size` x `size` so its visible part is centered
    // on `center`, in a flipped view.
    @objc(rectCenteringVisibleContentOfImage:atPoint:size:)
    static func rect(centeringVisibleContentOf image: NSImage,
                     at center: NSPoint,
                     size: CGFloat) -> NSRect {
        let bounds = visibleBounds(of: image)
        let scale = image.size.width > 0 ? size / image.size.width : 1
        return NSRect(x: center.x - bounds.midX * scale,
                      y: center.y - bounds.midY * scale,
                      width: size,
                      height: size)
    }

    // Draws `image` in `rect` with an outline `width` points wide that follows
    // its shape, so it stays legible on a background of a similar color.
    // Expects a flipped context, like a tab bar's.
    @objc(drawImage:inRect:outlineColor:width:)
    static func draw(_ image: NSImage, in rect: NSRect, outlineColor: NSColor, width: CGFloat) {
        let silhouette = NSImage(size: rect.size, flipped: true) { bounds in
            image.draw(in: bounds,
                       from: .zero,
                       operation: .sourceOver,
                       fraction: 1,
                       respectFlipped: true,
                       hints: nil)
            outlineColor.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        for dx in [-width, 0, width] {
            for dy in [-width, 0, width] where dx != 0 || dy != 0 {
                silhouette.draw(in: rect.offsetBy(dx: dx, dy: dy),
                                from: .zero,
                                operation: .sourceOver,
                                fraction: 1,
                                respectFlipped: true,
                                hints: nil)
            }
        }
        image.draw(in: rect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: true,
                   hints: nil)
    }

    private static func measure(_ image: NSImage) -> NSRect {
        let whole = NSRect(origin: .zero, size: image.size)
        let pixelsWide = max(1, Int(ceil(image.size.width * 2)))
        let pixelsHigh = max(1, Int(ceil(image.size.height * 2)))
        guard let context = CGContext(data: nil,
                                      width: pixelsWide,
                                      height: pixelsHigh,
                                      bitsPerComponent: 8,
                                      bytesPerRow: pixelsWide * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else {
            return whole
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // Row 0 of the buffer is the top of the image.
        let pixels = data.bindMemory(to: UInt8.self, capacity: pixelsWide * pixelsHigh * 4)
        var minX = pixelsWide, minY = pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide where pixels[(y * pixelsWide + x) * 4 + 3] > 40 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else {
            return whole
        }
        let sx = image.size.width / CGFloat(pixelsWide)
        let sy = image.size.height / CGFloat(pixelsHigh)
        return NSRect(x: CGFloat(minX) * sx,
                      y: CGFloat(minY) * sy,
                      width: CGFloat(maxX - minX + 1) * sx,
                      height: CGFloat(maxY - minY + 1) * sy)
    }
}
