//
//  JSONPrettyPrinter.swift
//  iTerm2
//
//  Created by George Nachman on 3/10/25.
//

@objc(iTermJSONPrettyPrinter)
class JSONPrettyPrinter: NSObject {
    private let result: JSONAttributedStringBuilder.Result
    private lazy var lineToBlockIDList: [Int: String] = {
        computeLineToBlockIDList()
    }()

    private static let userDefaultsKey = "NoSyncHavePromotedJSONPrettyPrint"
    private static var busy = false

    // Tell the user about the JSON pretty printing feature when they've
    // selected one that we're pretty sure is hard to read, but avoid wasting a
    // bunch of CPU on giant selections.
    @objc
    static func promoteIfJSON(string: String, callback: @escaping ()->()) {
        if string.count < 200 || string.count > 100_000 {
            return
        }
        if UserDefaults.standard.bool(forKey: userDefaultsKey) {
            return
        }
        if string.prefix(20).range(of: "^ *[\\[{]", options: [.regularExpression]) == nil {
            return
        }
        if busy {
            return
        }
        busy = true
        DispatchQueue.global().async {
            guard let data = string.data(using: .utf8) else {
                return
            }
            let maybeObject = try? JSONSerialization.jsonObject(
                with: data,
                options: [.allowFragments])
            if let maybeObject,
               let desiredNumberOfLines = JSONPrettyPrinter(maybeObject as AnyObject)?.result.attributedStrings.count {
                let actualNumberOfLines = string.ranges(of: "\n").count
                DispatchQueue.main.async {
                    busy = false
                    if desiredNumberOfLines < 10 {
                        return
                    }
                    if actualNumberOfLines > desiredNumberOfLines / 4 {
                        return
                    }
                    UserDefaults.standard.set(true, forKey: userDefaultsKey)
                    callback()
                }
            }
        }
    }

    @objc(initWithObject:)
    init?(_ obj: AnyObject) {
        let builder = JSONAttributedStringBuilder()
        guard let result = try? builder.result(from: obj) else {
            return nil
        }
        self.result = result
    }

    private func computeLineToBlockIDList() -> [Int: String] {
        struct Entry {
            var depth: Int
            var blockID: String
        }
        var mapping = [Int: Entry]()
        var counts = [Int: Int]()
        func update(folds: [JSONAttributedStringBuilder.FoldTreeNode], depth: Int) {
            for fold in folds {
                counts[depth, default: 0] += fold.lineRange.count
                for i in fold.lineRange {
                    if var existing = mapping[i] {
                        if existing.depth < depth {
                            existing.depth = depth
                            existing.blockID = existing.blockID.prepending(
                                string: fold.blockID,
                                toListDelimitedBy: iTermExternalAttributeBlockIDDelimiter)
                            mapping[i] = existing
                        } else {
                            mapping[i] = Entry(depth: depth, blockID: fold.blockID)
                        }
                    } else {
                        mapping[i] = Entry(depth: depth, blockID: fold.blockID)
                    }
                }
                update(folds: fold.children, depth: depth + 1)
            }
        }
        update(folds: result.folds, depth: 0)
        return mapping.mapValues {
            $0.blockID
        }
    }

    @objc(screenCharArraysWithMaxWidth:)
    func screenCharArrays(maxWidth: Int) -> [ScreenCharArray] {
        result.attributedStrings.enumerated().flatMap { (i, attributedString) in
            attributedString.screenCharArraysFromJSONAttributedString(
                maxWidth: maxWidth,
                blockIDList: lineToBlockIDList[i]).map {
                    $0.0
                }
        }

    }

