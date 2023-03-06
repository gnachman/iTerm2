//
//  CompressibleCharacterBuffer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/23.
//

import Foundation

class UnsafeReallocatableMutableBuffer<T: Equatable>: Equatable {
    private(set) var buffer: UnsafeMutableBufferPointer<T>
    var count: Int { buffer.count }

    init(count: Int) {
        precondition(count >= 0)
        let pointer = UnsafeMutableRawPointer(calloc(count, MemoryLayout<T>.stride))!
        buffer = UnsafeMutableBufferPointer<T>(start: pointer.assumingMemoryBound(to: T.self),
                                               count: count)
    }

    convenience init(copyingBytesFromAddress fromAddress: UnsafePointer<T>, count: Int) {
        self.init(count: count)
        memmove(buffer.baseAddress!, fromAddress, count * MemoryLayout<T>.stride)
    }

    convenience init(_ data: Data) {
        self.init(count: data.count / MemoryLayout<T>.stride)
        data.withUnsafeBytes { rawBufferPointer in
            let address = rawBufferPointer.assumingMemoryBound(to: screen_char_t.self).baseAddress!
            memmove(buffer.baseAddress!, address, count * MemoryLayout<T>.stride)
        }
    }

    deinit {
        let pointer = UnsafeMutableRawPointer(buffer.baseAddress)!
        Darwin.free(pointer)
    }

    func resize(to count: Int) {
        var pointer = UnsafeMutableRawPointer(buffer.baseAddress)!
        pointer = realloc(pointer, Int(count) * MemoryLayout<T>.stride)!
        buffer = UnsafeMutableBufferPointer<T>(
            start: pointer.assumingMemoryBound(to: T.self),
            count: Int(count))
    }

    func clone() -> UnsafeReallocatableMutableBuffer<T> {
        return UnsafeReallocatableMutableBuffer(copyingBytesFromAddress: buffer.baseAddress!,
                                                count: count)
    }

    static func == (lhs: UnsafeReallocatableMutableBuffer<T>, rhs: UnsafeReallocatableMutableBuffer<T>) -> Bool {
        return lhs.count == rhs.count && lhs.buffer.elementsEqual(rhs.buffer)
    }
}

extension UnsafeReallocatableMutableBuffer where T == screen_char_t {
    var debugDescription: String {
        return debugDescription(maxLength: Int.max)
    }

    var shortDebugDescription: String {
        return debugDescription(maxLength: 16)
    }

    private func debugDescription(maxLength: Int) -> String {
        return buffer.prefix(maxLength).map { c in
            if c.image != 0 {
                return "🌆"
            }
            var temp = c
            return ScreenCharToStr(&temp)
        }.joined() + (buffer.count > maxLength ? "…" : "")
    }
}

extension screen_char_t: Equatable {
    public static func == (lhs: screen_char_t, rhs: screen_char_t) -> Bool {
        var ltemp = lhs
        var rtemp = rhs
        return memcmp(&ltemp, &rtemp, MemoryLayout<screen_char_t>.size) == 0
    }
}

fileprivate enum Buffer: Equatable {
    case uncompressed(UnsafeReallocatableMutableBuffer<screen_char_t>)

    func clone() -> Buffer {
        switch self {
        case .uncompressed(let buffer):
            return .uncompressed(buffer.clone())
        }
    }

    static func == (lhs: Buffer, rhs: Buffer) -> Bool {
        switch (lhs, rhs) {
        case let (.uncompressed(lvalue), .uncompressed(rvalue)):
            return lvalue == rvalue
        default:
            return false
        }
    }
}

@objc(iTermCompressibleCharacterBuffer)
class CompressibleCharacterBuffer: NSObject {
    private var buffer: Buffer
    @objc private(set) var size: Int

    @objc
    init(_ size: Int) {
        self.size = size
        buffer = .uncompressed(UnsafeReallocatableMutableBuffer(count: size))
    }

    @objc(initWithUncompressedData:)
    init?(uncompressed data: Data) {
        size = data.count / MemoryLayout<screen_char_t>.stride
        buffer = .uncompressed(UnsafeReallocatableMutableBuffer(data))

        super.init()
    }

    private init(from other: CompressibleCharacterBuffer) {
        self.size = other.size
        self.buffer = other.buffer.clone()
    }

    @objc
    var mutablePointer: UnsafeMutablePointer<screen_char_t> {
        switch buffer {
        case .uncompressed(let buffer):
            return buffer.buffer.baseAddress!
        }
    }

    @objc
    var pointer: UnsafePointer<screen_char_t> {
        UnsafePointer(mutablePointer)
    }

    @objc
    func resize(_ newSize: Int) {
        let oldSize = size
        size = newSize
        switch buffer {
        case .uncompressed(let buffer):
            DLog("Resize \(buffer.shortDebugDescription) from \(oldSize) to \(newSize)")
            buffer.resize(to: newSize)
        }
    }

    @objc
    func clone() -> CompressibleCharacterBuffer {
        return CompressibleCharacterBuffer(from: self)
    }

    @objc
    func deepIsEqual(_ object: Any?) -> Bool {
        guard let other = object as? CompressibleCharacterBuffer else {
            return false
        }
        return self == other
    }

    static func == (lhs: CompressibleCharacterBuffer, rhs: CompressibleCharacterBuffer) -> Bool {
        return lhs.buffer == rhs.buffer && lhs.size == rhs.size
    }
}
