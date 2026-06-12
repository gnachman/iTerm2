import Foundation

// Latches a session's password-input state. The conductor's at-password-prompt
// signal is authoritative and used immediately; the TTY-based heuristic
// (ECHO off + ICANON on) is debounced so a brief stty -echo by a shell script
// reading an OSC response doesn't trigger the password manager auto-show.
@objc(iTermPasswordInputDebouncer)
class iTermPasswordInputDebouncer: NSObject {
    @objc var onRecheck: (() -> Void)?

    private var detectedAt: TimeInterval = 0
    private var recheckScheduled = false

    @objc func debouncedState(ttyPasswordInput: Bool,
                              conductorPasswordInput: Bool) -> Bool {
        if conductorPasswordInput {
            detectedAt = 0
            return true
        }
        if !ttyPasswordInput {
            detectedAt = 0
            return false
        }
        let debounce = iTermAdvancedSettingsModel.detectPasswordInputDebounce()
        if debounce <= 0 {
            return true
        }
        let now = Date.timeIntervalSinceReferenceDate
        if detectedAt == 0 {
            detectedAt = now
        }
        let elapsed = now - detectedAt
        if elapsed >= debounce {
            return true
        }
        scheduleRecheck(after: debounce - elapsed)
        return false
    }

    private func scheduleRecheck(after delay: TimeInterval) {
        if recheckScheduled {
            return
        }
        recheckScheduled = true
        let slop = 0.01
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + slop) { [weak self] in
            guard let self else { return }
            self.recheckScheduled = false
            self.onRecheck?()
        }
    }
}
