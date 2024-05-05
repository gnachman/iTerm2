//
//  CompressibleCharacterBuffer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/24/23.
//

import Foundation

class UnsafeReallocatableMutableBuffer<T: DefaultInitializable & Equatable>: Equatable {
    private(set) var buffer: UnsafeMutableBufferPointer<T>
    var count: Int { buffer.count }

    init(count: Int) {
        precondition(count >= 0)
        let pointer = UnsafeMutableRawPointer(calloc(max(1, count), MemoryLayout<T>.stride))!
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
        pointer = realloc(pointer, Int(max(1, count)) * MemoryLayout<T>.stride)!
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

protocol DefaultInitializable {
    init()
}

extension screen_char_t: DefaultInitializable {
    init() {
        self = screen_char_t(code: 0,
                             foregroundColor: 0,
                             fgGreen: 0,
                             fgBlue: 0,
                             backgroundColor: 0,
                             bgGreen: 0,
                             bgBlue: 0,
                             foregroundColorMode: 0,
                             backgroundColorMode: 0,
                             complexChar: 0,
                             bold: 0,
                             faint: 0,
                             italic: 0,
                             blink: 0,
                             underline: 0,
                             image: 0,
                             strikethrough: 0,
                             underlineStyle: .single,
                             invisible: 0,
                             inverse: 0,
                             guarded: 0,
                             unused: 0)
    }
}

extension Int: DefaultInitializable {
    init() {
        self = 0
    }
}

extension Int32: DefaultInitializable {
    init() {
        self = 0
    }
}

extension UInt8: DefaultInitializable {
    init() {
        self = 0
    }
}

extension unichar: DefaultInitializable {
    init() {
        self = 0
    }
}

struct EfficientDecoder {
    private let data: Data
    private var offset = 0

    var bytesRemaining: Int { data.count - offset }

    init(_ data: Data) {
        self.data = data
    }

    mutating func getScalar<T: DefaultInitializable>() throws -> T {
        let size = MemoryLayout<T>.stride
        if data.count + offset < size {
            throw EfficientDecoderError()
        }
        defer {
            offset += size
        }
        var result = T()
        _ = withUnsafeMutableBytes(of: &result) { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + size))
        }
        return result
    }

