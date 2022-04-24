//
//  JSONPorthole.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

class JSONPortholeRenderer: TextViewPortholeRenderer {
    static let identifier = "JSON"
    var identifier: String { return Self.identifier }
    private let jsonObject: Any

    func render(colors: TextViewPorthole.SavedColors) -> NSAttributedString {
        return Self.attributedString(jsonObject: jsonObject, colors: colors)
    }

    private static func attributedString(jsonObject: Any, colors: TextViewPorthole.SavedColors) -> NSAttributedString {
        return NSAttributedString.fromJSONObject(jsonObject,
                                                 colors: JSONColors(textColor: colors.textColor,
                                                                    backgroundColor: colors.backgroundColor),
                                                 indent: 0)
    }

    private static func parse(_ text: String) throws -> Any {
        return try JSONSerialization.jsonObject(with: text.data(using: .utf8)!,
                                                options: [.fragmentsAllowed])
    }

    static func createIfValid(text: String) -> JSONPortholeRenderer? {
        guard let obj = try? Self.parse(text) else {
            return nil
        }
        return JSONPortholeRenderer(object: obj)
    }

    static func forced(_ text: String) -> JSONPortholeRenderer {
        do {
            let obj = try parse(text)
            return JSONPortholeRenderer(object: obj)
        } catch {
            return JSONPortholeRenderer(object: error)
        }
    }

    init(object: Any) {
        jsonObject = object
    }

    init?(_ text: String) {
        do {
            jsonObject = try Self.parse(text)
        } catch {
            return nil
        }
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
        } else if let error = object as? Error {
            return fromJSONError(error, colors: colors, indent: indent)
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

    private static func fromJSONError(_ error: Error, colors: JSONColors, indent: Int) -> NSAttributedString {
        let color: NSColor
        if colors.backgroundColor.isDark {
            color = NSColor(srgbRed: 1.0, green: 0, blue: 0, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.7, green: 0, blue: 0, alpha: 1.0)
        }
        return NSAttributedString(string: error.localizedDescription,
                                  attributes: jsonAttributes(color: color))
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
