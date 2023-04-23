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
}

@objc(iTermPromptStateMachine)
class PromptStateMachine: NSObject {
    @objc weak var delegate: PromptStateMachineDelegate?

    private enum State: CustomDebugStringConvertible {
        case ground
        case receivingPrompt

        // Composer is always open in this state.
        case enteringCommand

        // Composer is always open in this state.
        case accruingAlreadyEnteredCommand(commandSoFar: String)

        case echoingBack
        case executing

        var debugDescription: String {
            switch self {
            case .ground: return "ground"
            case .receivingPrompt: return "receivingPrompt"
            case .enteringCommand: return "enteringCommand"
            case let .accruingAlreadyEnteredCommand(commandSoFar: commandSoFar):
                return "accruingAlreadyEnteredCommand(commandSoFar: \(commandSoFar))"
            case .echoingBack: return "echoingBack"
            case .executing: return "executing"
            }
        }
    }

    private var _state = State.ground
    private var state: State { _state }
    private var currentEvent = ""

    private func set(state newValue: State, on event: String) {
        NSLog("\(event): \(state) -> \(newValue)")
        _state = newValue
    }

    // Call this before any other token handling.
    @objc(handleToken:withEncoding:)
    func handle(token: VT100Token, encoding: UInt) {
        currentEvent = "handleToken\(token.debugDescription)"
        defer { currentEvent = "none" }

        switch token.type {
        case XTERMCC_FINAL_TERM:
            handleFinalTermToken(token)
        default:
            handleToken(token, encoding: encoding)
        }
    }

    @objc
    func willSendCommand() {
        NSLog("willSendCommand in \(state)")
        currentEvent = "willSendCommand"
        defer { currentEvent = "none" }

        switch state {
        case .ground, .receivingPrompt, .accruingAlreadyEnteredCommand, .echoingBack, .executing:
            return
        case .enteringCommand:
            set(state: .echoingBack, on: "willSendCommand")
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
        case .receivingPrompt:
            // Expect a call to didCapturePrompt
            break
        case .enteringCommand:
            // Something crazy happened so continue without composer.
            dismissComposer()
            set(state: .ground, on: "B")
        case .ground, .echoingBack, .executing:
            // Something crazy happened so continue without composer.
            set(state: .ground, on: "B")
        case .accruingAlreadyEnteredCommand:
            // Something crazy happened so continue without composer.
            set(state: .ground, on: "B")
        }
    }

    @objc(didCapturePrompt:)
    func didCapturePrompt(promptText: [ScreenCharArray]) {
        switch state {
        case .receivingPrompt:
            revealComposer(prompt: promptText)
            set(state: .enteringCommand, on: "B")
        case .enteringCommand, .ground, .echoingBack, .executing, .accruingAlreadyEnteredCommand:
            fatalError("Unexpected didCapturePrompt in \(state)")
            break
        }
    }

    // Command began executing
    private func handleFinalTermC() {
        switch state {
        case .ground, .receivingPrompt, .executing:
            // Something crazy happened so continue without composer.
            set(state: .ground, on: "C")
        case .enteringCommand:
            // TODO: Your work will be lost.
            dismissComposer()
            set(state: .ground, on: "C")
        case .echoingBack, .accruingAlreadyEnteredCommand:
            dismissComposer()
            set(state: .executing, on: "C")
        }
    }

    // Command finished executing
    private func handleFinalTermD() {
        switch state {
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
        case .ground, .receivingPrompt, .echoingBack, .executing:
            return
        case .enteringCommand:
            let command = token.stringValue(encoding: String.Encoding(rawValue: encoding)) ?? ""
            if command.isEmpty {
                // Allow stuff like focus reporting to go through.
                return
            }
            accrue(part: String(command.trimmingLeadingCharacters(in: .whitespaces)),
                   commandSoFar: "")
        case .accruingAlreadyEnteredCommand(commandSoFar: let commandSoFar):
            let part = token.stringValue(encoding: String.Encoding(rawValue: encoding)) ?? ""
            accrue(part: part, commandSoFar: commandSoFar)
        }
    }

    private func accrue(part: String, commandSoFar: String) {
        set(state: .accruingAlreadyEnteredCommand(commandSoFar: commandSoFar + part),
            on: "token")
        if !part.isEmpty {
            appendCommandToComposer(command: part)
        }
    }

    private func revealComposer(prompt: [ScreenCharArray]) {
        NSLog("revealComposer because \(currentEvent) in \(state)")
        delegate?.promptStateMachineRevealComposer(prompt: prompt)
    }

    private func dismissComposer() {
        NSLog("dismissComposer because \(currentEvent) in \(state)")
        delegate?.promptStateMachineDismissComposer()
    }

    private func lastPrompt() -> [ScreenCharArray]? {
        return delegate?.promptStateMachineLastPrompt()
    }

    private func appendCommandToComposer(command: String) {
        NSLog("appendCommandToComposer(\(command)) because \(currentEvent) in \(state)")
        delegate?.promptStateMachineAppendCommandToComposer(command: command)
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
