//
//  TokenBudget.swift
//  iTerm2
//
//  Limits how many token arrays read from the pty a TokenExecutor buffers. Each array holds a slot
//  from when it is added until it has been executed or discarded. A reader either blocks until a
//  slot is free (acquire) or checks first and asks to be told when there is room again.
//

import Foundation

final class TokenBudget {
    private struct State {
        var inUse = 0
        var capacityAvailableHandler: (queue: DispatchQueue, block: () -> Void)?
    }
    private let state = ConditionVariable(State())
    private let capacity: Int
    // The capacity-available handler fires once usage is at or below this.
    private let lowWatermark: Int

    init(capacity: Int) {
        // A capacity of zero would block forever.
        self.capacity = max(1, capacity)
        lowWatermark = self.capacity / 2
    }

    // Any thread. Whether a slot is free right now.
    var hasCapacity: Bool {
        return state.sync { $0.inUse < capacity }
    }

    // Any thread. Blocks until a slot is free, then takes it.
    func acquire() {
        state.wait { state -> Void? in
            guard state.inUse < capacity else {
                return nil
            }
            state.inUse += 1
            return ()
        }
    }

    // Any thread. Takes a slot if one is free. Never blocks.
    func tryAcquire() -> Bool {
        return state.sync { state in
            guard state.inUse < capacity else {
                return false
            }
            state.inUse += 1
            return true
        }
    }

    // Any thread. Frees a slot taken by acquire() or tryAcquire().
    func release() {
        // mutate signals, waking a thread blocked in acquire().
        state.mutate { state in
            it_assert(state.inUse > 0, "Released more slots than were acquired")
            state.inUse -= 1
            dispatchHandlerIfBelowWatermark(&state)
        }
    }

    // Any thread. Runs `block` asynchronously on `queue` once usage drops to the low watermark, or
    // right away if it is already there. Releases happen while the executor holds locks and in the
    // middle of executing tokens, so the block is never called inline.
    //
    // Only one block is kept. Registering another runs the pending one right away, so a block may
    // run while there is still no capacity and must check again. A reader that stopped (such as a
    // session's previous task) can leave a block behind, and the next reader must not be stranded
    // by it.
    func notifyWhenCapacityAvailable(on queue: DispatchQueue, _ block: @escaping () -> Void) {
        state.sync { state in
            if let previous = state.capacityAvailableHandler {
                previous.queue.async(execute: previous.block)
            }
            state.capacityAvailableHandler = (queue, block)
            dispatchHandlerIfBelowWatermark(&state)
        }
    }

    // Call with the state locked.
    private func dispatchHandlerIfBelowWatermark(_ state: inout State) {
        guard state.inUse <= lowWatermark, let handler = state.capacityAvailableHandler else {
            return
        }
        state.capacityAvailableHandler = nil
        handler.queue.async(execute: handler.block)
    }
}
