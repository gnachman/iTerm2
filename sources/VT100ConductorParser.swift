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
        case output(builder: SSHOutputTokenBuilder)
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
            DLog("Found a newline at offset \(bytesTilNewline)")
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
            DLog("Input \(line as NSData) invalid UTF-8")
            return .unhook
        }
        DLog("Process line \(string)")
        line = Data()
        switch state {
        case .initial:
            DLog("In initial state. Accept line as SSH_INIT.")
            token.type = SSH_INIT
            token.string = string
            state = .ground
            return .keepGoing

        case .ground:
            if string.hasPrefix("begin ") {
                let parts = string.components(separatedBy: " ")
                guard parts.count >= 2 else {
                    DLog("Malformed begin token, unhook")
                    return .unhook
                }
                DLog("In ground state: Found valid begin token")
                state = .body(parts[1])
                // No need to expose this to clients.
                token.type = SSH_BEGIN
                token.string = parts[1]
                return .keepGoing
            } else if string == "unhook" {
                DLog("In ground state: Found valid unhook token")
                token.type = SSH_UNHOOK
                return .unhook
            } else if string.hasPrefix("%output ") {
                if let builder = SSHOutputTokenBuilder(string) {
                    state = .output(builder: builder)
                    return .keepGoing
                } else {
                    DLog("Malformed %output, unhook")
                    return .unhook
                }
            } else if string.hasPrefix("%terminate ") {
                let parts = string.components(separatedBy: " ")
                guard parts.count >= 3, let pid = Int32(parts[1]), let rc = Int32(parts[2]) else {
                    DLog("Malformed %terminate, unhook")
                    return .unhook
                }
                token.type = SSH_TERMINATE
                iTermAddCSIParameter(token.csi, pid)
                iTermAddCSIParameter(token.csi, rc)
                return .keepGoing
            } else {
                DLog("In ground state: Found unrecognized token")
                return .unhook
            }

        case .output(builder: let builder):
            if string.hasPrefix("%end \(builder.identifier)") {
                if builder.populate(token) {
                    state = .ground
                    return .keepGoing
                }
                DLog("Failed to build \(builder)")
                return .unhook
            }
            builder.append(string)
            return .keepGoing

        case .body(let id):
            let expectedPrefix = "end \(id) "
            if string.hasPrefix(expectedPrefix) {
                DLog("In body state: found valid end token")
                state = .ground
                token.type = SSH_END
                token.string = id + " " + String(string.dropFirst(expectedPrefix.count))
            } else {
                DLog("In body state: found valid line")
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

private class SSHOutputTokenBuilder {
    let pid: Int32
    let channel: Int8
    let identifier: String
    @objc private(set) var base64 = ""

    init?(_ string: String) {
        let parts = string.components(separatedBy: " ")
        guard parts.count >= 4, let pid = Int32(parts[2]), let channel = Int8(parts[3]) else {
            return nil
        }
        self.pid = pid
        self.identifier = parts[1]
        self.channel = channel
    }

    func append(_ string: String) {
        base64.append(string)
    }

    func populate(_ token: VT100Token) -> Bool {
        guard let data = Data(base64Encoded: base64) else {
            return false
        }
        token.csi.pointee.p.0 = pid
        token.csi.pointee.p.1 = Int32(channel)
        token.csi.pointee.count = 2
        token.savedData = data
        token.type = SSH_OUTPUT
        return true
    }
}

@objc class ParsedSSHOutput: NSObject {
    @objc let pid: Int32
    @objc let channel: Int32
    @objc let data: Data

    @objc init?(_ token: VT100Token) {
        guard token.type == SSH_OUTPUT else {
            return nil
        }
        guard token.csi.pointee.count >= 2 else {
            return nil
        }
        pid = token.csi.pointee.p.0
        channel = token.csi.pointee.p.1
        data = token.savedData
    }
}
