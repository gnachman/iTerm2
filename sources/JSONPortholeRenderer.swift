//
//  JSONPortholeRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/22/22.
//

import Foundation

class JSONPortholeRenderer {
    private let jsonObject: Any

    static func wants(_ text: String) -> Bool {
        return (try? parse(text)) != nil
    }

    func render(visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return Self.attributedString(jsonObject: jsonObject, visualAttributes: visualAttributes)
    }

    private static func attributedString(
        jsonObject: Any,
        visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return NSAttributedString.fromJSONObject(jsonObject,
                                                 visualAttributes: visualAttributes,
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

fileprivate extension NSAttributedString {
    static func fromJSONObject(_ object: Any,
                               visualAttributes: TextViewPorthole.VisualAttributes,
                               indent: Int) -> NSAttributedString {
        if let dict = object as? NSDictionary {
            return fromJSONDictionary(dict, visualAttributes: visualAttributes, indent: indent)
        } else if let array = object as? NSArray {
            return fromJSONArray(array, visualAttributes: visualAttributes, indent: indent)
        } else if let string = object as? NSString {
            return fromJSONString(string, visualAttributes: visualAttributes, indent: indent)
        } else if let number = object as? NSNumber {
            return fromJSONNumber(number, visualAttributes: visualAttributes, indent: indent)
        } else if object as? NSNull != nil {
            return fromJSONNull(visualAttributes, indent: indent)
        } else if let error = object as? Error {
            return fromJSONError(error, visualAttributes: visualAttributes, indent: indent)
        } else {
            return NSAttributedString()
        }
    }

    private static func fromJSONDictionary(_ dict: NSDictionary,
                                           visualAttributes: TextViewPorthole.VisualAttributes,
                                           indent: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("{", visualAttributes: visualAttributes))
        var first = true
        for (key, value) in dict {
            if !first {
                result.append(fromJSONSyntaxString(",", visualAttributes: visualAttributes))
            }
            first = false
            result.append(jsonNewline(visualAttributes: visualAttributes))
            result.append(fromJSONindent(indent + 1, visualAttributes: visualAttributes))
            result.append(fromJSONObject(key,
                                         visualAttributes: visualAttributes,
                                         indent: indent + 1))
            result.append(fromJSONSyntaxString(": ", visualAttributes: visualAttributes))
            result.append(fromJSONObject(value,
                                         visualAttributes: visualAttributes,
                                         indent: indent + 1))
        }
        result.append(jsonNewline(visualAttributes: visualAttributes))
        result.append(fromJSONindent(indent, visualAttributes: visualAttributes))
        result.append(fromJSONSyntaxString("}", visualAttributes: visualAttributes))
        return result
    }

    private static func fromJSONArray(_ array: NSArray,
                                      visualAttributes: TextViewPorthole.VisualAttributes,
                                      indent: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("[", visualAttributes: visualAttributes))
        var first = true
        for element in array {
            if !first {
                result.append(fromJSONSyntaxString(",", visualAttributes: visualAttributes))
            }
            first = false
            result.append(jsonNewline(visualAttributes: visualAttributes))
            result.append(fromJSONindent(indent + 1, visualAttributes: visualAttributes))
            result.append(fromJSONObject(element,
                                         visualAttributes: visualAttributes,
                                         indent: indent + 1))
        }
        result.append(jsonNewline(visualAttributes: visualAttributes))
        result.append(fromJSONindent(indent, visualAttributes: visualAttributes))
        result.append(fromJSONSyntaxString("]", visualAttributes: visualAttributes))
        return result
    }

    private static func fromJSONString(_ string: NSString,
                                       visualAttributes: TextViewPorthole.VisualAttributes,
                                       indent: Int) -> NSAttributedString {
        let color: NSColor
        if visualAttributes.backgroundColor.isDark {
            color = NSColor(srgbRed: 0.4, green: 1.0, blue: 0.4, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.2, green: 0.7, blue: 0.2, alpha: 1.0)
        }
        let result = NSMutableAttributedString()
        result.append(fromJSONSyntaxString("\"", visualAttributes: visualAttributes))
        result.append(NSAttributedString(
            string: string as String,
            attributes: jsonAttributes(visualAttributes: visualAttributes,
                                       color: color)))
        result.append(fromJSONSyntaxString("\"", visualAttributes: visualAttributes))
        return result
    }

    private static func fromJSONNumber(_ number: NSNumber,
                                       visualAttributes: TextViewPorthole.VisualAttributes,
                                       indent: Int) -> NSAttributedString {
        let color: NSColor
        if visualAttributes.backgroundColor.isDark {
            color = NSColor(srgbRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.7, green: 0.2, blue: 0.2, alpha: 1.0)
        }
        return NSAttributedString(string: number.stringValue,
                                  attributes: jsonAttributes(visualAttributes: visualAttributes,
                                                             color: color))
    }

    private static func fromJSONError(_ error: Error,
                                      visualAttributes: TextViewPorthole.VisualAttributes,
                                      indent: Int) -> NSAttributedString {
        let color: NSColor
        if visualAttributes.backgroundColor.isDark {
            color = NSColor(srgbRed: 1.0, green: 0, blue: 0, alpha: 1.0)
        } else {
            color = NSColor(srgbRed: 0.7, green: 0, blue: 0, alpha: 1.0)
        }
        var message = error.localizedDescription
        if let debugDescription = (error as NSError).userInfo["NSDebugDescription"] as? String {
            message += "\n"
            message += debugDescription
        }
        return NSAttributedString(string: message,
                                  attributes: jsonAttributes(visualAttributes: visualAttributes,
                                                             color: color))
    }

    private static func fromJSONNull(_ visualAttributes: TextViewPorthole.VisualAttributes,
                                     indent: Int) -> NSAttributedString {
        let color = NSColor.init(white: 0.5, alpha: 1)
        return NSAttributedString(string: "null",
                                  attributes: jsonAttributes(visualAttributes: visualAttributes,
                                                             color: color))

    }

    private static func jsonNewline(
        visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
        return NSAttributedString(string: "\n",
                                  attributes: basicJSONAttributes(visualAttributes))
    }

    private static func basicJSONAttributes(
        _ visualAttributes: TextViewPorthole.VisualAttributes) -> [NSAttributedString.Key: Any] {
        return [.font: visualAttributes.font]
    }

    private static func jsonAttributes(visualAttributes: TextViewPorthole.VisualAttributes,
                                       color: NSColor) -> [NSAttributedString.Key: Any] {
        return basicJSONAttributes(
            visualAttributes).merging([.foregroundColor: color]) { _, _ in fatalError() }
    }
    
    private static func fromJSONindent(
        _ indent: Int,
        visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
            return NSAttributedString(string: String(repeating: " ", count: indent * 4),
                                      attributes: basicJSONAttributes(visualAttributes))
    }

    private static func fromJSONSyntaxString(
        _ string: String,
        visualAttributes: TextViewPorthole.VisualAttributes) -> NSAttributedString {
            return NSAttributedString(string: string,
                                      attributes: jsonAttributes(
                                        visualAttributes: visualAttributes,
                                        color: visualAttributes.textColor.withAlphaComponent(0.75)))
    }
}
