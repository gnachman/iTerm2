//
//  TokenArray.swift
//  iTerm2
//
//  Created by George Nachman on 5/11/25.
//

class TokenArray: IteratorProtocol, CustomDebugStringConvertible {
    var debugDescription: String {
        var descr = [String]()
        for i in 0..<cvector.count {
            let token = CVectorGetObject(&cvector, i) as! VT100Token
            descr.append(token.description)
        }
        return descr.joined(separator: "\n")
    }

    typealias Element = VT100Token
    let length: Int
    private var cvector: CVector
    private var nextIndex = Int32(0)
    let count: Int32
    var numberRemaining: Int32 { count - nextIndex }
    static var destroyQueue: DispatchQueue = {
        return DispatchQueue(label: "com.iterm2.token-destroyer")
    }()
    private var semaphore: DispatchSemaphore?

    var hasNext: Bool {
        return nextIndex < count
    }

    var canCoalesce: Bool {
        (nextIndex..<count).allSatisfy {
            let type = CVectorGetVT100Token(&cvector, $0).type
            return type == VT100_ASCIISTRING || type == VT100_MIXED_ASCII_CR_LF || type == VT100_GANG
        }
    }

    // length is byte length ofinputs
    init(_ cvector: CVector, length: Int, semaphore: DispatchSemaphore?) {
        precondition(length > 0)
        self.cvector = cvector
        self.length = length
        self.semaphore = semaphore
        count = CVectorCount(&self.cvector)
    }

    func next() -> VT100Token? {
        guard hasNext else {
            return nil
        }
        defer {
            nextIndex += 1
            if nextIndex == count, let semaphore = semaphore {
                semaphore.signal()
                self.semaphore = nil
            }
        }
        return (CVectorGetObject(&cvector, nextIndex) as! VT100Token)
    }

    var peekRemaining: [VT100Token] {
        return (nextIndex..<count).map {
            CVectorGetVT100Token(&cvector, $0)
        }
    }

    // Returns the next token in the queue or nil if it is empty.
    var peek: VT100Token? {
        guard hasNext else {
            return nil
        }
        return CVectorGetVT100Token(&cvector, nextIndex)
    }

    // Returns whether there is another token.
    func consume() -> Bool {
        nextIndex += 1
        if nextIndex == count, let semaphore = semaphore {
            semaphore.signal()
            self.semaphore = nil
        }
        return hasNext
    }

    func skipToEnd() {
        DLog("skipToEnd")
        if nextIndex >= count {
            return
        }
        nextIndex = count
        if let semaphore = semaphore {
            semaphore.signal()
            self.semaphore = nil
        }
    }

    private var dirty = true

    func didFinish() {
        semaphore?.signal()
        semaphore = nil
    }

    func cleanup() {
        guard dirty else {
            return
        }
        dirty = false
        semaphore?.signal()
        CVectorReleaseObjectsAndDestroy(cvector)
    }

    func replaceLast(with replacement: VT100Token) {
        let count = CVectorCount(&cvector)
        it_assert(count > 0)
        CVectorSetVT100Token(&cvector, count - 1, replacement)
    }

    deinit {
        cleanup()
    }
}
