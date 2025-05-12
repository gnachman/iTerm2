//
//  TwoTierTokenQueue.swift
//  iTerm2
//
//  Created by George Nachman on 5/11/25.
//

// This contains either a non-empty list of TokenArrays which are coalescable or exactly one
// TokenArray which is not coalescable.
class TokenArrayGroup {
    let arrays: [TokenArray]
    let length: Int
    var isEmpty: Bool {
        return arrays.isEmpty
    }
    let coalescable: Bool
    init(_ arrays: [TokenArray], coalescable: Bool, length: Int) {
        self.arrays = arrays
        self.coalescable = coalescable
        self.length = length
    }
    private var gang: VT100Token {
        it_assert(coalescable)
        let gang = VT100Token()
        gang.type = VT100_GANG
        gang.subtokens = arrays.flatMap { tokenArray in
            tokenArray.peekRemaining
        }
        return gang
    }
    var peek: VT100Token? {
        if isEmpty {
            return nil
        }
        if coalescable {
            return gang
        }
        it_assert(arrays.count == 1)
        return arrays[0].peek
    }
    func consume() -> Bool {
        if coalescable {
            for array in arrays {
                _ = array.consume()
            }
            return false
        }
        return arrays[0].consume()
    }
}

class TwoTierTokenQueue {
    static let numberOfPriorities = 2

    private lazy var queues: [Queue] = {
        (0..<TwoTierTokenQueue.numberOfPriorities).map { _ in Queue() }
    }()

    private var nextQueueAndTokenArray: (Queue, TokenArray, Int)? {
        for (i, queue) in queues.enumerated() {
            if let tokenArray = queue.first {
                return (queue, tokenArray, i)
            }
        }
        return nil
    }

    private var nextQueueAndTokenArrayGroup: (Queue, TokenArrayGroup, Int)? {
        for (i, queue) in queues.enumerated() {
            if let group = queue.firstGroup {
                return (queue, group, i)
            }
        }
        return nil
    }

    var isEmpty: Bool {
        return queues.allSatisfy {
            $0.isEmpty
        }
    }

    // Used to hold on to unused arrays so they can be cleaned up in another queue to reduce latency.
    private var garbage: [TokenArray] = []

    // Closure returns false to stop, true to keep going
    func enumerateTokenArrayGroups(_ closure: (TokenArrayGroup, Int) -> Bool) {
        if gDebugLogging.boolValue {
            DLog("Begin number remaining=\(queues.map { $0.totalNumberRemaining })")
        }
        while let tuple = nextQueueAndTokenArrayGroup {
            let (queue, tokenArrayGroup, priority) = tuple
            let shouldContinue = closure(tokenArrayGroup, priority)
            for tokenArray in tokenArrayGroup.arrays {
                if !tokenArray.hasNext {
                    if gDebugLogging.boolValue {
                        DLog("Token array fully consumed")
                    }
                    tokenArray.didFinish()
                    garbage.append(tokenArray)
                    queue.removeFirst()
                }
            }
            if !shouldContinue {
                if gDebugLogging.boolValue {
                    DLog("Stopping early with number remaining=\(queues.map { $0.totalNumberRemaining })")
                }
                break
            }
        }
        if garbage.count >= 16 {
            let arrays = garbage
            garbage = []
            TokenArray.destroyQueue.async {
                for array in arrays {
                    array.cleanup(asyncFree: false)
                }
            }
        }
    }

    var hasHighPriorityToken: Bool {
        return !queues[0].isEmpty
    }

    func removeAll() {
        DLog("remove all")
        for i in 0..<queues.count {
            queues[i].removeAll()
        }
    }

    func addTokens(_ tokenArray: TokenArray, highPriority: Bool) {
        if gDebugLogging.boolValue {
            DLog("add \(tokenArray.count) tokens, highpri=\(highPriority)")
        }
        queues[highPriority ? 0 : 1].append(tokenArray)
    }
}

fileprivate class Queue: CustomDebugStringConvertible {
    var debugDescription: String {
        return arrays.map {
            "--BEGIN ARRAY--\n" + $0.debugDescription + "\n--END ARRAY--"
        }.joined(separator: "\n\n")
    }
    private let mutex = Mutex()
    private var arrays = [TokenArray]()

    var first: TokenArray? {
        mutex.sync {
            return arrays.first
        }
    }

    var firstGroup: TokenArrayGroup? {
        return mutex.sync {
            guard let firstArray = arrays.first else {
                return nil
            }
            var result = [TokenArray]()
            var length = 0
            for i in 0..<arrays.count {
                if !arrays[i].canCoalesce(withNext: arrays[safe: i + 1]?.peek) {
                    break
                }
                result.append(arrays[i])
                length += arrays[i].length
            }
            return if result.isEmpty {
                TokenArrayGroup([firstArray], coalescable: false, length: firstArray.length)
            } else {
                TokenArrayGroup(result, coalescable: true, length: length)
            }
        }
    }

    func removeFirst() {
        mutex.sync {
            guard !arrays.isEmpty else {
                return
            }
            arrays.removeFirst()
        }
    }

    func removeFirst(_ n: Int) {
        mutex.sync {
            guard !arrays.isEmpty else {
                return
            }
            arrays.removeFirst(n)
        }
    }

    func removeAll() {
        mutex.sync {
            arrays.removeAll()
        }
    }

    func append(_ tokenArray: TokenArray) {
        mutex.sync {
            arrays.append(tokenArray)
        }
    }

    var isEmpty: Bool {
        mutex.sync {
            return arrays.isEmpty
        }
    }

    var totalNumberRemaining: Int {
        mutex.sync {
            return arrays.map { Int($0.numberRemaining) }.reduce(0, +)
        }
    }
}
