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

    convenience init(_ decoder: inout EfficientDecoder, placeholder: T) throws {
        let count: Int = try decoder.getScalar()
        let possiblyUndersizedArray: [T] = try decoder.getArray()
        if possiblyUndersizedArray.count > count {
            throw EfficientDecoderError()
        }
        let array = possiblyUndersizedArray + Array<T>(repeating: placeholder,
                                                       count: count - possiblyUndersizedArray.count)
        self.init(count: array.count)
        let byteCount = array.count * MemoryLayout<T>.stride
        _ = array.withUnsafeBytes { arrayUnsafeBytes in
            arrayUnsafeBytes.baseAddress!.withMemoryRebound(to: T.self, capacity: array.count) { arrayPointer in
                buffer.baseAddress!.withMemoryRebound(to: T.self, capacity: array.count) { destinationBytes in
                    memcpy(destinationBytes, arrayPointer, byteCount)
                }
            }
        }
    }

    func encode(_ encoder: inout EfficientEncoder, maxSize: Int) {
        encoder.putScalar(count)
        var array = Array(buffer)[0..<maxSize]
        encoder.putArray(&array)
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

class EfficientDecoderError: Error {
}

struct EfficientDecoder {
    private let data: Data
    private var offset = 0

    var bytesRemaining: Int { data.count - offset }

    init(_ data: Data) {
        self.data = data
    }

    mutating func getScalar<T>() throws -> T {
        let size = MemoryLayout<T>.stride
        if data.count < size {
            throw EfficientDecoderError()
        }
        defer {
            offset += size
        }
        let result = data.withUnsafeBytes { pointer in
            return pointer.baseAddress!.advanced(by: offset).assumingMemoryBound(to: T.self).pointee
        }
        return result
    }

    mutating func getScalar() throws -> Data {
        let count: Int = try getScalar()
        if count <= 0 {
            throw EfficientDecoderError()
        }
        var data = Data(count: count)
        data.withUnsafeMutableBytes { mutableRawBufferPointer in
            self.data.subdata(in: offset..<(offset + count)).withUnsafeBytes { unsafeRawBufferPointer in
                _ = memcpy(mutableRawBufferPointer.baseAddress!, unsafeRawBufferPointer.baseAddress!, count)
            }
        }
        offset += count
        return data
    }

    mutating func getArray<T>() throws -> [T] {
        let count: Int32 = try getScalar()
        let lengthInBytes = Int(count) * MemoryLayout<T>.stride
        if offset < 0 {
            throw EfficientDecoderError()
        }
        if offset + lengthInBytes > data.count {
            throw EfficientDecoderError()
        }
        let subdata = data.subdata(in: offset..<(offset + lengthInBytes))
        defer {
            offset += lengthInBytes
        }
        return subdata.withUnsafeBytes {
            (pointer: UnsafeRawBufferPointer) -> [T] in
            let buffer = UnsafeBufferPointer<T>(start: pointer.baseAddress!.assumingMemoryBound(to: T.self),
                                                count: Int(count))
            return Array<T>(buffer)
        }
    }
}

struct EfficientEncoder {
    private(set) var data = Data()

    mutating func putScalar<T>(_ value: T) {
        var temp = value
        withUnsafeBytes(of: &temp) { pointer in
            data.append(Data(pointer))
        }
    }

    mutating func putScalar(_ value: Data) {
        putScalar(value.count)
        self.data.append(value)
    }

    mutating func putArray<T>(_ value: inout [T]) {
        putScalar(Int32(value.count))
        value.withUnsafeBufferPointer { temp in
            data.append(temp)
        }
    }

    mutating func putArray<T>(_ value: inout ArraySlice<T>) {
        putScalar(Int32(value.count))
        value.withUnsafeBufferPointer { temp in
            data.append(temp)
        }
    }
}

fileprivate enum Buffer: Equatable {
    case uninitialized
    case uncompressed(UnsafeReallocatableMutableBuffer<screen_char_t>)

    private enum EncoderKeys: UInt8 {
        case uninitialized = 0
        case uncompressed = 1
    }

    func clone() -> Buffer {
        switch self {
        case .uninitialized:
            return self
        case .uncompressed(let buffer):
            return .uncompressed(buffer.clone())
        }
    }

    static func == (lhs: Buffer, rhs: Buffer) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized):
            return true
        case let (.uncompressed(lvalue), .uncompressed(rvalue)):
            return lvalue == rvalue
        default:
            return false
        }
    }

    func encode(_ encoder: inout EfficientEncoder, maxSize: Int) {
        switch self {
        case .uninitialized:
            encoder.putScalar(EncoderKeys.uninitialized.rawValue)
        case .uncompressed(let chars):
            encoder.putScalar(EncoderKeys.uncompressed.rawValue)
            chars.encode(&encoder, maxSize: maxSize)
        }
    }

    init(_ decoder: inout EfficientDecoder) throws {
        switch EncoderKeys(rawValue: try decoder.getScalar()) {
        case .uninitialized:
            self = .uninitialized
        case .uncompressed:
            self = .uncompressed(try UnsafeReallocatableMutableBuffer(&decoder, placeholder: screen_char_t()))
        case .none:
            throw EfficientDecoderError()
        }
    }

    var debugDescription: String {
        switch self {
        case .uninitialized:
            return "[uninitialized]"
        case .uncompressed(let buffer):
            return buffer.debugDescription
        }
    }

    var shortDebugDescription: String {
        switch self {
        case .uninitialized:
            return "[uninitialized]"
        case .uncompressed(let buffer):
            return buffer.shortDebugDescription
        }
    }
}

@objc(iTermCompressibleCharacterBuffer)
class CompressibleCharacterBuffer: NSObject {
    override var debugDescription: String {
        return "<\(type(of: self)): \(it_addressString) size=\(size) “\(buffer.shortDebugDescription)”>"
    }
    private var buffer: Buffer = .uninitialized
    @objc private(set) var size: Int

    @objc
    init(_ size: Int) {
        self.size = size
    }

    @objc(initWithUncompressedData:)
    init?(uncompressed data: Data) {
        size = data.count / MemoryLayout<screen_char_t>.stride
        buffer = .uncompressed(UnsafeReallocatableMutableBuffer(data))

        super.init()
    }

    @objc(initWithEncodedData:)
    init?(encoded data: Data) {
        var decoder = EfficientDecoder(data)
        do {
            size = try decoder.getScalar()
            buffer = try Buffer(&decoder)
        } catch {
            return nil
        }
    }
    
    private init(from other: CompressibleCharacterBuffer) {
        self.size = other.size
        self.buffer = other.buffer.clone()
    }

    @objc(encodedDataWithMaxSize:)
    func encodedData(maxSize: Int) -> Data {
        var encoded = EfficientEncoder()
        encoded.putScalar(size)
        buffer.encode(&encoded, maxSize: maxSize)
        return encoded.data
    }

    @objc
    var mutablePointer: UnsafeMutablePointer<screen_char_t> {
        switch buffer {
        case .uninitialized:
            return realize().buffer.baseAddress!
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
        case .uninitialized:
            break
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

    private func realize() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        let underlying = UnsafeReallocatableMutableBuffer<screen_char_t>(count: size)
        buffer = .uncompressed(underlying)
        return underlying
    }

}
