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
    static func textViewPorthole(config: PortholeConfig) -> Porthole {
        let porthole = TextViewPorthole(config,
                                        renderer: textViewPortholeRenderer(config: config))
        PortholeRegistry.instance.add(porthole)
        return porthole
    }

    private static func textViewPortholeRenderer(config: PortholeConfig) -> TextViewPortholeRenderer {
        return TextViewPortholeRenderer(config.text,
                                        type: config.type,
                                        filename: config.filename)
    }

    @objc
    static func porthole(_ dictionary: [String: AnyObject],
                         colorMap: iTermColorMapReading,
                         useSelectedTextColor: Bool,
                         font: NSFont) -> ObjCPorthole? {
        guard let (type, info) = PortholeType.unwrap(dictionary: dictionary) else {
            return nil
        }
        switch type {
        case .text:
            guard let (config, uuid, savedLines, language, languages) = TextViewPorthole.config(
                fromDictionary: info,
                colorMap: colorMap,
                useSelectedTextColor: useSelectedTextColor,
                font: font) else {
                return nil
            }
            let renderer = TextViewPortholeRenderer(config.text,
                                                    language: language,
                                                    languages: languages)
            return TextViewPorthole(config,
                                    renderer: renderer,
                                    uuid: uuid,
                                    savedLines: savedLines)
        }
    }
}

