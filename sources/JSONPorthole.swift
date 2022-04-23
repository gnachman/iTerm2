//
//  JSONPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

class JSONPorthole: BaseTextViewPorthole {
    private let jsonObject: Any

    private static func attributedString(jsonObject: Any, colors: SavedColors) -> NSAttributedString {
        return NSAttributedString.fromJSONObject(jsonObject,
                                                 colors: JSONColors(textColor: colors.textColor,
                                                                    backgroundColor: colors.backgroundColor),
                                                 indent: 0)
    }

    private static func parse(_ text: String) throws -> Any {
        return try JSONSerialization.jsonObject(with: text.data(using: .utf8)!,
                                                options: [.fragmentsAllowed])
    }

    static func createIfValid(config: PortholeConfig, uuid: String? = nil) -> JSONPorthole? {
        guard let obj = try? Self.parse(config.text) else {
            return nil
        }
        return JSONPorthole(object: obj, config: config, uuid: uuid)
    }

    init(object: Any, config: PortholeConfig, uuid: String? = nil) {
        jsonObject = object
        super.init(config, uuid: uuid)
        finishInitialization()
    }

    override init(_ config: PortholeConfig,
                  uuid: String? = nil) {
        let obj: Any
        do {
            obj = try Self.parse(config.text)
        } catch {
            obj = "Error parsing JSON: \(error.localizedDescription)"
        }
        jsonObject = obj
        super.init(config,
                   uuid: uuid)
        finishInitialization()
    }

    private func finishInitialization() {
        let attributedString = Self.attributedString(jsonObject: jsonObject,
                                                     colors: savedColors)
        textStorage.setAttributedString(attributedString)
    }

    private static let jsonDictionaryKey = "json"

    static func from(_ dictionary: [String: AnyObject],
                     colorMap: iTermColorMap) -> JSONPorthole? {
        guard let uuid = dictionary[Self.uuidDictionaryKey] as? String,
              let json = dictionary[Self.jsonDictionaryKey] as? String else {
            return nil
        }
        return JSONPorthole(PortholeConfig(text: json, colorMap: colorMap),
                            uuid: uuid)
    }

    override var dictionaryValue: [String: AnyObject] {
        var result = super.dictionaryValue
        result[Self.jsonDictionaryKey] = config.text as NSString
        return result
    }

    override func updateColors() {
        super.updateColors()
        textView.textStorage?.setAttributedString(Self.attributedString(jsonObject: jsonObject,
                                                                        colors: savedColors))
    }

}

fileprivate struct JSONColors {
    let textColor: NSColor
    let backgroundColor: NSColor
}

fileprivate extension NSAttributedString {
    static func fromJSONObject(_ object: Any,
                               colors: JSONColors,
                               indent: Int) -> NSAttributedString {
        if let dict = object as? NSDictionary {
            return fromJSONDictionary(dict, colors: colors, indent: indent)
        } else if let array = object as? NSArray {
            return fromJSONArray(array, colors: colors, indent: indent)
        } else if let string = object as? NSString {
            return fromJSONString(string, colors: colors, indent: indent)
        } else if let number = object as? NSNumber {
            return fromJSONNumber(number, colors: colors, indent: indent)
        } else if object as? NSNull != nil {
            return fromJSONNull(colors, indent: indent)
        } else {
            return NSAttributedString()
        }
    }

    private static func fromJSONDictionary(_ dict: NSDictionary,
                                           colors: JSONColors,
                                           indent: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("{", colors: colors))
        var first = true
        for (key, value) in dict {
            if !first {
                result.append(fromJSONSyntaxString(",", colors: colors))
            }
            first = false
            result.append(jsonNewline())
            result.append(fromJSONindent(indent + 1))
            result.append(fromJSONObject(key, colors: colors, indent: indent + 1))
            result.append(fromJSONSyntaxString(": ", colors: colors))
            result.append(fromJSONObject(value, colors: colors, indent: indent + 1))
        }
        result.append(jsonNewline())
        result.append(fromJSONindent(indent))
        result.append(fromJSONSyntaxString("}", colors: colors))
        return result
    }

    private static func fromJSONArray(_ array: NSArray, colors: JSONColors, indent: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("[", colors: colors))
        var first = true
        for element in array {
            if !first {
                result.append(fromJSONSyntaxString(",", colors: colors))
            }
            first = false
            result.append(jsonNewline())
            result.append(fromJSONindent(indent + 1))
            result.append(fromJSONObject(element, colors: colors, indent: indent + 1))
        }
        result.append(jsonNewline())
        result.append(fromJSONindent(indent))
        result.append(fromJSONSyntaxString("]", colors: colors))
        return result
    }

    private static func fromJSONString(_ string: NSString, colors: JSONColors, indent: Int) -> NSAttributedString {
        let color: NSColor
        if colors.backgroundColor.isDark {
            color = NSColor(srgbRed: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.2, green: 0.7, blue: 0.2, alpha: 1.0)
        }
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("\"", colors: colors))
        result.append(NSAttributedString(string: string as String,
                                         attributes: jsonAttributes(color: color)))
        result.append(fromJSONSyntaxString("\"", colors: colors))
        return result
    }

    private static func fromJSONNumber(_ number: NSNumber, colors: JSONColors, indent: Int) -> NSAttributedString {
        let color: NSColor
        if colors.backgroundColor.isDark {
            color = NSColor(srgbRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.7, green: 0.2, blue: 0.2, alpha: 1.0)
        }
        return NSAttributedString(string: number.stringValue, attributes: jsonAttributes(color: color))
    }

    private static func fromJSONNull(_ colors: JSONColors, indent: Int) -> NSAttributedString {
        let color = NSColor.init(white: 0.5, alpha: 1)
        return NSAttributedString(string: "null", attributes: jsonAttributes(color: color))

    }

    private static func jsonNewline() -> NSAttributedString {
        return NSAttributedString(string: "\n", attributes: basicJSONAttributes)
    }

    private static var basicJSONAttributes: [NSAttributedString.Key: Any] {
        return [.font: NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize)!]
    }

    private static func jsonAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        return basicJSONAttributes.merging([.foregroundColor: color]) { _, _ in fatalError() }
    }
    
    private static func fromJSONindent(_ indent: Int) -> NSAttributedString {
        return NSAttributedString(string: String(repeating: " ", count: indent * 4),
                                  attributes: basicJSONAttributes)
    }

    private static func fromJSONSyntaxString(_ string: String, colors: JSONColors) -> NSAttributedString {
        return NSAttributedString(string: string,
                                  attributes: jsonAttributes(color: colors.textColor.withAlphaComponent(0.75)))
    }
}
