//
//  PromptStateMachine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/20/23.
//

import Foundation

@objc(iTermPromptStateMachineDelegate)
protocol PromptStateMachineDelegate: AnyObject {
    @objc func promptStateMachineRevealComposer(prompt: [ScreenCharArray])
    @objc func promptStateMachineDismissComposer()
    @objc func promptStateMachineLastPrompt() -> [ScreenCharArray]

    @objc(promptStateMachineAppendCommandToComposer:)
    func promptStateMachineAppendCommandToComposer(command: String)

    @objc var promptStateMachineCursorAbsCoord: VT100GridAbsCoord { get }
    @objc func promptStateMachineCheckForPrompt()
}

@objc(iTermPromptStateMachine)
class PromptStateMachine: NSObject {
    override var debugDescription: String {
        return "<PromptStateMachine: \(self.it_addressString) state=\(state)>"
    }
    @objc weak var delegate: PromptStateMachineDelegate?

    private enum State: CustomDebugStringConvertible {
        case disabled

        case ground
        case receivingPrompt

        // Composer is always open in this state.
        case enteringCommand(prompt: [ScreenCharArray])

        // Composer is always open in this state.
        case accruingAlreadyEnteredCommand(commandSoFar: String, prompt: [ScreenCharArray], cursorCoord: VT100GridAbsCoord)

        case echoingBack
        case executing

        var debugDescription: String {
            switch self {
            case .disabled: return "disabled"
            case .ground: return "ground"
            case .receivingPrompt: return "receivingPrompt"
            case .enteringCommand: return "enteringCommand"
            case let .accruingAlreadyEnteredCommand(commandSoFar: commandSoFar, prompt: prompt, cursorCoord: cursorCoord):
                return "accruingAlreadyEnteredCommand(commandSoFar: \(commandSoFar), prompt: \(prompt), cursorCoord: \(cursorCoord))"
            case .echoingBack: return "echoingBack"
            case .executing: return "executing"
            }
        }

        private enum Name: String {
            case disabled
            case ground
            case receivingPrompt
            case enteringCommand
            case accruingAlreadyEnteredCommand
            case echoingBack
            case executing
        }

        var name: String {
            switch self {
            case .disabled:
                return Name.disabled.rawValue
            case .ground:
                return Name.ground.rawValue
            case .receivingPrompt:
                return Name.receivingPrompt.rawValue
            case .enteringCommand:
                return Name.enteringCommand.rawValue
            case .echoingBack:
                return Name.echoingBack.rawValue
            case .executing:
                return Name.executing.rawValue
            case .accruingAlreadyEnteredCommand:
                return Name.accruingAlreadyEnteredCommand.rawValue

            }
        }
        private static let nameKey = "name"
        private static let promptKey = "prompt"
        private static let commandSoFarKey = "commandSoFar"
        private static let cursorCoordKey = "cursorCoord"

        var dictionaryValue: [String: Any] {
            var result: [String: Any] = [State.nameKey: name]
            switch self {
            case .disabled, .ground, .receivingPrompt, .echoingBack, .executing:
                break
            case .enteringCommand(prompt: let prompt):
                result[State.promptKey] = prompt.map { $0.dictionaryValue }
            case .accruingAlreadyEnteredCommand(commandSoFar: let commandSoFar,
                                                prompt: let prompt,
                                                cursorCoord: let cursorCoord):
                result[State.promptKey] = prompt.map { $0.dictionaryValue }
                result[State.commandSoFarKey] = commandSoFar
                result[State.cursorCoordKey] = ["x": Int64(cursorCoord.x), "y": Int64(cursorCoord.y)]
            }
            return result
        }

        private static func prompt(fromDictionary dictionary: NSDictionary) -> [ScreenCharArray] {
            let promptDictionaries: [[AnyHashable: Any]] = dictionary[State.promptKey] as? [[AnyHashable: Any]] ?? []
            let prompt: [ScreenCharArray] = promptDictionaries.compactMap { ScreenCharArray(dictionary: $0) }
            return prompt
        }

