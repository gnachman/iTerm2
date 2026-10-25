//
//  ByteBudget.swift
//  iTerm2
//
//  Counts bytes that have been produced but not yet consumed, so a producer that can't be blocked
//  can still be slowed down at its source. A tmux gateway's pane sessions take bytes as they queue
//  %output for their tasks and give them back as the tasks read it. While the count is at capacity,
//  the gateway stops reading from tmux, which is the backpressure a pipe per pane used to provide.
//

import Foundation

@objc(iTermByteBudget)
final class ByteBudget: NSObject {
    private struct State {
        var inUse = 0
        var capacityAvailableHandler: (queue: DispatchQueue, block: () -> Void)?
    }
    private let state = MutableAtomicObject(State())
    private let capacity: Int
    // The capacity-available handler runs once usage is at or below this.
    private let lowWatermark: Int

    @objc
    init(capacity: Int) {
        self.capacity = max(1, capacity)
        lowWatermark = self.capacity / 2
    }

    override var description: String {
        let inUse = state.access { $0.inUse }
        return "<ByteBudget: \(Unmanaged.passUnretained(self).toOpaque()) \(inUse)/\(capacity)>"
    }

    // Any thread.
    var inUse: Int {
        return state.access { $0.inUse }
    }

    // Any thread. Whether usage is below capacity.
    @objc var hasCapacity: Bool {
        return state.access { $0.inUse < capacity }
    }

    // Any thread. Never blocks, and may take usage past capacity.
    func take(_ count: Int) {
        it_assert(count >= 0, "Negative count \(count)")
        state.mutableAccess { $0.inUse += count }
    }

    // Any thread. Returns bytes taken by take(_:).
    func give(_ count: Int) {
        it_assert(count >= 0, "Negative count \(count)")
        state.mutableAccess { state in
            it_assert(state.inUse >= count, "Gave back \(count) but only \(state.inUse) were taken")
            state.inUse -= count
            dispatchHandlerIfBelowWatermark(&state)
        }
    }

    // Any thread. Runs `block` asynchronously on `queue` once usage drops to the low watermark, or
    // right away if it is already there. Bytes are given back with locks held, so the block is
    // never called inline.
    //
    // Only one block is kept. Registering another runs the pending one right away, so a block may
    // run while there is still no capacity and must check again.
    @objc(notifyWhenCapacityAvailableOnQueue:block:)
    func notifyWhenCapacityAvailable(on queue: DispatchQueue, _ block: @escaping () -> Void) {
        state.mutableAccess { state in
            if let previous = state.capacityAvailableHandler {
                previous.queue.async(execute: previous.block)
            }
            state.capacityAvailableHandler = (queue, block)
            dispatchHandlerIfBelowWatermark(&state)
        }
    }

    // Any thread. Runs the pending block, if any, now. Call this when something besides usage
    // changes whether the waiting reader may read, so it checks again.
    @objc
    func wake() {
        state.mutableAccess { state in
            guard let handler = state.capacityAvailableHandler else {
                return
            }
            state.capacityAvailableHandler = nil
            handler.queue.async(execute: handler.block)
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
