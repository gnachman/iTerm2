//
//  ProducerConsumerQueue.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

class ProducerConsumerQueue<T> {
    private let cond = ConditionVariable([T]())

    func produce(_ value: T) {
        cond.mutate { queue in
            queue.append(value)
        }
    }

    func blockingConsume() -> T {
        return cond.wait { queue in
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            return nil
        }
    }

    func tryConsume() -> T? {
        return cond.sync { queue in
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            return nil
        }
    }

    func peek() -> T? {
        cond.sync { queue in
            queue.first
        }
    }

    var count: Int {
        cond.sync { queue in
            queue.count
        }
    }
}

