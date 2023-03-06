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

struct CompressedScreenCharBuffer: Equatable, CustomDebugStringConvertible {
    var debugDescription: String {
        return runs.map { run in
            run.debugDescription
        }.joined()
    }

    var shortDebugDescription: String {
        let full = debugDescription
        let maxLength = 16
        return String(full.prefix(maxLength)) + (full.count > maxLength ? "…" : "")
    }

    struct Run: Equatable {
        var base: screen_char_t
        var codes: [unichar]
        func expand(to destination: UnsafeMutablePointer<screen_char_t>,
                    spaceRemaining: Int) {
            for (i, code) in codes[0..<min(codes.count, spaceRemaining)].enumerated() {
                var c = base
                c.code = code
                destination[i] = c
            }
        }

        mutating func encode(_ encoder: inout EfficientEncoder) {
            encoder.putScalar(base)
            encoder.putArray(&codes)
        }

        init(_ efficientDecoder: inout EfficientDecoder) throws {
            base = try efficientDecoder.getScalar()
            codes = try efficientDecoder.getArray()
        }

        init(base: screen_char_t, codes: [unichar]) {
            self.base = base
            self.codes = codes
        }

        var debugDescription: String {
            if base.image != 0 {
                return Array(repeating: "🌆", count: codes.count).joined()
            }
            return codes.compactMap {
                var temp = base
                temp.code = $0
                return ScreenCharToStr(&temp)
            }.joined()
        }
    }

    // Number of elements when decompressed.
    let count: Int
    let runs: [Run]

    func decompressed() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        let buffer = UnsafeReallocatableMutableBuffer<screen_char_t>(count: count)
        var offset = 0
        for run in runs {
            precondition(count >= offset)
            run.expand(to: buffer.buffer.baseAddress!.advanced(by: offset),
                       spaceRemaining: count - offset)
            offset += run.codes.count
        }
        return buffer
    }

    init(_ buffer: UnsafeReallocatableMutableBuffer<screen_char_t>, size: Int) {
        var base: screen_char_t? = nil
        var runs = [Run]()
        for c in buffer.buffer[..<size] {
            if let base,
               ScreenCharacterAttributesEqual(base, c),
               base.complexChar == c.complexChar {
                // Add to an existing run
                runs[runs.count - 1].codes.append(c.code)
                continue
            }
            // Start a new run
            runs.append(Run(base: c, codes: [c.code]))
            base = c
        }
        self.runs = runs
        count = size
    }

    static func == (lhs: CompressedScreenCharBuffer, rhs: CompressedScreenCharBuffer) -> Bool {
        return lhs.count == rhs.count && lhs.runs == rhs.runs
    }

    func encode(_ encoder: inout EfficientEncoder) {
        encoder.putScalar(count)
        encoder.putScalar(runs.count)
        for var run in runs {
            run.encode(&encoder)
        }
    }

    init(_ decoder: inout EfficientDecoder) throws {
        count = try decoder.getScalar()
        let numRuns: Int = try decoder.getScalar()
        var runs = [Run]()
        for _ in 0..<numRuns {
            runs.append(try Run(&decoder))
        }
        self.runs = runs
    }
}

fileprivate enum Buffer: Equatable {
    case uninitialized
    case uncompressed(UnsafeReallocatableMutableBuffer<screen_char_t>)
    case compressed(CompressedScreenCharBuffer)

    private enum EncoderKeys: UInt8 {
        case uninitialized = 0
        case uncompressed = 1
        case compressed = 2
    }

    func clone() -> Buffer {
        switch self {
        case .uninitialized:
            return self
        case .compressed(let buffer):
            return .compressed(buffer)
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
        case let (.compressed(lvalue), .compressed(rvalue)):
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
        case .compressed(let compressed):
            encoder.putScalar(EncoderKeys.compressed.rawValue)
            compressed.encode(&encoder)
        }
    }

    init(_ decoder: inout EfficientDecoder) throws {
        switch EncoderKeys(rawValue: try decoder.getScalar()) {
        case .uninitialized:
            self = .uninitialized
        case .uncompressed:
            self = .uncompressed(try UnsafeReallocatableMutableBuffer(&decoder, placeholder: screen_char_t()))
        case .compressed:
            self = .compressed(try CompressedScreenCharBuffer(&decoder))
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
        case .compressed(let buffer):
            return buffer.debugDescription
        }
    }

    var shortDebugDescription: String {
        switch self {
        case .uninitialized:
            return "[uninitialized]"
        case .uncompressed(let buffer):
            return buffer.shortDebugDescription
        case .compressed(let buffer):
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
        case .compressed:
            return decompress().buffer.baseAddress!
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
        case .uninitialized, .compressed:
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

    @objc
    func compress(usedCount: Int) {
        switch buffer {
        case .uninitialized, .compressed:
            return
        case .uncompressed(let buffer):
            let compressedBuffer = CompressedScreenCharBuffer(buffer, size: usedCount)
            self.buffer = .compressed(compressedBuffer)
            size = compressedBuffer.count
        }
    }

    private func realize() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        let underlying = UnsafeReallocatableMutableBuffer<screen_char_t>(count: size)
        buffer = .uncompressed(underlying)
        return underlying
    }

    private func decompress() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        switch buffer {
        case .uninitialized:
            return realize()
        case .uncompressed(let buffer):
            return buffer
        case .compressed(let compressedBuffer):
            size = compressedBuffer.count
            DLog("Decompress \(self.debugDescription) to size \(size)")
            let decompressed = compressedBuffer.decompressed()
            buffer = .uncompressed(decompressed)
            return decompressed
        }
    }
}
