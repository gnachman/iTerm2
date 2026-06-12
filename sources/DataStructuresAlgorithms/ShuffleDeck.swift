import Foundation

/// Fair-random rotation through a list of strings. Each item is returned once
/// per cycle before any repeats; the order within a cycle is shuffled.
///
/// Usage:
///   deck.setPool(items)   // refresh the available items
///   deck.advance()        // move to the next item; read deck.current
///
/// When the internal queue runs out, a fresh cycle is shuffled in place
/// (excluding `current`, so you never get an immediate repeat across the
/// cycle boundary).
class ShuffleDeck {
    /// The item most recently returned by advance() — i.e. what is "in play."
    private(set) var current: String?

    /// The pool of all known items. Rebuilt from this whenever `upcoming`
    /// empties.
    private var pool: [String] = []

    /// Items queued to be returned by successive calls to advance(), in order.
    /// Always disjoint from `current`.
    private var upcoming: [String] = []

    /// Replace the pool of available items.
    ///
    /// - No-op when `items` equals the existing pool (common case: the folder
    ///   contents haven't changed since the last scan).
    /// - Drops removed items from `upcoming` and clears `current` if it is
    ///   no longer in the pool.
    /// - Does not add newly-discovered items to `upcoming`; they join the
    ///   next cycle when `advance()` reshuffles. This keeps all cycles
    ///   shuffled, including the first one.
    func setPool(_ items: [String]) {
        if items == pool {
            return
        }
        pool = items
        let poolSet = Set(items)
        if let c = current, !poolSet.contains(c) {
            current = nil
        }
        upcoming.removeAll { !poolSet.contains($0) }
    }

    /// Advance to the next item. Returns the new `current` (or nil if the
    /// pool is empty). If `upcoming` is exhausted, reshuffles the pool and,
    /// if the shuffle put `current` at the front, swaps it with the next
    /// item to avoid an immediate repeat across the cycle boundary. Every
    /// item appears exactly once per cycle.
    @discardableResult
    func advance() -> String? {
        if pool.isEmpty {
            current = nil
            upcoming = []
            return nil
        }
        if pool.count == 1 {
            current = pool.first
            upcoming = []
            return current
        }
        if upcoming.isEmpty {
            upcoming = pool
            upcoming.shuffle()
            if upcoming.first == current, upcoming.count > 1 {
                upcoming.swapAt(0, 1)
            }
        }
        current = upcoming.removeFirst()
        return current
    }
}