        init(dictionary: NSDictionary) {
            guard let name = dictionary[State.nameKey] as? String else {
                self = .ground
                return
            }
            switch Name(rawValue: name) {
            case .disabled:
                self = .disabled
            case .ground:
                self = .ground
            case .receivingPrompt:
                self = .receivingPrompt
            case .enteringCommand:
                self = .enteringCommand(prompt: Self.prompt(fromDictionary: dictionary))
            case .accruingAlreadyEnteredCommand:
                let commandSoFar = dictionary[State.commandSoFarKey] as? String ?? ""
                let cursorCoord: VT100GridAbsCoord
                if let obj = dictionary[State.cursorCoordKey],
                    let dict = obj as? [String: Int64],
                    let x = dict["x"],
                    let y = dict["y"] {
                    cursorCoord = VT100GridAbsCoord(x: Int32(x), y: y)
                } else {
                    cursorCoord = VT100GridAbsCoord(x: 0, y: -1)
                }
                self = .accruingAlreadyEnteredCommand(commandSoFar: commandSoFar,
                                                      prompt: Self.prompt(fromDictionary: dictionary),
                                                      cursorCoord: cursorCoord)
            case .echoingBack:
                self = .echoingBack
            case .executing:
                self = .executing
            case .none:
                self = .ground
            }
        }
    }

    private var _state = State.ground
    private var state: State { _state }
    private var currentEvent = ""
    @objc var isAtPrompt: Bool {
        switch state {
        case .disabled, .ground, .executing:
            return false
        case .receivingPrompt, .enteringCommand, .accruingAlreadyEnteredCommand, .echoingBack:
            return true
        }
    }

    private func set(state newValue: State, on event: String) {
        DLog("\(event): \(state) -> \(newValue)")
        _state = newValue
    }

    @objc var isEnteringCommand: Bool {
        switch state {
        case .enteringCommand, .accruingAlreadyEnteredCommand:
            return true
        case .executing, .echoingBack, .receivingPrompt, .ground, .disabled:
            return false
        }
    }

    @objc var isEchoingBackCommand: Bool {
        switch state {
        case .echoingBack:
            return true
        case .accruingAlreadyEnteredCommand, .executing, .receivingPrompt, .enteringCommand, .ground, .disabled:
            return false
        }
    }

    @objc(setAllowed:)
    func setAllowed(_ allowed: Bool) {
        if gDebugLogging.boolValue {
            currentEvent = "setAllowed"
        }
        defer {
            if gDebugLogging.boolValue {
                currentEvent = "none"
            }
        }
        if !allowed {
            set(state: .disabled, on: "disallowed")
            dismissComposer()
        } else {
            set(state: .ground, on: "allowed")
        }
    }

    // Call this before any other token handling.
    @objc(handleToken:withEncoding:)
    func handle(token: VT100Token, encoding: UInt) {
        // Computing the description can be somewhat expensive, and it's only
        // used for debugging. Use a placeholder instead when it's not used.
        if gDebugLogging.boolValue {
            currentEvent = "handleToken\(token.debugDescription)"
        }
        defer {
            if gDebugLogging.boolValue {
                currentEvent = "none"
            }
        }

        switch token.type {
        case XTERMCC_FINAL_TERM:
            handleFinalTermToken(token)
        default:
            handleToken(token, encoding: encoding)
        }
    }

    @objc
    func willSendCommand() {
        DLog("willSendCommand in \(state)")
        if gDebugLogging.boolValue {
            currentEvent = "willSendCommand"
        }
        defer {
            if gDebugLogging.boolValue {
                currentEvent = "none"
            }
        }

        switch state {
        case .disabled, .ground, .receivingPrompt, .accruingAlreadyEnteredCommand, .echoingBack, .executing:
            return
        case .enteringCommand:
            set(state: .echoingBack, on: "willSendCommand")
        }
    }

