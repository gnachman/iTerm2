//
//  HTMLEncoding.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/27/21.
//

import Foundation

extension NSData {
    @objc(htmlDataWithForeground:background:colorMap:useCustomBoldColor:brightenBold:)
    func htmlData(foreground: screen_char_t,
                  background: screen_char_t,
                  colorMap: iTermColorMapReading,
                  useCustomBoldColor: Bool,
                  brightenBold: Bool) -> Data {
        let encoder = HTMLEncoder(colorMap: colorMap)
        let config = HTMLEncoder.Configuration(useCustomBoldColor: useCustomBoldColor, brightenBold: brightenBold)
        return encoder.encode(self as Data,
                              foreground: foreground,
                              background: background,
                              configuration: config)
    }

    @objc
    static func styleSheet(fontFamily: String,
                           fontSize: CGFloat,
                           backgroundColor: NSColor,
                           textColor: NSColor) -> Data {
        var props = ["font-family": fontFamily,
                     "font-size": "\(fontSize)pt"]
        if let color = HTMLEncoder.formattedColor(backgroundColor) {
            props["background-color"] = color
        }
        if let color = HTMLEncoder.formattedColor(textColor) {
            props["color"] = color
        }
        let style = props.map { $0.key + ":" + $0.value }.joined(separator: ";")
        return ("<style>body { " + style + "}</style>").data(using: .utf8)!
    }

    @objc(inlineHTMLData)
    var inlineHTMLData: Data {
        let base64 = base64EncodedString()
        return "<img src=\"data:image/png;base64, \(base64)\"/>".data(using: .utf8)!
    }
}

class HTMLEncoder {
    struct Configuration {
        let useCustomBoldColor: Bool
        let brightenBold: Bool
    }

    private let colorMap: iTermColorMapReading

    init(colorMap: iTermColorMapReading) {
        self.colorMap = colorMap
    }

    func encode(_ data: Data,
                foreground: screen_char_t,
                background: screen_char_t,
                configuration: Configuration) -> Data {
        guard foreground.image == 0 else {
            return Data()
        }
        var stack: [(tag: String?, attributes: String?, text: Data?)] = []
        let styleProperties = styleProperties(foreground: foreground, background: background, configuration: configuration)
        let attrs = ["title": timestamp, "style": styleProperties].compactMapValues { $0 }
        if !attrs.isEmpty {
            let formattedAttributes = attrs.map { "\($0.key)='\($0.value)'" }.joined(separator: " ")
            stack.append((tag: "span", attributes: formattedAttributes, text: nil))
        }
        if foreground.bold != 0 {
            stack.append((tag: "b", attributes: nil, text: nil))
        }
        if foreground.italic != 0 {
            stack.append((tag: "i", attributes: nil, text: nil))
        }
        if foreground.underline != 0 {
            stack.append((tag: "u", attributes: nil, text: nil))
        }
        if foreground.strikethrough != 0 {
            stack.append((tag: "strike", attributes: nil, text: nil))
        }
        stack.append((tag: nil, attributes: nil, text: data))
        var result = Data()
        for elt in stack {
            if let tag = elt.tag {
                result.append(("<" + tag).data(using: .utf8)!)
            }
            if let attributes = elt.attributes {
                result.append((" " + attributes).data(using: .utf8)!)
            }
            if elt.tag != nil {
                result.append(">".data(using: .utf8)!)
            }
            if let text = elt.text {
                result.append(text)
            }
        }
        for elt in stack.reversed() {
            if let tag = elt.tag {
                result.append(("</" + tag + ">").data(using: .utf8)!)
            }
        }
        return result
    }

    private static var dateFormatter: DateFormatter = { () -> DateFormatter in
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "yyyy-MM-dd hh.mm.ss.SSS", options: 0, locale: Locale.current)
        return f
    }()

    private var timestamp: String {
        return Self.dateFormatter.string(from: Date())
    }

    private func styleProperties(foreground: screen_char_t,
                            background: screen_char_t,
                            configuration: Configuration) -> String? {
        let fgKey = colorMap.key(forColor: Int32(foreground.foregroundColor),
                                 green: Int32(foreground.fgGreen),
                                 blue: Int32(foreground.fgBlue),
                                 colorMode: ColorMode(rawValue: foreground.foregroundColorMode),
                                 bold: foreground.bold != 0,
                                 isBackground: false,
                                 useCustomBoldColor: configuration.useCustomBoldColor,
                                 brightenBold: configuration.brightenBold)
        var fgcolor = fgKey == kColorMapForeground ? nil : colorMap.color(forKey: fgKey)!
        if foreground.faint != 0 {
            fgcolor = fgcolor?.withAlphaComponent(0.5)
        }

        let bgKey = colorMap.key(forColor: Int32(background.backgroundColor),
                                 green: Int32(background.bgGreen),
                                 blue: Int32(background.bgBlue),
                                 colorMode: ColorMode(rawValue: background.backgroundColorMode),
                                 bold: foreground.bold != 0,
                                 isBackground: true,
                                 useCustomBoldColor: configuration.useCustomBoldColor,
                                 brightenBold: configuration.brightenBold)
        let bgcolor = bgKey == kColorMapBackground ? nil : colorMap.color(forKey: bgKey)!

        var style = [String: String]()
        if let fgcolor = fgcolor {
            style["color"] = Self.formattedColor(fgcolor)
        }
        if let bgcolor = bgcolor {
            style["background-color"] = Self.formattedColor(bgcolor)
        }
        if foreground.underline != 0 {
            switch foreground.underlineStyle {
            case .curly:
                style["text-decoration-style"] = "wavy"
            case .single:
                break
            case .double:
                style["text-decoration-style"] = "double"
            @unknown default:
                break
            }
        }

        if style.isEmpty {
            return nil
        }

        return style.map { tuple in
            let (key, value) = tuple
            return key + ":" + value
        }.joined(separator: ";")
    }

    fileprivate static func formattedColor(_ color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            return nil
        }
        let clamp = { (value: Double) -> Double in
            if value < 0 {
                return 0
            }
            if value > 1 {
                return 1
            }
            return value
        }
        let hex = { (value: CGFloat) -> String in
            let safe = clamp(Double(value))
            let i = round(safe * 255.0)
            let s = String(format: "%0.2X", Int(i))
            return s
        }
        return "#" + hex(srgb.redComponent) + hex(srgb.greenComponent) + hex(srgb.blueComponent) + hex(srgb.alphaComponent)
    }
}
