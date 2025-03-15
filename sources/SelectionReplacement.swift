//
//  SelectionReplacement.swift
//  iTerm2
//
//  Created by George Nachman on 3/14/25.
//

@objc(iTermSelectionReplacement)
class SelectionReplacement: NSObject {
    @objc(iTermSelectionReplacementKind)
    enum Kind: Int, CaseIterable {
    case json
    case base64Decode
    case base64Encode
    }

    @objc(iTermSelectionReplacementPayload)
    class Payload: NSObject {
        private enum Value {
        case json(AnyObject)
        case base64Decode(String)
        case base64Encode(String)
        }
        private let value: Value
        private let range: VT100GridAbsCoordRange
        @objc var kind: Kind {
            switch value {
            case .json: .json
            case .base64Decode: .base64Decode
            case .base64Encode: .base64Encode
            }
        }
        init?(json string: String, range: VT100GridAbsCoordRange) {
            guard let data = string.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                return nil
            }
            guard obj is [Any] || obj is [String: Any] else {
                return nil
            }
            self.value = .json(obj as AnyObject)
            self.range = range
        }
        init?(base64DecodableString string: String, range: VT100GridAbsCoordRange) {
            guard let data = (Data(base64Encoded: string, options: [.ignoreUnknownCharacters]) ?? Data.urlSafeBase64EncodedString(string)) else {
                return nil
            }
            guard let decodedString = String(data: data, encoding: .utf8) else {
                return nil
            }
            guard decodedString.rangeOfCharacter(from: CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\n")).union(CharacterSet.illegalCharacters)) == nil else {
                return nil
            }
            self.value = .base64Decode(decodedString)
            self.range = range
        }
        init?(base64EncodableString string: String, range: VT100GridAbsCoordRange) {
            guard !string.isEmpty else {
                return nil
            }
            self.value = .base64Encode(Data(string.utf8).base64EncodedString(options: [.lineLength64Characters]))
            self.range = range
        }

        @objc(executeWithWidth:completion:)
        func execute(width: Int32, completion: (VT100GridAbsCoordRange, [ScreenCharArray], [String: iTermRange]) -> ()) {
            if let executor {
                let result = executor.execute(maxWidth: Int(width))
                completion(range, result.lines, result.blocks)
            }
        }

        struct Result {
            var lines: [ScreenCharArray]
            var blocks: [String: iTermRange]
        }
        protocol SelectionReplacementExecutor {
            func execute(maxWidth: Int) -> Result
        }
        private var executor: SelectionReplacementExecutor? {
            switch value {
            case .json(let obj): JSONPrettyPrinterExecutor(obj)
            case .base64Decode(let string), .base64Encode(let string): Base64Executor(string)
            }
        }

        private struct JSONPrettyPrinterExecutor: SelectionReplacementExecutor {
            var obj: AnyObject
            let printer: JSONPrettyPrinter

            init?(_ obj: AnyObject) {
                guard let printer = JSONPrettyPrinter(obj) else {
                    return nil
                }
                self.obj = obj
                self.printer = printer
            }
            func execute(maxWidth width: Int) -> Result {
                return Result(lines: printer.screenCharArrays(maxWidth: width),
                              blocks: printer.blockMarks(maxWidth: width))
            }
        }

        private struct Base64Executor: SelectionReplacementExecutor {
            var transformed: String

            init?(_ string: String) {
                self.transformed = string
            }

            func execute(maxWidth width: Int) -> Result {
                var result = [ScreenCharArray]()
                for line in transformed.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
                    let sca = MutableScreenCharArray()
                    sca.eol = EOL_HARD
                    var c = screen_char_t()
                    c.backgroundColorMode = ColorModeAlternate.rawValue
                    c.backgroundColor = UInt32(ALTSEM_DEFAULT)
                    c.foregroundColorMode = ColorModeAlternate.rawValue
                    c.foregroundColor = UInt32(ALTSEM_DEFAULT)
                    sca.append(line, style: c, continuation: sca.continuation)
                    let splitLines = sca.split(maxWidth: Int(width)).map {
                        $0.0
                    }
                    result.append(contentsOf:splitLines);
                }
                return Result(lines: result, blocks: [:])
            }
        }
    }

    @objc(payloadsFromString:range:)
    static func payloads(fromString string: String, range: VT100GridAbsCoordRange) -> [Payload] {
        return Kind.allCases.compactMap {
            payload(fromString: string, range: range, kind: $0)
        }
    }

    @objc(payloadFromString:range:ofKind:)
    static func payload(fromString string: String, range: VT100GridAbsCoordRange, kind: Kind) -> Payload? {
        switch kind {
        case .json:
            Payload(json: string, range: range)
        case .base64Decode:
            Payload(base64DecodableString: string, range: range)
        case .base64Encode:
            Payload(base64EncodableString: string, range: range)
        }
    }
}


extension Data {
    static func urlSafeBase64EncodedString(_ string: String) -> Data? {
        guard let nsdata = NSData(urlSafeBase64EncodedString: string) else {
            return nil
        }
        return nsdata as Data
    }
}