    @objc
    func revealOrDismissComposerAgain() {
        if gDebugLogging.boolValue {
            currentEvent = "re-do"
        }
        defer {
            if gDebugLogging.boolValue {
                currentEvent = "none"
            }
        }
        switch state {
        case .disabled, .ground, .receivingPrompt, .echoingBack, .executing:
            dismissComposer()

        case let .enteringCommand(prompt: prompt),
            let .accruingAlreadyEnteredCommand(_, prompt: prompt, _):
            revealComposer(prompt: prompt)
        }
    }

    private func handleFinalTermToken(_ token: VT100Token) {
        guard let value = token.string else {
            return
        }
        let args = value.components(separatedBy: ";")
        guard let firstArg = args.first else {
            return
        }
        switch firstArg {
        case "A":
            handleFinalTermA()
        case "B":
            handleFinalTermB()
        case "C":
            handleFinalTermC()
        case "D":
            handleFinalTermD()
        default:
            break
        }
    }

    // Will receive prompt
    private func handleFinalTermA() {
        switch state {
        case .disabled:
            break
        case .ground, .echoingBack, .executing:
            set(state: .receivingPrompt, on: "A")
        case .enteringCommand:
            dismissComposer()
            set(state: .receivingPrompt, on: "A")
        case .receivingPrompt:
            break
        case .accruingAlreadyEnteredCommand:
            set(state: .receivingPrompt, on: "A")
        }
    }

    // Did receive prompt
    private func handleFinalTermB() {
        switch state {
        case .disabled:
            break
        case .receivingPrompt:
            // Expect a call to didCapturePrompt
            break
        case .enteringCommand:
            // Something crazy happened so continue without composer.
            dismissComposer()
            set(state: .ground, on: "B")
        case .ground, .echoingBack, .executing:
            // Something crazy happened so continue without composer.
            delegate?.promptStateMachineCheckForPrompt()
            set(state: .ground, on: "B")
        case .accruingAlreadyEnteredCommand:
            // Something crazy happened so continue without composer.
            set(state: .ground, on: "B")
        }
    }

    @objc(didCapturePrompt:)
    func didCapturePrompt(promptText: [ScreenCharArray]) {
        switch state {
        case .disabled:
            break
        case .receivingPrompt:
            revealComposer(prompt: promptText)
            set(state: .enteringCommand(prompt: promptText), on: "B")
        case .enteringCommand, .ground, .echoingBack, .executing, .accruingAlreadyEnteredCommand:
            // If you get here it's probably because a trigger detected the prompt.
            revealComposer(prompt: promptText)
            set(state: .enteringCommand(prompt: promptText), on: "Trigger, probably")
            break
        }
    }

    // Command began executing
    private func handleFinalTermC() {
        commandDidBeginExecution(reason: "C")
    }

    @objc
    func triggerDetectedCommandDidBeginExecution() {
        commandDidBeginExecution(reason: "Trigger")
    }

    func commandDidBeginExecution(reason: String) {
        switch state {
        case .disabled:
            break
        case .ground, .receivingPrompt, .executing:
            // Something crazy happened so continue without composer.
            set(state: .ground, on: reason)
        case .enteringCommand:
            // TODO: Your work will be lost.
            dismissComposer()
            set(state: .ground, on: reason)
        case .echoingBack, .accruingAlreadyEnteredCommand:
            dismissComposer()
            set(state: .executing, on: reason)
        }
    }

    // Command finished executing
    private func handleFinalTermD() {
        switch state {
        case .disabled:
            break
        case .ground, .receivingPrompt, .echoingBack, .executing, .accruingAlreadyEnteredCommand:
            set(state: .ground, on: "D")
        case .enteringCommand:
            dismissComposer()
            set(state: .ground, on: "D")
        }
    }