    // Returns a map from block ID to the range of indexes into the result of
    // screenCharArrays(maxWidth:) that correspond to those blocks.
    @objc(blockMarksWithMaxWidth:)
    func blockMarks(maxWidth: Int) -> [String: iTermRange] {
        // `starts` gives the index in each `result.attributedStrings` where a wrapped line begins.
        // So if result.attributedStrings=["x", "12345"] and maxWidth is 3 then starts
        // starts would be [[0], [0,3]].
        let starts = result.attributedStrings.enumerated().map { (i, attributedString) in
            attributedString.screenCharArraysFromJSONAttributedString(
                maxWidth: maxWidth,
                blockIDList: lineToBlockIDList[i]).map {
                    $0.1
                }
        }
        // Convert a raw line number to a wrapped line number.
        func wrap(_ rawLineNumber: Int) -> Int {
            let counts = starts.map {
                $0.count
            }
            let subcounts = counts[0..<min(counts.count, rawLineNumber)]
            return subcounts.reduce(0, +)
        }

        let entries = result.folds.compactMap({ $0.flattened }).joined()
        var mappings = [String: iTermRange]()
        for entry in entries {
            let rawRange = entry.lineRange
            let lowerBound = wrap(rawRange.lowerBound)
            let upperBound = wrap(rawRange.upperBound)
            mappings[entry.blockID] = iTermRange(lowerBound..<upperBound)
        }
        return mappings
    }
}

@objc(iTermRange)
class iTermRange: NSObject {
    @objc var location: Int
    @objc var length: Int
    @objc var max: Int { location + length }
    @objc var nsrange: NSRange { NSRange(location: location, length: length) }

    override var description: String {
        if location == NSNotFound {
            return "<not found>"
        }
        if length <= 0 {
            return "<empty>"
        }
        return "[\(location), \(location + length - 1)]"
    }

    @objc(rangeWithLocation:length:)
    static func create(location: Int, length: Int) -> iTermRange {
        return iTermRange(location: location, length: length)
    }

    @objc
    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    @objc
    init(_ nsrange: NSRange) {
        location = nsrange.location
        length = nsrange.length
    }

    init(_ range: Range<Int>) {
        location = range.lowerBound
        length = range.count
    }
}

extension ScreenCharArray {
    func split(maxWidth: Int) -> [(ScreenCharArray, Int)] {
        if length < maxWidth {
            return [(self, 0)]
        }
        var sca = self
        var parts = [(ScreenCharArray, Int)]()
        var ci = 0
        while sca.length > 0 {
            var i = min(Int(sca.length), maxWidth)
            if sca.line[i - 1].code == DWC_RIGHT {
                i -= 1
            }
            let subsca = sca.subArray(to: Int32(i))
            let tuple = (subsca, ci)
            parts.append(tuple)
            sca = sca.subArray(from: subsca.length)
            ci += Int(subsca.length)
        }
        return parts
    }
}

extension NSAttributedString {
    func screenCharArraysFromJSONAttributedString(maxWidth: Int,
                                                  blockIDList: String?) -> [(ScreenCharArray, Int)] {
        if maxWidth < 2 {
            return []
        }
        let rawLine = screenCharArrayFromJSONAttributedString(blockIDList: blockIDList)
        return rawLine.split(maxWidth: maxWidth)
    }

    func screenCharArrayFromJSONAttributedString(blockIDList: String?) -> ScreenCharArray {
        var eol = screen_char_t()
        eol.code = UInt16(EOL_HARD)
        var temp = [screen_char_t()]
        let result = MutableScreenCharArray(line: &temp,
                                            length: 0,
                                            continuation: eol,
                                            date: Date(),
                                            externalAttributes: nil,
                                            rtlFound: string.mayContainRTL,
                                            bidiInfo: nil)

        enumerateJSONSubstrings { string, maybePart in
            var c = screen_char_t()
            c.backgroundColorMode = ColorModeAlternate.rawValue
            c.backgroundColor = UInt32(ALTSEM_DEFAULT)
            c.foregroundColorMode = ColorModeNormal.rawValue
            switch maybePart {
            case .punctuation, .null:
                c.foregroundColorMode = ColorModeAlternate.rawValue
                c.foregroundColor = UInt32(ALTSEM_DEFAULT)
                c.inverse = 1
            case .string:
                c.foregroundColor = UInt32(kiTermScreenCharAnsiColor.green.rawValue)
            case .number:
                c.foregroundColor = UInt32(kiTermScreenCharAnsiColor.red.rawValue)
            case .bool:
                c.foregroundColor = UInt32(kiTermScreenCharAnsiColor.yellow.rawValue)
            case .key, .none:
                c.foregroundColorMode = ColorModeAlternate.rawValue
                c.foregroundColor = UInt32(ALTSEM_DEFAULT)
            }
            result.append(string, style: c, continuation: eol)
        }
        if let blockIDList {
            let eaIndex = iTermExternalAttributeIndex()
            if let attr = iTermExternalAttribute(
                havingUnderlineColor: false,
                underlineColor: .init(red: 0, green: 0, blue: 0, mode: ColorModeAlternate),
                url: nil,
                blockIDList: blockIDList,
                controlCode: nil) {
                eaIndex.setAttributes(attr, at: 0, count: result.length)
                result.setExternalAttributesIndex(eaIndex)
            }
        }
        return result
    }

