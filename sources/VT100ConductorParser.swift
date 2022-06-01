//
//  VT100ConductorParser.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/9/22.
//

import Foundation

@objc
class VT100ConductorParser: NSObject, VT100DCSParserHook {
    private var recoveryMode = false
    private var line = Data()
    private let uniqueID: String
    private enum State {
        case initial
        case ground
        case body(String)
        case output(builder: SSHOutputTokenBuilder)
        case autopoll(builder: SSHOutputTokenBuilder)
    }
    private var state = State.initial
    var hookDescription: String {
        return "[SSH CONDUCTOR]"
    }

#warning("DNS")
    private func DLog(_ messageBlock: @autoclosure () -> String,
                      file: String = #file,
                      line: Int = #line,
                      function: String = #function) {
        let message = messageBlock()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "HH:mm:ss.SSS ZZZ",
                                                            options: 0,
                                                            locale: nil)
        let hms = dateFormatter.string(from: Date())
        print("\(hms) \(file.lastPathComponent):\(line) \(function): [\(self.it_addressString)] \(message)")
    }

    @objc(initWithUniqueID:)
    init(uniqueID: String) {
        self.uniqueID = uniqueID
    }

    @objc static func newRecoveryModeInstance(uniqueID: String) -> VT100ConductorParser {
        let instance = VT100ConductorParser(uniqueID: uniqueID)
        instance.recoveryMode = true
        instance.state = .ground
        return instance
    }

    // Return true to unhook.
    func handleInput(_ context: UnsafeMutablePointer<iTermParserContext>,
                     support8BitControlCharacters: Bool,
                     token result: VT100Token) -> VT100DCSParserHookResult {
        result.type = VT100_WAIT
        switch state {
        case .initial:
            return parseInitial(context, into: result)

        case .ground:
            return parseGround(context, token: result)

        case .body(let id):
            return parseBody(context, identifier: id, token: result)

        case .output(builder: let builder), .autopoll(builder: let builder):
            return parseOutput(context, builder: builder, token: result)
        }
    }

    enum OSCParserResult {
        case notOSC
        case osc(Int, String)
        case blocked
    }
    private func parseNextOSC(_ context: UnsafeMutablePointer<iTermParserContext>,
                              skipInitialGarbage: Bool) -> OSCParserResult {
        enum State {
            case ground
            case esc
            case osc(String)
            case oscParam(Int, String)
            case oscEsc(Int, String)
        }
        let esc = 27
        let closeBracket = Character("]").asciiValue!
        let zero = Character("0").asciiValue!
        let nine = Character("9").asciiValue!
        let semicolon = Character(";").asciiValue!
        let backslash = Character("\\").asciiValue!
        var checkpoint = iTermParserNumberOfBytesConsumed(context)
        var state: State = State.ground {
            didSet {
                switch state {
                case .ground:
                    checkpoint = iTermParserNumberOfBytesConsumed(context)
                default:
                    break
                }
            }
        }
        while iTermParserCanAdvance(context) {
            let c = iTermParserConsume(context)
            switch state {
            case .ground:
                if c == esc {
                    state = .esc
                } else {
                    if !skipInitialGarbage {
                        iTermParserBacktrack(context, offset: checkpoint)
                        return .notOSC
                    }
                    checkpoint = iTermParserNumberOfBytesConsumed(context)
                }
            case .esc:
                if c == closeBracket {
                    state = .osc("")
                } else {
                    if !skipInitialGarbage {
                        iTermParserBacktrack(context, offset: checkpoint)
                        return .notOSC
                    }
                    state = .ground
                }
            case .osc(let param):
                if c >= zero && c <= nine {
                    state = .osc(param + String(ascii: c))
                } else if c == semicolon, let code = Int(param) {
                    state = .oscParam(code, "")
                } else {
                    if !skipInitialGarbage {
                        iTermParserBacktrack(context, offset: checkpoint)
                        return .notOSC
                    }
                    state = .ground
                }
            case .oscParam(let code, let payload):
                if c == esc {
                    state = .oscEsc(code, payload)
                } else {
                    state = .oscParam(code, payload + String(ascii: c))
                }
            case .oscEsc(let code, let payload):
                if c == backslash {
                    // Ignore any unrecognized paramters which may come before the colon and then
                    // ignore the colon itself.
                    return .osc(code, String(payload.substringAfterFirst(":")))
                } else {
                    state = .oscParam(code, payload + String(ascii: UInt8(esc)) + String(ascii: c))
                }
            }
        }
        iTermParserBacktrack(context, offset: checkpoint)
        return .blocked
    }

    private func parseNextLine(_ context: UnsafeMutablePointer<iTermParserContext>) -> Data? {
        let bytesTilNewline = iTermParserNumberOfBytesUntilCharacter(context, "\n".firstASCIICharacter)
        if bytesTilNewline == -1 {
            DLog("No newline found")
            return nil
        }
        let bytes = iTermParserPeekRawBytes(context, bytesTilNewline)
        let buffer = UnsafeBufferPointer(start: bytes, count: Int(bytesTilNewline))
        iTermParserAdvanceMultiple(context, bytesTilNewline)
        return Data(buffer: buffer)
    }

    private enum ProcessingResult {
        case keepGoing
        case unhook
    }

    private func parseInitial(_ context: UnsafeMutablePointer<iTermParserContext>,
                              into token: VT100Token) -> VT100DCSParserHookResult {
        // Read initial payload of DCS 2000p
        // Space-delimited args of at least token, unique ID, boolean args, [possible future args], hyphen, ssh args.
        guard let lineData = parseNextLine(context) else {
            return .blocked
        }
        guard let line = String(data: lineData, encoding: .utf8) else {
            DLog("non-utf8 data \((lineData as NSData).it_hexEncoded())")
            return .unhook
        }
        DLog("In initial state. Accept line as SSH_INIT.")
        token.type = SSH_INIT
        token.string = line + " " + uniqueID
        state = .ground
        return .canReadAgain
    }

    private func parsePreFramerPayload(_ string: String, into token: VT100Token) -> VT100DCSParserHookResult {
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
            return .canReadAgain
        }
        if string == "unhook" {
            DLog("In ground state: Found valid unhook token")
            token.type = SSH_UNHOOK
            return .unhook
        }
        DLog("In ground state: Found unrecognized token")
        return .unhook
    }

    private func parseFramerBegin(_ string: String, into token: VT100Token) -> VT100DCSParserHookResult {
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
        return .canReadAgain
    }

    private func parseFramerOutput(_ string: String, into token: VT100Token) -> VT100DCSParserHookResult {
        if let builder = SSHOutputTokenBuilder(string) {
            DLog("create builder with identifier \(builder.identifier)")
            state = .output(builder: builder)
            return .canReadAgain
        }
        DLog("Malformed %output/%autopoll, unhook")
        return .unhook
    }

    private func parseFramerTerminate(_ string: String, into token: VT100Token) -> VT100DCSParserHookResult {
        let parts = string.components(separatedBy: " ")
        guard parts.count >= 3, let pid = Int32(parts[1]), let rc = Int32(parts[2]) else {
            DLog("Malformed %terminate, unhook")
            return .unhook
        }
        token.type = SSH_TERMINATE
        iTermAddCSIParameter(token.csi, pid)
        iTermAddCSIParameter(token.csi, rc)
        return .canReadAgain
    }

    private func parseFramerPayload(_ string: String, into token: VT100Token) -> VT100DCSParserHookResult {
        let wasInRecoveryMode = recoveryMode
        recoveryMode = false
        if string.hasPrefix("begin ") {
            return parseFramerBegin(string, into: token)
        }
        if string.hasPrefix("%output ") || string.hasPrefix("%autopoll ") {
            return parseFramerOutput(string, into: token)
        }
        if string.hasPrefix("%terminate ") {
            return parseFramerTerminate(string, into: token)
        }
        if string.hasPrefix("%") {
            DLog("Ignore unrecognized notification \(string)")
            return .canReadAgain
        }
        if wasInRecoveryMode {
            DLog("Ignore unrecognized line in recovery mode")
            recoveryMode = true
            return .canReadAgain
        }
        DLog("In ground state: Found unrecognized token")
        return .unhook
    }

    struct ConditionalPeekResult {
        let context: UnsafeMutablePointer<iTermParserContext>
        var offset: Int
        var result: OSCParserResult
        func backtrack() {
            iTermParserBacktrack(context, offset: offset)
        }
    }

    private func conditionallyPeekOSC(_ context: UnsafeMutablePointer<iTermParserContext>) -> ConditionalPeekResult {
        let startingOffset = iTermParserNumberOfBytesConsumed(context)
        let result = parseNextOSC(context, skipInitialGarbage: false)
        return ConditionalPeekResult(context: context, offset: startingOffset, result: result)
    }

    enum DataOrOSC {
        case data(Data)
        case eof
    }

    // If the context starts with an OSC, it's not one we care about. Stop before an osc beginning
    // after the first bytes.
    private func consumeUntilStartOfNextOSCOrEnd(_ context: UnsafeMutablePointer<iTermParserContext>) -> DataOrOSC {
        if !iTermParserCanAdvance(context) {
            return .eof
        }
        let esc = UInt8(VT100CC_ESC.rawValue)
        let count = iTermParserNumberOfBytesUntilCharacter(context, esc)
        let bytesToConsume: Int32
        if count == 0 {
            bytesToConsume = 1
        } else if count < 0 {
            // no esc, consume everything.
            bytesToConsume = iTermParserLength(context)
        } else {
            precondition(count > 0)
            // stuff before esc, consume up to it
            bytesToConsume = count
        }
        precondition(bytesToConsume > 0)
        let buffer = UnsafeBufferPointer(start: iTermParserPeekRawBytes(context, bytesToConsume)!,
                                         count: Int(bytesToConsume))
        let data = Data(buffer: buffer)
        iTermParserAdvanceMultiple(context, bytesToConsume)
        return .data(data)
    }

    private func parseGround(_ context: UnsafeMutablePointer<iTermParserContext>,
                             token result: VT100Token) -> VT100DCSParserHookResult {
        // Base state, possibly pre-framer. Everything should be wrapped in OSC 134 or 135.
        while iTermParserCanAdvance(context) {
            switch parseNextOSC(context, skipInitialGarbage: true) {
            case .osc(134, let payload):
                return parseFramerPayload(payload, into: result)
            case .osc(135, let payload):
                return parsePreFramerPayload(payload, into: result)
            case .blocked:
                return .blocked
            case .notOSC:
                fatalError()
            case .osc(let code, let payload):
                DLog("Ignore unrecognized osc with code \(code) and payload \(payload)")
                // Ignore unrecognized OSC
            }
        }
        return .canReadAgain
    }

    private func parseBody(_ context: UnsafeMutablePointer<iTermParserContext>,
                           identifier id: String,
                           token result: VT100Token) -> VT100DCSParserHookResult {
        if !iTermParserCanAdvance(context) {
            return .canReadAgain
        }
        let peek = conditionallyPeekOSC(context)
        switch peek.result {
        case .osc(134, let payload), .osc(135, let payload):
            let expectedPrefix = "end \(id) "
            if payload.hasPrefix(expectedPrefix) {
                DLog("In body state: found valid end token")
                state = .ground
                result.type = SSH_END
                result.string = id + " " + String(payload.dropFirst(expectedPrefix.count))
                return .canReadAgain
            }
            DLog("In body state: found valid line \(payload)")
            result.type = SSH_LINE
            result.string = payload
            return .canReadAgain
        case .osc(_, _), .notOSC:
            DLog("non-OSC 134/135 output: \(context.dump)")
            peek.backtrack()
            return .unhook
        case .blocked:
            DLog("Need to keep reading body, blocked at \(context.dump)")
            peek.backtrack()
            return .blocked
        }
    }

    private func parseOutput(_ context: UnsafeMutablePointer<iTermParserContext>,
                             builder: SSHOutputTokenBuilder,
                             token: VT100Token) -> VT100DCSParserHookResult {
        let terminator = "%end \(builder.identifier)"
        let peek = conditionallyPeekOSC(context)
        switch peek.result {
        case .osc(134, terminator):
            if builder.populate(token) {
                state = .ground
                return .canReadAgain
            }
            DLog("Failed to build \(builder)")
            return .unhook
        case .blocked:
            peek.backtrack()
            return .blocked
        case .notOSC, .osc(_, _):
            peek.backtrack()
            switch consumeUntilStartOfNextOSCOrEnd(context) {
            case .eof:
                break
            case .data(let text):
                builder.append(text)
            }
            return .canReadAgain
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
    let depth: Int
    enum Flavor: String {
        case output = "%output"
        case autopoll = "%autopoll"
    }
    @objc private(set) var rawData = Data()

    init?(_ string: String) {
        let parts = string.components(separatedBy: " ")
        guard let flavor = Flavor(rawValue: parts[0]) else {
            return nil
        }
        switch flavor {
        case .output:
            guard parts.count >= 5,
                  let pid = Int32(parts[2]),
                  let channel = Int8(parts[3]),
                  let depth = Int(parts[4]) else {
                return nil
            }
            self.pid = pid
            self.channel = channel
            self.depth = depth
        case .autopoll:
            guard parts.count >= 2 else {
                return nil
            }
            self.pid = SSH_OUTPUT_AUTOPOLL_PID
            self.channel = 1
            self.depth = 0
        }
        self.identifier = parts[1]
    }

    func append(_ data: Data) {
        rawData.append(data)
    }

    private var decoded: Data? {
        if pid == SSH_OUTPUT_AUTOPOLL_PID {
            return ((String(data: rawData, encoding: .utf8) ?? "") + "\nEOF\n").data(using: .utf8)
        } else {
            return rawData
        }
    }

    func populate(_ token: VT100Token) -> Bool {
        guard let data = decoded else {
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

extension String {
    func removing(prefix: String) -> Substring {
        guard hasPrefix(prefix) else {
            return Substring(self)
        }
        return dropFirst(prefix.count)
    }

    fileprivate static let VT100CC_ST = "\u{1b}\\"
}

extension Substring {
    var removingOSC134Prefix: Substring {
        let osc134 = "\u{1b}]134;"
        guard hasPrefix(osc134) else {
            return Substring(self)
        }
        guard let colon = range(of: ":") else {
            return ""
        }
        return self[colon.upperBound...]
    }
}

extension Data {
    func ends(with possibleSuffix: Data) -> Bool {
        if count < possibleSuffix.count {
            return false
        }
        let i = count - possibleSuffix.count
        return self[i...] == possibleSuffix
    }
}

func iTermParserBacktrack(_ context: UnsafeMutablePointer<iTermParserContext>,
                          offset: Int) {
    iTermParserBacktrackBy(context, Int32(iTermParserNumberOfBytesConsumed(context) - offset))
}

extension UnsafeMutablePointer where Pointee == iTermParserContext {
    var dump: String {
        let length = iTermParserLength(self)
        let bytes = iTermParserPeekRawBytes(self, length)!
        return "count=\(length) " + (0..<length).map { i -> String in
            let c = bytes[Int(i)]
            if c < 32 || c >= 127 {
                let hex: String = String(format: "%02x", Int(c))
                return "<0x" + hex + ">"
            }
            return String(ascii: UInt8(c))
        }.joined(separator: "")
    }
}
