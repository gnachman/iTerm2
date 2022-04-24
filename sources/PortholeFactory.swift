//
//  PortholeFactory.swift
//  iTerm2
//
//  Created by George Nachman on 4/22/22.
//

import Foundation
import CoreText

@objc(iTermPortholeFactory)
class PortholeFactory: NSObject {
    static func markdownPorthole(config: PortholeConfig) -> Porthole {
        return TextViewPorthole(config, renderer: MarkdownPortholeRenderer(config.text))
    }

    static func jsonPorthole(config: PortholeConfig) -> Porthole? {
        guard let renderer = JSONPortholeRenderer(config.text) else {
            return nil
        }
        return TextViewPorthole(config, renderer: renderer)
    }
    
    @objc
    static func porthole(_ dictionary: [String: AnyObject],
                         colorMap: iTermColorMap,
                         font: NSFont) -> ObjCPorthole? {
        guard let (type, info) = PortholeType.unwrap(dictionary: dictionary) else {
            return nil
        }
        switch type {
        case .text:
            guard let (config, rendererName, _) = TextViewPorthole.config(fromDictionary: info,
                                                                          colorMap: colorMap,
                                                                          font: font) else {
                return nil
            }
            guard let renderer = textRenderer(rendererName, text: config.text) else {
                return nil
            }
            return TextViewPorthole(config, renderer: renderer)
        }
    }

    private static func textRenderer(_ rendererName: String, text: String) -> TextViewPortholeRenderer? {
        if rendererName == MarkdownPortholeRenderer.identifier {
            return MarkdownPortholeRenderer(text)
        }
        if rendererName == JSONPortholeRenderer.identifier {
            return JSONPortholeRenderer(text)
        }
        return nil
    }
}

