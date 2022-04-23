//
//  PortholeFactory.swift
//  iTerm2
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

@objc(iTermPortholeFactory)
class PortholeFactory: NSObject {
    static func markdownPorthole(config: PortholeConfig) -> Porthole {
        return MarkdownPorthole(config)
    }

    static func jsonPorthole(config: PortholeConfig) -> Porthole? {
        return JSONPorthole.createIfValid(config: config)
    }
    
    @objc
    static func porthole(_ dictionary: [String: AnyObject],
                         colorMap: iTermColorMap) -> ObjCPorthole? {
        guard let (type, info) = PortholeType.unwrap(dictionary: dictionary) else {
            return nil
        }
        switch type {
        case .markdown:
            return MarkdownPorthole.from(info, colorMap: colorMap)
        case .json:
            return JSONPorthole.from(info, colorMap: colorMap)
        }
    }
}