    func components(separatedBy separator: String) -> [NSAttributedString] {
        let nsString = self.string as NSString
        var components: [NSAttributedString] = []
        var start = 0

        while start < nsString.length {
            let range = nsString.range(of: separator, options: [], range: NSRange(location: start, length: nsString.length - start))
            if range.location == NSNotFound {
                let substringRange = NSRange(location: start, length: nsString.length - start)
                components.append(self.attributedSubstring(from: substringRange))
                break
            } else {
                let substringRange = NSRange(location: start, length: range.location - start)
                components.append(self.attributedSubstring(from: substringRange))
                start = range.location + range.length
            }
        }

        // If the string ends with the separator, add an empty component.
        if start == nsString.length {
            components.append(NSAttributedString(string: ""))
        }

        return components
    }

    func enumerateJSONSubstrings(_ callback: (String, JSONAttributedStringBuilder.JSONPart?) -> ()) {
        let fullRange = NSRange(location: 0, length: length)
        enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let substring = attributedSubstring(from: range).string
            let jsonPartString = attributes[JSONAttributedStringBuilder.jsonPart] as? String
            let jsonPart: JSONAttributedStringBuilder.JSONPart? = if let jsonPartString {
                JSONAttributedStringBuilder.JSONPart(rawValue: jsonPartString)
            } else {
                nil
            }
            callback(substring, jsonPart)
        }
    }
}

