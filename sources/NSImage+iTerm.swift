//
//  NSImage+iTerm.swift
//  iTerm2
//
//  Created by George Nachman on 6/3/25.
//

extension NSImage {
    static func iconImage(filename: String, size: NSSize) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFileType: NSHFSTypeOfFile(filename) ?? "")
        icon.size = size
        return icon
    }
}
