//
//  NSImage+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

import UniformTypeIdentifiers

extension NSImage {
    static func iconImage(filename: String, size: NSSize) -> NSImage {
        guard let uttype = UTType(filenameExtension: (filename as NSString).pathExtension) else {
            return NSWorkspace.shared.icon(for: UTType.utf8PlainText)
        }
        let icon = NSWorkspace.shared.icon(for: uttype)
        icon.size = size
        return icon
    }
}

extension SFSymbol {
    var nsimage: NSImage {
        NSImage(systemSymbolName: rawValue, accessibilityDescription: rawValue)!
    }
}

extension NSImage {
    func color(at point: CGPoint) -> NSColor? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Clamp point inside the image
        let x = min(max(Int(point.x), 0), width - 1)
        let y = min(max(Int(point.y), 0), height - 1)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]
        
        guard let context = CGContext(data: &pixel,
                                      width: 1,
                                      height: 1,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        
        // Note Core Graphics origin is bottom-left, so flip Y
        context.draw(cgImage,
                     in: CGRect(x: -x, y: -(height - 1 - y), width: width, height: height))
        
        return NSColor(calibratedRed: CGFloat(pixel[0]) / 255.0,
                       green: CGFloat(pixel[1]) / 255.0,
                       blue: CGFloat(pixel[2]) / 255.0,
                       alpha: CGFloat(pixel[3]) / 255.0)
    }
}