class JSONAttributedStringBuilder {
    enum JSONError: Error {
        case invalidObject
    }
    static let jsonPart = NSAttributedString.Key(rawValue: "iTermJSONPart")
    enum JSONPart: String {
        case punctuation
        case key
        case string
        case number
        case bool
        case null
    }
    // Define color attributes for different JSON components.
    private let punctuationAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.punctuation.rawValue]
    private let keyAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.key.rawValue]
    private let stringAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.string.rawValue]
    private let numberAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.number.rawValue]
    private let boolAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.bool.rawValue]
    private let nullAttributes: [NSAttributedString.Key: Any] = [jsonPart: JSONPart.null.rawValue]

    struct FoldTreeNode {
        var lineRange: Range<Int>
        var children = [FoldTreeNode]()
        var blockID = UUID().uuidString

        var ranges: [Range<Int>] {
            return [lineRange] + children.flatMap { $0.ranges }
        }

        var flattened: [(lineRange: Range<Int>, blockID: String)] {
            [(lineRange: lineRange, blockID: blockID)] + children.flatMap { $0.flattened }
        }
    }

    struct Result {
        var attributedStrings = [NSAttributedString]()
        private var _workingAttributedString = NSMutableAttributedString()
        var folds = [FoldTreeNode]()

        private var stack = [FoldTreeNode]()
        mutating func appendBlock(_ closure: (inout Result) throws -> ()) rethrows {
            let start = attributedStrings.count
            stack.append(FoldTreeNode(lineRange: start..<start))
            try closure(&self)
            var node = stack.removeLast()
            node.lineRange = start..<(attributedStrings.count + 1)
            if stack.isEmpty {
                folds.append(node)
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }

        mutating func append(string: String, attributes: [NSAttributedString.Key: Any], eol: Bool) {
            _workingAttributedString.append(NSAttributedString(string: string,
                                                               attributes: attributes))
            if eol {
                appendNewline()
            }
        }

        mutating func appendNewline() {
            attributedStrings.append(_workingAttributedString)
            _workingAttributedString = NSMutableAttributedString()
        }

        mutating func commit() {
            if !_workingAttributedString.string.isEmpty {
                attributedStrings.append(_workingAttributedString)
                _workingAttributedString = NSMutableAttributedString()
            }
        }
    }

    /// Generates an attributed string for the JSON representation of an object.
    /// - Parameter object: The JSON object (could be a dictionary, array, or other type).
    /// - Returns: An NSAttributedString with syntax highlighting.
    func result(from object: Any) throws -> Result {
        var result = Result()
        try append(object: object, to: &result, indentLevel: 0)
        result.commit()
        return result
    }

    // Recursive helper to build the attributed string.
    private func append(object: Any,
                        to result: inout Result,
                        indentLevel: Int) throws {
        let indent = String(repeating: "    ", count: indentLevel)

        if let dict = object as? [String: Any] {
            try result.appendBlock { result in
                result.append(string: "{", attributes: punctuationAttributes, eol: true)
                let keys = Array(dict.keys)
                for (index, key) in keys.enumerated() {
                    result.append(string: indent + "    ", attributes: punctuationAttributes, eol: false)

                    // Escape key and apply key attributes.
                    let escapedKey = escape(string: key)
                    result.append(string: "\"\(escapedKey)\"", attributes: keyAttributes, eol: false)
                    result.append(string: ": ", attributes: punctuationAttributes, eol: false)

                    // Append value.
                    if let value = dict[key] {
                        try append(object: value, to: &result, indentLevel: indentLevel + 1)
                    } else {
                        result.append(string: "null", attributes: nullAttributes, eol: false)
                    }

                    if index < keys.count - 1 {
                        result.append(string: ",", attributes: punctuationAttributes, eol: false)
                    }
                    result.appendNewline()
                }
                result.append(string: indent + "}", attributes: punctuationAttributes, eol: false)
            }
        } else if let array = object as? [Any] {
            try result.appendBlock { result in
                result.append(string: "[", attributes: punctuationAttributes, eol: true)
                for (index, item) in array.enumerated() {
                    result.append(string: indent + "    ", attributes: punctuationAttributes, eol: false)
                    try append(object: item, to: &result, indentLevel: indentLevel + 1)
                    if index < array.count - 1 {
                        result.append(string: ",", attributes: punctuationAttributes, eol: false)
                    }
                    result.appendNewline()
                }
                result.append(string: indent + "]", attributes: punctuationAttributes, eol: false)
            }
        } else if let str = object as? String {
            let escaped = escape(string: str)
            result.append(string: "\"\(escaped)\"", attributes: stringAttributes, eol: false)
        } else if let number = object as? NSNumber {
            // Distinguish between boolean and numeric values.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                let boolValue = number.boolValue
                result.append(string: boolValue ? "true" : "false", attributes: boolAttributes, eol: false)
            } else {
                result.append(string: "\(number)", attributes: numberAttributes, eol: false)
            }
        } else if object is NSNull {
            result.append(string: "null", attributes: nullAttributes, eol: false)
        } else {
            throw JSONError.invalidObject
        }
    }

    // Escapes special characters in strings for valid JSON output.
    private func escape(string: String) -> String {
        var result = ""
        for char in string {
            switch char {
            case "\"":
                result.append("\\\"")
            case "\\":
                result.append("\\\\")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            default:
                if let firstScalar = char.unicodeScalars.first,
                   CharacterSet.controlCharacters.contains(firstScalar) {
                    let value = char.unicodeScalars.first!.value
                    result.append(String(format: "\\u%04x", value))
                } else {
                    result.append(char)
                }
            }
        }
        return result
    }
}

extension String {
    func prepending(string: String, toListDelimitedBy delimiter: String) -> String {
        var parts = components(separatedBy: delimiter)
        parts.insert(string, at: 0)
        return parts.joined(separator: delimiter)
    }
    func removing(string: String, fromListDelimitedBy delimiter: String) -> String {
        var parts = components(separatedBy: delimiter)
        parts.removeAll { $0 == delimiter }
        return parts.joined(separator: delimiter)
    }
}

@objc
extension NSString {
    @objc(prependingString:toListDelimitedBy:)
    func objc_prepending(string: String, toListDelimitedBy delimiter: String) -> String {
        return (self as String).prepending(string: string, toListDelimitedBy: delimiter)
    }

    @objc(removingString:fromListDelimitedBy:)
    func objc_removing(string: String, fromListDelimitedBy delimiter: String) -> String {
        return (self as String).removing(string: string, fromListDelimitedBy: delimiter)
    }
}
