//
//  PortholeFactory.swift
//  iTerm2
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

@objc(iTermPortholeFactory)
class PortholeFactory: NSObject {
    @objc
    static func markdownPorthole(markdown: String,
                                 colorMap: iTermColorMap,
                                 baseDirectory: URL?) -> ObjCPorthole? {
        if #available(macOS 12, *) {
            return MarkdownPorthole(markdown, colorMap: colorMap, baseDirectory: baseDirectory)
        } else {
            return nil
        }
    }

    @objc
    static func porthole(_ dictionary: [String: AnyObject],
                         colorMap: iTermColorMap) -> ObjCPorthole? {
        guard let (type, info) = PortholeType.unwrap(dictionary: dictionary) else {
            return nil
        }
        switch type {
        case .markdown:
            if #available(macOS 12, *) {
                return MarkdownPorthole.from(info, colorMap: colorMap)
            } else {
                return nil
            }
        }
    }
}

