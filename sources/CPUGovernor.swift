//
//  CPUGovernor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/4/21.
//

import Foundation

private class AtomicFlag {
    private var _value: Bool
    private let queue = DispatchQueue(label: "com.iterm2.atomic-flag")

    var value: Bool {
        get {
            return queue.sync { return _value }
        }
        set {
            queue.sync { _value = newValue }
        }
    }

    init(_ value: Bool) {
        self._value = value
    }
}

@objc(iTermCPUGovernor) public class CPUGovernor: NSObject {
    @objc public var pid: pid_t {
        willSet {
            if newValue != pid {
                DLog("pid will change")
                invalidate()
            }
        }
        didSet {
            DLog("pid=\(pid)")
        }
    }

    // Time running / time suspended
    private let dutyCycle: Double

    private let queue = DispatchQueue(label: "com.iterm2.cpu-governor")
    private var running = AtomicFlag(false)

    // Amount of time in a suspend-wait-resume-wait cycle.
    private let cycleTime = 0.1

    // Outstanding tokens.
    private var tokens = Set<Int>()
    private var nextToken = 0

    @objc(initWithPID:dutyCycle:) public init(_ pid: pid_t, dutyCycle: Double) {
        self.pid = pid
        self.dutyCycle = dutyCycle
    }

    @objc public func incr() -> Int {
        let token = nextToken
        nextToken += 1
        precondition(!tokens.contains(token))
        tokens.insert(token)
        update()
        DLog("Allocate token \(token) giving \(tokens)")
        return token
    }

    @objc(decr:) public func decr(_ token: Int) {
        guard tokens.remove(token) != nil else {
            DLog("Deallocate already-removed token \(token)")
            return
        }
        DLog("Deallocate token \(token) giving \(tokens)")
        update()
    }

    @objc public func invalidate() {
        DLog("Invalidate")
        tokens.removeAll()
        guard running.value else {
            return
        }
        update()
    }

    private func update() {
        if tokens.isEmpty && running.value {
            stop()
        } else if !tokens.isEmpty && !running.value {
            start()
        }
    }

    private func start() {
        guard !running.value else {
            return
        }
        DLog("running=true")
        running.value = true
        queue.async { [weak self] in
            self?.mainloop()
        }
    }

    private func stop() {
        guard running.value else {
            return
        }
        DLog("running=false")
        running.value = false
    }

    private var processTerminated: Bool {
        return kill(pid, 0) != 0
    }

    private func mainloop() {
        dispatchPrecondition(condition: .onQueue(queue))

        DLog("Start mainloop")
        while running.value && !processTerminated {
            cycle()
        }
        DLog("Return from mainloop")
    }

    private func cycle() {
        DLog("Cycle")
        suspend()
        sleepWhileSuspended()

        if processTerminated {
            return
        }

        resume()
        sleepWhileRunning()
    }

    private func suspend() {
        DLog("Suspend \(pid)")
        kill(pid, SIGTSTP)
    }

    private func resume() {
        DLog("Resume \(pid)")
        kill(pid, SIGCONT)
    }

    private func sleepWhileSuspended() {
        sleep(1)
    }

    private func sleepWhileRunning() {
        sleep(dutyCycle)
    }

    private func sleep(_ multiplier: TimeInterval) {
        let coeff = cycleTime / (dutyCycle + 1)
        DLog("Sleep for \(multiplier) units of \(coeff) sec = \(coeff * multiplier)")
        Thread.sleep(forTimeInterval: coeff * multiplier)
    }
}
