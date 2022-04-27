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
    static func highlightrPorthole(config: PortholeConfig) -> Porthole {
        return TextViewPorthole(config,
                                renderer: textViewPortholeRenderer(config: config))
    }

    private static func textViewPortholeRenderer(config: PortholeConfig) -> TextViewPortholeRenderer {
        return TextViewPortholeRenderer(config.text,
                                        type: config.type,
                                        filename: config.filename)
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
            guard let (config, _) = TextViewPorthole.config(fromDictionary: info,
                                                            colorMap: colorMap,
                                                            font: font) else {
                return nil
            }
            return TextViewPorthole(config,
                                    renderer: textViewPortholeRenderer(config: config))
        }
    }
}