    mutating func getArray<T: DefaultInitializable>() throws -> [T] {
        let count: Int32 = try getScalar()
        let lengthInBytes = Int(count) * MemoryLayout<T>.stride
        if offset < 0 {
            throw EfficientDecoderError()
        }
        if offset + lengthInBytes > data.count {
            throw EfficientDecoderError()
        }
        defer {
            offset += lengthInBytes
        }
        var result = Array<T>(repeating: T(), count: Int(count))
        result.withUnsafeMutableBufferPointer { buffer in
            data.copyBytes(to: buffer, from: offset..<(offset + lengthInBytes))
        }
        return result
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

    func decompressed(capacity: Int) -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        let buffer = UnsafeReallocatableMutableBuffer<screen_char_t>(count: max(capacity, count))
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

    // This is used to optimize lookups for consecutive indexes by remembering which run the last one was in.
    private struct LookupCache {
        /// Desired index (linear, 0 to count-1)
        var i = 0
        /// Corresponding run index. Is always valid.
        var run = 0
        /// Corresponding offset within that run. Is always valid.
        var offset = 0
    }

    private var _lookupCache = LookupCache()

    subscript(_ i: Int) -> screen_char_t {
        mutating get {
            if i < _lookupCache.i {
                _lookupCache = LookupCache()
            }
            while _lookupCache.i <= i && _lookupCache.run < runs.count {
                let offset = i - _lookupCache.offset
                let run = runs[_lookupCache.run]
                if run.codes.count > offset {
                    var c = run.base
                    c.code = run.codes[offset]
                    return c
                }
                _lookupCache.offset += run.codes.count
                _lookupCache.run += 1
            }
            fatalError("Index \(i) out of bounds with \(_lookupCache.i) entries")
        }
    }

    mutating func screenCharArray(offset: Int,
                                  length: Int,
                                  metadata: iTermImmutableMetadata,
                                  continuation: screen_char_t,
                                  paddedToLength paddedSize: Int,
                                  eligibleForDWC: Bool) -> ScreenCharArray {
        let range = offset..<(offset + length)
        let chars = range.map { self[$0] }
        return withExtendedLifetime(chars) {
            let sca = ScreenCharArray(line: chars,
                                      length: Int32(chars.count),
                                      metadata: metadata,
                                      continuation: continuation).padded(toLength: Int32(paddedSize),
                                                                         eligibleForDWC: eligibleForDWC)
            sca.makeSafe()
            return sca
        }
    }

    mutating func string(from offset: Int,
                         length: Int,
                         backingStore backingStorePtr: UnsafeMutablePointer<UnsafeMutablePointer<unichar>?>,
                         deltas deltasPtr: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>) -> String? {
        var capacity = length + Int(kMaxParts) + 1
        var rawChars = iTermMalloc(MemoryLayout<unichar>.stride * capacity)
        var chars = rawChars.assumingMemoryBound(to: unichar.self)

        var rawDeltas = iTermMalloc(MemoryLayout<Int32>.stride * capacity)
        var deltas = rawDeltas.assumingMemoryBound(to: Int32.self)

        var o = 0
        var delta = Int32(0)
        for i in 0..<length {
            var sct = self[i + offset]
            if !sct.isRegularCharacter {
                delta += 1
                continue
            }
            if o + Int(kMaxParts) + 1 >= capacity {
                capacity *= 2

                rawChars = iTermRealloc(rawChars, capacity, MemoryLayout<unichar>.stride)
                chars = rawChars.assumingMemoryBound(to: unichar.self)

                rawDeltas = iTermRealloc(rawDeltas, capacity, MemoryLayout<Int32>.stride)
                deltas = rawDeltas.assumingMemoryBound(to: Int32.self)
            }

            let len = Int(ExpandScreenChar(&sct, &chars[o]))
            delta += 1
            for j in 0..<len {
                delta -= 1
                deltas[o + j] = delta
            }
            o += len
        }
        deltas[o] = delta
        backingStorePtr.pointee = chars
        deltasPtr.pointee = deltas
        return String(data: Data(bytesNoCopy: rawChars,
                                 count: MemoryLayout<unichar>.stride * o,
                                 deallocator: .none),
                      encoding: .utf16LittleEndian)
    }
}

extension screen_char_t {
    var isRegularCharacter: Bool {
        if image != 0 {
            return false
        }
        if complexChar != 0 {
            return true
        }
        let privateRange = unichar(ITERM2_PRIVATE_BEGIN)...unichar(ITERM2_PRIVATE_END)
        if privateRange.contains(code) {
            return false
        }
        return true
    }
}

// Buffer transisions as follows:
//
// uncompressed --1--> compressed
//           ^         |     ^
//           |         3     |
//           2         |     1
//           |         V     |
//          superposition ---'
//
// 1. Occurs periodically. Requires that the buffer not have multiple users.
// 2. This is best done at merge time. Requires that the buffer not have multiple concurrent users.
// 3. Can happen at any time.

fileprivate enum Buffer: Equatable {
    case uninitialized
    case uncompressed(UnsafeReallocatableMutableBuffer<screen_char_t>)
    case compressed(CompressedScreenCharBuffer)
    // This exists so that the compressed/uncompressed buffer that existed before, which may be used by other threads, remains valid.
    case superposition(CompressedScreenCharBuffer, UnsafeReallocatableMutableBuffer<screen_char_t>)

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
        case .superposition(let compressed, _):
            return .compressed(compressed)
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
        case let (.superposition(lvalue, _), .superposition(rvalue, _)):
            return lvalue == rvalue
        case let (.superposition(lvalue, _), .compressed(rvalue)),
            let (.compressed(lvalue), .superposition(rvalue, _)):
            return lvalue == rvalue
        case let (.superposition(_, lvalue), .uncompressed(rvalue)),
            let (.uncompressed(lvalue), .superposition(_, rvalue)):
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
        case .compressed(let compressed), .superposition(let compressed, _):
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
        case .compressed(let buffer), .superposition(let buffer, _):
            return buffer.debugDescription
        }
    }

    var shortDebugDescription: String {
        switch self {
        case .uninitialized:
            return "[uninitialized]"
        case .uncompressed(let buffer):
            return buffer.shortDebugDescription
        case .compressed(let buffer), .superposition(let buffer, _):
            return buffer.shortDebugDescription
        }
    }

    subscript(_ i: Int) -> screen_char_t {
        switch self {
        case .uninitialized:
            return screen_char_t()
        case .uncompressed(let innerBuffer):
            return innerBuffer.buffer[i]
        case .compressed(var innerBuffer), .superposition(var innerBuffer, _):
            return innerBuffer[i]
        }
    }
}

