//
//  DoubleTapHotkeyStateMachine.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/1/23.
//

import Foundation

@objc(iTermDoubleTapHotkeyStateMachine)
class DoubleTapHotkeyStateMachine: NSObject {
    private enum State {
        case ground
        case firstDown
        case firstUp
        case secondDown
    }
    private var lastChange: TimeInterval = 0
    private var state = State.ground {
        willSet {
            if state != newValue {
                DLog("\(self.it_addressString): \(state) -> \(newValue)")
            }
        }
        didSet {
            lastChange = NSDate.it_timeSinceBoot()
        }
    }

    // MARK: - APIs

    @objc
    func reset() {
        if state != .ground {
            DLog("\(self.it_addressString): Reset")
            state = .ground
        }
    }

    // Returns true on activation.
    @objc(handleEvent:activationModifier:)
    func handle(event: CGEvent,
                activationModifier: iTermHotKeyModifierActivation) -> Bool {
        let change = Change(event.flags, activationModifier: activationModifier)
        DLog("\(self.it_addressString): state=\(state) change=\(change) event.flags=\(event.flags) activationModifier=\(activationModifier)")
        let result = {
            switch state {
            case .ground:
                return handleGround(change)

            case .firstDown:
                return handleFirstDown(change)

            case .firstUp:
                return handleFirstUp(change)

            case .secondDown:
                return handleSecondDown(change)
            }
        }()
        DLog("\(self.it_addressString): return \(result), state=\(state)")
        return result
    }

    private struct Change: CustomDebugStringConvertible {
        var debugDescription: String {
            return "<Change onlyActivationModifierIsPressed=\(onlyActivationModifierIsPressed) anyModifierIsPressed=\(anyModifierIsPressed)>"
        }
        var onlyActivationModifierIsPressed: Bool
        var anyModifierIsPressed: Bool

        init(_ flags: CGEventFlags,
             activationModifier: iTermHotKeyModifierActivation) {
            onlyActivationModifierIsPressed = Change.isOnlyModifierPressed(flags, activationModifier: activationModifier)
            anyModifierIsPressed = !flags.intersection(Change.mask).isEmpty
        }

        private static let mask = CGEventFlags([
            CGEventFlags.maskShift,
            CGEventFlags.maskAlternate,
            CGEventFlags.maskCommand,
            CGEventFlags.maskControl])

        private static func isOnlyModifierPressed(_ flags: CGEventFlags,
                                                  activationModifier modifier: iTermHotKeyModifierActivation) -> Bool {
            let maskedFlags = flags.intersection(mask)
            DLog("Masked flags are \(maskedFlags) for mask \(mask)")
            switch modifier {
            case .shift:
                return maskedFlags == [.maskShift]
            case .option:
                return maskedFlags == [.maskAlternate]
            case .command:
                return maskedFlags == [.maskCommand]
            case .control:
                return maskedFlags == [.maskControl]
            @unknown default:
                fatalError()
            }
        }
    }

    private func handleGround(_ change: Change) -> Bool {
        if change.onlyActivationModifierIsPressed {
            state = .firstDown
        }
        return false
    }

    /// If `nextState` is nil then a valid key-up is an activation. Otherwise transition to it.
    private func handleKeyUp(_ change: Change,
                             nextState: State?) -> Bool {
        guard eventIsTimely else {
            state = .ground
            return false
        }
        guard change.onlyActivationModifierIsPressed || !change.anyModifierIsPressed else {
            // Keydown on another modifier concurrent with hotkey modifier.
            state = .ground
            return false
        }
        guard !change.anyModifierIsPressed else {
            // Uninteresting event like Fn
            return false
        }
        if let nextState {
            state = nextState
            return false
        }
        state = .ground
        return true
    }

    private func handleFirstDown(_ change: Change) -> Bool {
        return handleKeyUp(change, nextState: .firstUp)
    }

    private func handleFirstUp(_ change: Change) -> Bool {
        guard eventIsTimely else {
            DLog("\(self.it_addressString): Switch to ground state and handle change again.")
            state = .ground
            return handleGround(change)
        }
        guard change.anyModifierIsPressed else {
            // Uninteresting event like Fn
            return false
        }
        guard change.onlyActivationModifierIsPressed else {
            // Pressed some other modifier
            state = .ground
            return false
        }
        state = .secondDown
        return false
    }

    private func handleSecondDown(_ change: Change) -> Bool {
        return handleKeyUp(change, nextState: nil)
    }

    private var eventIsTimely: Bool {
        let now = NSDate.it_timeSinceBoot()
        let elapsed = now - lastChange
        let minDelay = iTermAdvancedSettingsModel.hotKeyDoubleTapMinDelay()
        let maxDelay = iTermAdvancedSettingsModel.hotKeyDoubleTapMaxDelay()
        let allowed = minDelay..<max(minDelay, maxDelay)
        DLog("\(self.it_addressString): elapsed=\(elapsed) allowed=\(allowed)")
        return allowed.contains(elapsed)
    }
}
