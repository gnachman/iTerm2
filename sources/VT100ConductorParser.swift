//
//  VT100ConductorParser.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/9/22.
//

import Foundation

@objc
class VT100ConductorParser: NSObject, VT100DCSParserHook {
    private var line = Data()
    private enum State {
        case initial
        case ground
        case body(String)
    }
    private var state = State.initial
    var hookDescription: String {
        return "[SSH CONDUCTOR]"
    }

    func handleInput(_ context: UnsafeMutablePointer<iTermParserContext>,
                     support8BitControlCharacters: Bool,
                     token result: VT100Token) -> Bool {
        let bytesTilNewline = iTermParserNumberOfBytesUntilCharacter(context, "\n".firstASCIICharacter)
        if bytesTilNewline == -1 {
            DLog("No newline found")
            // No newline to be found. Append everything that is available to `_line`.
            let length = iTermParserLength(context)
            line.appendBytes(iTermParserPeekRawBytes(context, length),
                             length: Int(length),
                             excludingCharacter: "\r".firstASCIICharacter)
            iTermParserAdvanceMultiple(context, length)
            result.type = VT100_WAIT
        } else {
            // Append bytes up to the newline, stripping out linefeeds. Consume the newline.
            line.appendBytes(iTermParserPeekRawBytes(context, bytesTilNewline),
                             length: Int(bytesTilNewline),
                             excludingCharacter: "\r".firstASCIICharacter)
            iTermParserAdvanceMultiple(context, bytesTilNewline + 1)
            return processLine(into: result) == .unhook
        }
        return false
    }

    private enum ProcessingResult {
        case keepGoing
        case unhook
    }

    private func processLine(into token: VT100Token) -> ProcessingResult {
        guard let string = String(data: line, encoding: .utf8) else {
            return .unhook
        }
        line = Data()
        switch state {
        case .initial:
            token.type = SSH_INIT
            token.string = string
            state = .ground
            return .keepGoing
        case .ground:
            if string.hasPrefix("begin ") {
                let parts = string.components(separatedBy: " ")
                guard parts.count >= 2 else {
                    return .unhook
                }
                state = .body(parts[1])
                // No need to expose this to clients.
                token.type = VT100_WAIT
                return .keepGoing
            } else if string == "unhook" {
                token.type = SSH_UNHOOK
                return .unhook
            } else {
                return .unhook
            }

        case .body(let id):
            let expectedPrefix = "end \(id) "
            if string.hasPrefix(expectedPrefix) {
                state = .ground
                token.type = SSH_END
                token.string = String(string.dropFirst(expectedPrefix.count))
            } else {
                token.type = SSH_LINE
                token.string = string
                line = Data()
            }
            return .keepGoing
        }
    }
}

extension String {
    var firstASCIICharacter: UInt8 {
        return UInt8(utf8.first!)
    }
}

extension Data {
    mutating func appendBytes(_ pointer: UnsafePointer<UInt8>,
                              length: Int,
                              excludingCharacter: UInt8) {
        let buffer = UnsafeBufferPointer(start: pointer, count: length)
        let exclusion = Data([excludingCharacter])
        var rangeToSearch = 0..<length
        while rangeToSearch.lowerBound < rangeToSearch.upperBound {
            if let excludeRange = buffer.firstRange(of: exclusion, in: rangeToSearch) {
                append(from: pointer, range: rangeToSearch.lowerBound ..< excludeRange.lowerBound)
                rangeToSearch = excludeRange.upperBound..<length
            } else {
                append(from: pointer, range: rangeToSearch.lowerBound ..< length)
                return
            }
        }
    }

    mutating func append(from pointer: UnsafePointer<UInt8>, range: Range<Int>) {
        append(pointer.advanced(by: range.lowerBound), count: range.count)
    }
}
