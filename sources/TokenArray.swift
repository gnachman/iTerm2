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
    let lengthTotal: Int
    let lengthExcludingInBandSignaling: Int
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

    func canCoalesce(withNext nextToken: VT100Token?) -> Bool {
        if count <= nextIndex {
            return true
        }
        if !(nextIndex..<(count - 1)).allSatisfy({
            let type = CVectorGetVT100Token(&cvector, $0).type
            return type == VT100_ASCIISTRING || type == VT100_MIXED_ASCII_CR_LF || type == VT100_GANG
        }) {
            return false
        }
        let type = CVectorGetVT100Token(&cvector, count - 1).type
        if type == VT100_ASCIISTRING || type == VT100_MIXED_ASCII_CR_LF || type == VT100_GANG {
            return true
        }
        // The TTY driver will sometimes emit two consecutive CRs when `onlcr` is on and it happens
        // on the boundary of a read. The telltale is a 1024-byte read that ends with a CR and the
        // next read begins with CR LF. Consecutive CRs are harmless for the purposes of coalescing
        // tokens into a group. The consumer can simply ignore any VT100_CR tokens.
        return type == VT100CC_CR && (nextToken?.type == VT100_MIXED_ASCII_CR_LF &&
                                      nextToken?.asciiData.pointee.buffer[0] == 13)
    }

    // length is byte length ofinputs
    init(_ cvector: CVector,
         lengthTotal: Int,
         lengthExcludingInBandSignaling: Int,
         semaphore: DispatchSemaphore?) {
        precondition(lengthTotal > 0 && lengthExcludingInBandSignaling >= 0)
        self.cvector = cvector
        self.lengthTotal = lengthTotal
        self.lengthExcludingInBandSignaling = lengthExcludingInBandSignaling
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

    func cleanup(asyncFree: Bool) {
        guard dirty else {
            return
        }
        dirty = false
        semaphore?.signal()
        if asyncFree {
            TokenArray.destroyQueue.async { [cvector] in
                CVectorReleaseObjectsAndDestroy(cvector)
            }
        } else {
            CVectorReleaseObjectsAndDestroy(cvector)
        }
    }

    func replaceLast(with replacement: VT100Token) {
        let count = CVectorCount(&cvector)
        it_assert(count > 0)
        CVectorSetVT100Token(&cvector, count - 1, replacement)
    }

    deinit {
        cleanup(asyncFree: true)
    }
}