    // Returns whether the token should be handled immediately.
    private func handleToken(_ token: VT100Token, encoding: UInt) {
        switch state {
        case .ground, .receivingPrompt, .echoingBack, .executing, .disabled:
            return
        case .enteringCommand(let prompt):
            let command = token.stringValue(encoding: String.Encoding(rawValue: encoding)) ?? ""
            if command.isEmpty {
                // Allow stuff like focus reporting to go through.
                return
            }
            accrue(coord: delegate?.promptStateMachineCursorAbsCoord ?? VT100GridAbsCoord(x: 0, y: -1),
                   previousCoord: VT100GridAbsCoord(x: 0, y: -1),
                   part: String(command.trimmingLeadingCharacters(in: .whitespaces)),
                   commandSoFar: "",
                   prompt: prompt)
        case .accruingAlreadyEnteredCommand(commandSoFar: let commandSoFar, let prompt, let cursorCoord):
            let part = token.stringValue(encoding: String.Encoding(rawValue: encoding)) ?? ""
            accrue(coord: delegate?.promptStateMachineCursorAbsCoord ?? VT100GridAbsCoord(x: 0, y: -1),
                   previousCoord: cursorCoord,
                   part: part,
                   commandSoFar: commandSoFar,
                   prompt: prompt)
        }
    }

    private func accrue(coord: VT100GridAbsCoord,
                        previousCoord: VT100GridAbsCoord,
                        part: String,
                        commandSoFar: String,
                        prompt: [ScreenCharArray]) {
        if coord.y == previousCoord.y && coord.x <= previousCoord.x {
            DLog("Reject \(part) at \(coord.x),\(coord.y)")
            return
        }
        DLog("Accept \(part) at \(coord.x),\(coord.y)")
        let maxLength = 1024 * 4
        // String.count is O(n) and this becomes accidentally quadratic but counting UTF-16 seems to be fast.
        if commandSoFar.utf16.count + part.utf16.count > maxLength {
            return
        }
        set(state: .accruingAlreadyEnteredCommand(commandSoFar: commandSoFar + part,
                                                  prompt: prompt,
                                                  cursorCoord: coord),
            on: "token")
        if !part.isEmpty {
            appendCommandToComposer(command: part)
        }
    }

    private func revealComposer(prompt: [ScreenCharArray]) {
        DLog("revealComposer because \(currentEvent) in \(state)")
        delegate?.promptStateMachineRevealComposer(prompt: prompt)
    }

    private func dismissComposer() {
        DLog("dismissComposer because \(currentEvent) in \(state)")
        delegate?.promptStateMachineDismissComposer()
    }

    private func lastPrompt() -> [ScreenCharArray]? {
        return delegate?.promptStateMachineLastPrompt()
    }

    private func appendCommandToComposer(command: String) {
        DLog("appendCommandToComposer(\(command)) because \(currentEvent) in \(state)")
        delegate?.promptStateMachineAppendCommandToComposer(command: command)
    }

    @objc
    func loadPromptStateDictionary(_ dict: NSDictionary) {
        _state = State(dictionary: dict)
        switch state {
        case .disabled, .ground, .receivingPrompt, .echoingBack, .executing:
            dismissComposer()
        case .enteringCommand(let prompt):
            revealComposer(prompt: prompt)
        case .accruingAlreadyEnteredCommand(commandSoFar: let commandSoFar, prompt: let prompt, _):
            revealComposer(prompt: prompt)
            delegate?.promptStateMachineAppendCommandToComposer(command: commandSoFar)
        }
    }

    @objc
    var dictionaryValue: NSDictionary {
        return state.dictionaryValue as NSDictionary
    }
}


extension VT100Token {
    func stringValue(encoding: String.Encoding) -> String? {
        switch type {
        case VT100_STRING:
            return self.string
        case VT100_ASCIISTRING:
            let data = NSData(bytes: asciiData.pointee.buffer, length: Int(asciiData.pointee.length))
            return String(data: data as Data, encoding: encoding)
        case VT100CC_LF:
            return "\n"
        default:
            return nil
        }
    }
}
