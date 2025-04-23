//
//  DeltaString.swift
//  StyleMap
//
//  Created by George Nachman on 4/21/25.
//

import Foundation

@objc
class DeltaString: NSObject {
    @objc let unsafeString: NSString  // fast but lifetime-limited by this DeltaString object
    @objc var string: NSString { unsafeString.copy() as! NSString }
    @objc let length: CInt

    // 1:1 with UTF-16 codepoints in `string`
    @objc var deltas: UnsafePointer<CInt> { UnsafePointer(deltasStore) }

    private let deltasStore: UnsafeMutablePointer<CInt>
    private let backingStore: UnsafeMutablePointer<unichar>?

    /// replace all your old inits with this single one:
    @objc
    init(string: NSString,
         length: CInt,
         deltasStore: UnsafeMutablePointer<CInt>,
         backingStore: UnsafeMutablePointer<unichar>?)
    {
        self.unsafeString = string
        self.length = length
        self.deltasStore = deltasStore
        self.backingStore = backingStore
        super.init()
    }

    deinit {
        free(deltasStore)
        free(backingStore)
    }
}

@objc
class DeltaStringBuilder: NSObject {
    private let length: CInt
    private let utf16Cap: Int
    private var deltaPtr: UnsafeMutablePointer<CInt>?
    private var uniPtr: UnsafeMutablePointer<unichar>?
    private var deltaIdx = 0
    private var uniIdx = 0
    private var runningΔ = 0
    private let maxParts = 20

    /// Pre-allocate both buffers.
    init(count: CInt) {
        length = count
        utf16Cap = Int(count) * maxParts + 1
        let padded = count + 1
        // malloc so DeltaString can free()
        let dBytes = Int(padded) * MemoryLayout<CInt>.size
        deltaPtr = UnsafeMutableRawPointer(malloc(dBytes))!
            .bindMemory(to: CInt.self, capacity: Int(padded))
        uniPtr   = UnsafeMutableRawPointer(
            malloc(utf16Cap * MemoryLayout<unichar>.size)
        )!.bindMemory(to: unichar.self, capacity: utf16Cap)
    }

    deinit {
        free(deltaPtr)
        free(uniPtr)
    }

    /// append exactly one ASCII chunk
    func append(ascii data: SubData) {
        let bytes = data.data
        for b in bytes {
            uniPtr![uniIdx] = unichar(b)
            deltaPtr![deltaIdx] = 0
            uniIdx += 1
            deltaIdx += 1
        }
    }

    /// append codes+complex exactly as before, carrying the running `delta` across chunks
    func append(codes: [UInt16], complex: IndexSet, range: NSRange) {
        let start = range.location
        let count = range.length

        for offset in 0..<count {
            let i = start + offset
            let code = codes[i]
            let isComplexChar = complex.contains(i)

            // private‑use handling
            if !isComplexChar
                && (UInt16(ITERM2_PRIVATE_BEGIN)...UInt16(ITERM2_PRIVATE_END)).contains(code)
            {
                runningΔ += 1
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                continue
            }

            if let partNS = ComplexCharRegistry.instance.string(for: code, isComplex: isComplexChar) {
                let part = partNS as String
                let utf16Len = part.utf16.count
                runningΔ += 1
                runningΔ -= utf16Len
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                for cu in part.utf16 {
                    uniPtr![uniIdx] = cu
                    uniIdx += 1
                }
            } else {
                runningΔ += 1
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                uniPtr![uniIdx] = unichar(code)
                uniIdx += 1
            }
        }

        deltaIdx += count
    }

    func append(char: screen_char_t, repeated count: Int) {
        let code = char.code
        let isComplexChar = char.complexChar != 0
        var partNS: NSString?
        if isComplexChar {
            partNS = ComplexCharRegistry.instance.string(for: code, isComplex: isComplexChar)
        }
        for offset in 0..<count {
            let i = offset

            // private‑use handling
            if !isComplexChar
                && (UInt16(ITERM2_PRIVATE_BEGIN)...UInt16(ITERM2_PRIVATE_END)).contains(code)
            {
                runningΔ += 1
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                continue
            }

            if let partNS {
                let part = partNS as String
                let utf16Len = part.utf16.count
                runningΔ += 1
                runningΔ -= utf16Len
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                for cu in part.utf16 {
                    uniPtr![uniIdx] = cu
                    uniIdx += 1
                }
            } else {
                runningΔ += 1
                deltaPtr![deltaIdx + offset] = CInt(runningΔ)
                uniPtr![uniIdx] = unichar(code)
                uniIdx += 1
            }
        }

        deltaIdx += count
    }
    /// once you’ve appended *exactly* `deltaCount` entries and `utf16Cap` code units,
    /// tear down the builder and hand off ownership of both buffers to DeltaString
    func build() -> DeltaString {
        precondition(deltaIdx <= utf16Cap)
        precondition(uniIdx <= utf16Cap)
        precondition(deltaIdx == uniIdx)

        // make NSString *without* copying or free‐on‐dealloc
        let ns = NSString(
            charactersNoCopy: uniPtr!,
            length: uniIdx,
            freeWhenDone: false
        )
        // steal the pointers
        let dp = deltaPtr!
        let up = uniPtr!

        // prevent our deinit from freeing them
        deltaPtr = nil
        uniPtr   = nil

        return DeltaString(
            string: ns,
            length: length,
            deltasStore: dp,
            backingStore: up
        )
    }

    func append(chars: UnsafePointer<screen_char_t>, count: CInt) {
        let n = Int(count)
        let privateRange = UInt16(ITERM2_PRIVATE_BEGIN)...UInt16(ITERM2_PRIVATE_END)
        for i in 0..<n {
            var cell = chars[i]
            let code = cell.code
            let isComplex = cell.complexChar != 0
            let isImage = cell.image != 0

            if isImage ||
                (!isComplex && privateRange.contains(code)) {
                // Skip private-use characters which signify things like double-width characters and
                // tab fillers.
                runningΔ += 1
                continue
            }

            let len = ExpandScreenChar(&cell, uniPtr!.advanced(by: uniIdx))
            uniIdx += Int(len)
            runningΔ += 1
            for _ in 0..<len {
                runningΔ -= 1
                it_assert(deltaIdx < length)
                deltaPtr![deltaIdx] = CInt(runningΔ)
                deltaIdx += 1
            }
        }
        it_assert(deltaIdx <= length)
        deltaPtr![deltaIdx] = CInt(runningΔ)
    }
}