@objc(iTermCompressibleCharacterBuffer)
class CompressibleCharacterBuffer: NSObject, UniqueWeakBoxable {
    override var debugDescription: String {
        "<\(type(of: self)): \(it_addressString) compressed=\(isCompressed) size=\(size) idle=\(idleTime) “\(shortDebugDescription)”>"
    }

    private struct State: Equatable {
        var buffer: Buffer = .uninitialized
        // The actual buffer space when uncompressed will be at least this amount.
        // See resize() for details.
        var size: Int = 0

        mutating func realize() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
            let underlying = UnsafeReallocatableMutableBuffer<screen_char_t>(count: size)
            buffer = .uncompressed(underlying)
            return underlying
        }

        mutating func decompress() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
            switch buffer {
            case .uninitialized:
                return realize()
            case .uncompressed(let buffer), .superposition(_, let buffer):
                return buffer
            case .compressed(let compressedBuffer):
                let decompressed = compressedBuffer.decompressed(capacity: size)
                buffer = .superposition(compressedBuffer, decompressed)
                DLog("compressed -> superposition: \(buffer.debugDescription)")
                return decompressed
            }
        }

        mutating func resize(_ newSize: Int) {
            let oldSize = size
            size = newSize
            if newSize <= oldSize {
                // If it's getting smaller don't do anything yet. Next time the buffer gets compressed and
                // then decompressed it will actually shrink. This is done to avoid unnecessary reallocs
                // since shrinkToFit is called on blocks that might grow right away.
                return
            }
            switch buffer {
            case .uninitialized, .compressed:
                break
            case .uncompressed(let buffer):
                DLog("Resize \(buffer.shortDebugDescription) from \(oldSize) to \(newSize)")
                buffer.resize(to: newSize)
            case .superposition:
                // You must have acquired a mutation certificate to resize which guarantees no
                // superposition.
                fatalError()
            }
        }

        mutating func exitSuperpositionIfNeeded(toCompressed: Bool) {
            switch buffer {
            case .superposition(let compressed, let uncompressed):
                if toCompressed {
                    buffer = .compressed(compressed)
                    DLog("superposition -> compressed: \(buffer.debugDescription)")
                } else {
                    buffer = .uncompressed(uncompressed)
                    DLog("superposition -> uncompressed: \(buffer.debugDescription)")
                }
            default:
                break
            }
        }

        mutating func compress() -> Bool {
            switch buffer {
            case .uninitialized, .compressed:
                return false
            case .superposition:
                // Compression requires a mutation certificate so it's safe to exit superposition.
                exitSuperpositionIfNeeded(toCompressed: true)
                return false
            case .uncompressed(let buffer):
                let compressedBuffer = CompressedScreenCharBuffer(buffer, size: size)
                self.buffer = .compressed(compressedBuffer)
                DLog("uncompressed -> compressed \(buffer.debugDescription)")
                size = compressedBuffer.count
                return true
            }
        }

    }

    // Don't access this directly. Go through read() and write() instead.
    private var _state = State()
    private let lock = Mutex()
    @objc var size: Int {
        read { state in
            state.size
        }
    }

    private func read<T>(_ closure: (State) throws -> (T)) rethrows -> T {
        return try lock.sync {
            return try closure(_state)
        }
    }

    private func write<T>(_ closure: (inout State) throws -> (T)) rethrows -> T {
        return try lock.sync {
            return try closure(&_state)
        }
    }

    private var lastAccess = mach_absolute_time()
    lazy var uniqueWeakBox: UniqueWeakBox<CompressibleCharacterBuffer> = {
        UniqueWeakBox(self)
    }()

    @objc
    init(_ size: Int) {
        super.init()

        write { state in
            state.size = size
        }
    }

    @objc(initWithUncompressedData:)
    init?(uncompressed data: Data) {
        super.init()

        write { state in
            state.size = data.count / MemoryLayout<screen_char_t>.stride
            state.buffer = .uncompressed(UnsafeReallocatableMutableBuffer(data))
        }
    }

    @objc(initWithEncodedData:)
    init?(encoded data: Data) {
        super.init()

        var decoder = EfficientDecoder(data)
        do {
            try write { state in
                state.size = try decoder.getScalar()
                state.buffer = try Buffer(&decoder)
            }
        } catch {
            return nil
        }
    }
    
    private init(from other: CompressibleCharacterBuffer) {
        super.init()

        write { state in
            other.read { otherState in
                state.size = otherState.size
                state.buffer = otherState.buffer.clone()
            }
        }
    }

    @objc(encodedDataWithMaxSize:)
    func encodedData(maxSize: Int) -> Data {
        var encoded = EfficientEncoder()
        read { state in
            encoded.putScalar(state.size)
            state.buffer.encode(&encoded, maxSize: maxSize)
        }
        return encoded.data
    }

    private var placeholder: UnsafeMutablePointer<screen_char_t>?

    deinit {
        placeholder?.deallocate()
    }

    @objc
    var mutablePointer: UnsafeMutablePointer<screen_char_t> {
        lastAccess = mach_absolute_time()
        let result = write { state in
            switch state.buffer {
            case .uninitialized:
                return state.realize().buffer.baseAddress
            case .compressed:
                return state.decompress().buffer.baseAddress
            case .uncompressed(let buffer), .superposition(_, let buffer):
                return buffer.buffer.baseAddress
            }
        }
        if let result {
            return result
        }
        // There won't be a base address if the buffer is empty so return a placeholder.
        if let placeholder {
            return placeholder
        }
        let np = UnsafeMutablePointer<screen_char_t>.allocate(capacity: max(1, size))
        placeholder = np
        return np
    }

    @objc
    var pointer: UnsafePointer<screen_char_t> {
        UnsafePointer(mutablePointer)
    }

    @objc
    func resize(_ newSize: Int) {
        write { state in
            state.resize(newSize)
        }
    }

    @objc(cloneCompressed:)
    func clone(compressed: Bool) -> CompressibleCharacterBuffer {
        let newInstance = CompressibleCharacterBuffer(from: self)
        newInstance.write { newState in
            newState.exitSuperpositionIfNeeded(toCompressed: compressed)
        }
        return newInstance
    }

    @objc
    func deepIsEqual(_ object: Any?) -> Bool {
        guard let other = object as? CompressibleCharacterBuffer else {
            return false
        }
        return self == other
    }

    static func == (lhs: CompressibleCharacterBuffer, rhs: CompressibleCharacterBuffer) -> Bool {
        if lhs === rhs {
            return true
        }
        return earlierInMemory(lhs, rhs).read { lstate in
            laterInMemory(lhs, rhs).read { rstate in
                return lstate == rstate
            }
        }
    }

    @objc
    func compress() -> Bool {
        write { state in
            state.compress()
        }
    }

    @objc var idleTime: TimeInterval {
        let now = NSDate.it_timeInterval(forAbsoluteTime: mach_absolute_time())
        return now - NSDate.it_timeInterval(forAbsoluteTime: lastAccess)
    }

    @objc
    var isCompressed: Bool {
        read { state in
            switch state.buffer {
            case .compressed, .superposition:
                return true
            case .uninitialized, .uncompressed:
                return false
            }
        }
    }

    var shortDebugDescription: String {
        read {
            $0.buffer.shortDebugDescription
        }
    }

    @objc
    var hasUncompressedBuffer: Bool {
        read { state in
            switch state.buffer {
            case .uncompressed, .superposition:
                return true
            case .compressed, .uninitialized:
                return false
            }
        }
    }

    @objc
    var isInSuperposition: Bool {
        read { state in
            switch state.buffer {
            case .superposition:
                return true
            default:
                return false
            }
        }
    }

    /// Use this only for compressed buffers. It's faster than decompressing and then counting.
    @objc
    func numberOfFullLines(offset: Int,
                           length: Int,
                           width: Int) -> Int {
        read { state in
            switch state.buffer {
            case .uninitialized:
                return 0
            case .uncompressed:
                fatalError("Not supported")
            case .compressed(var buffer), .superposition(var buffer, _):
                var fullLines = 0
                var i = width
                while i < length {
                    if ScreenCharIsDWC_RIGHT(buffer[i]) {
                        i -= 1
                    }
                    fullLines += 1
                    i += width
                }
                return fullLines
            }
        }
    }

    @objc(characterAtIndex:)
    func chraracter(at index: Int) -> screen_char_t {
        read {
            $0.buffer[index]
        }
    }

    @objc(screenCharArrayStartingAtOffset:length:metadata:continuation:paddedToLength:eligibleForDWC:)
    func screenCharArray(offset: Int,
                         length: Int,
                         metadata: iTermImmutableMetadata,
                         continuation: screen_char_t,
                         paddedToLength paddedSize: Int,
                         eligibleForDWC: Bool) -> ScreenCharArray {
        read { state in
            switch state.buffer {
            case .uninitialized, .uncompressed:
                fatalError("Not supported")
            case .compressed(var innerBuffer), .superposition(var innerBuffer, _):
                let sca = innerBuffer.screenCharArray(offset: offset,
                                                      length: length,
                                                      metadata: metadata,
                                                      continuation: continuation,
                                                      paddedToLength: paddedSize,
                                                      eligibleForDWC: eligibleForDWC)

                return sca
            }
        }
    }

    @objc(stringFromOffset:length:backingStore:deltas:)
    func string(from offset: Int,
                length: Int,
                backingStore backingStorePtr: UnsafeMutablePointer<UnsafeMutablePointer<unichar>?>,
                deltas deltasPtr: UnsafeMutablePointer<UnsafeMutablePointer<Int32>?>) -> String? {
        read { state in
            switch state.buffer {
            case .uninitialized:
                fatalError()
            case .uncompressed(let innerBuffer):
                return ScreenCharArrayToString(innerBuffer.buffer.baseAddress!.advanced(by: offset),
                                               0,
                                               Int32(length),
                                               backingStorePtr,
                                               deltasPtr)
            case .compressed(var innerBuffer), .superposition(var innerBuffer, _):
                return innerBuffer.string(from: offset,
                                          length: length,
                                          backingStore: backingStorePtr,
                                          deltas: deltasPtr)
            }
        }
    }

    @objc
    func purgeDecompressed() {
        write { state in
            state.exitSuperpositionIfNeeded(toCompressed: false)
        }
    }

    @objc
    var compressionDebugDescription: String {
        let modeString = read { state in
            switch state.buffer {
            case .superposition:
                return "superposition"
            case .compressed:
                return "compressed"
            case .uncompressed:
                return "uncompressed"
            case .uninitialized:
                return "uninitialized"
            }
        }
        return "mode=\(modeString) idle=\(idleTime)"
    }
}
