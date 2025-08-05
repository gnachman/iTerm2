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
