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

/// Lets you ask if some amount of time has passed.
class DeadlineMonitor {
    private let end: TimeInterval

    private static var now: TimeInterval {
        NSDate.it_timeInterval(forAbsoluteTime: mach_absolute_time())
    }

    init(duration: TimeInterval) {
        end = Self.now + duration
    }

    /// Returns: whether the deadline remains unreached.
    var pending: Bool {
        return Self.now < end
    }
}

// This manages a collection of buffers that need compression eventually. It tries to schedule work
// when nothing else is going on and avoids hogging the CPU.
class CharacterBufferCompressor {
    // All methods run on this queue.
    private let queue: DispatchQueue
    private var scheduled = false
    typealias BufferSet = Set<UniqueWeakBox<CompressibleCharacterBuffer>>
    private var buffers = MutableAtomicObject(BufferSet())

    init(_ queue: DispatchQueue) {
        self.queue = queue
        if #available(macOS 12.0, *) {
            NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                   object: nil,
                                                   queue: nil) { [weak self] notif in
                self?.queue.async {
                    DLog("Low power mode disabled. Try to schedule decompression. queue=\(String(describing: self?.queue))")
                    self?.scheduleIfNeeded(urgency: .low)
                }
            }
        }
    }

    func insert(_ buffer: CompressibleCharacterBuffer) {
        buffers.mutableAccess {
            $0.insert(buffer.uniqueWeakBox)
        }
        scheduleIfNeeded(urgency: .low)
    }

    private enum Urgency {
        case low
        case medium
        case high

        // Delay before attempting compression.
        var duration: TimeInterval {
            switch self {
                // Used when a buffer has just been used. We want the delay to be long since it's
                // likely to be reused again soon.
                case .low: return 20.0

                // Used when the system is too busy to do compression. This is a balance between
                // wasting CPU and waiting too long for a window where we could do work and missing
                // it.
                case .medium: return 1.0

                // Used when we ran out of time compressing and had more to do. We don't want to
                // wait too long because it'll take too long to compress lots of buffers. We don't
                // to wait too little (we'll keep CPU utilization high) and burn a lot of cycles on
                // scheduling overhead.
                case .high: return 0.2
            }
        }
    }

    private func scheduleIfNeeded(urgency: Urgency) {
        if scheduled {
            return
        }
        if buffers.value.isEmpty {
            return
        }
        if #available(macOS 12.0, *) {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                return
            }
        }
        DLog("Schedule compression in \(urgency.duration) sec")
        scheduled = true
        queue.asyncAfter(deadline: .now() + urgency.duration) { [weak self] in
            self?.scheduled = false
            self?.compress()
        }
    }

    // How long a buffer must be idle before we'll compress it.
    fileprivate static func ttl(_ size: Int) -> TimeInterval {
        let baseTime = TimeInterval(1.25)
        return baseTime * Double(size) / 1024.0
    }

    private func compress() {
        let utilization = ProcessInfo.ownCPUUsage()
        if utilization > 0.5 {
            DLog("My cpu is \(utilization) so don't try to compress")
            scheduleIfNeeded(urgency: .medium)
            return
        }
        DLog("My cpu is \(utilization) so proceed")
        var finishedInTime = false
        buffers.mutate { buffers in
            DLog("Try to compress \(buffers.prefix(16).compactMap { $0.value?.debugDescription }.joined(separator: " "))")
            // residual holds the buffers we do not choose to compress.
            var residual = buffers

            // Avoid hogging the main thread. Since we are forced to run on a particular dispatch
            // queue, we don't get to use QoS. Instead, limit the duration of this loop to a small
            // fraction of the interval at which the timer that launches it runs.
            let dutyCycle = 0.05
            let deadlineMonitor = DeadlineMonitor(duration: Urgency.high.duration * dutyCycle)
            var count = 0
            for box in buffers where deadlineMonitor.pending {
                guard let buffer = box.value else {
                    residual.remove(box)
                    continue
                }
                if buffer.idleTime > Self.ttl(buffer.size) {
                    buffer.compress()
                    residual.remove(box)
                    count += 1
                }
            }
            DLog("Compressed \(count) buffers")
            finishedInTime = deadlineMonitor.pending
            return residual
        }
        scheduleIfNeeded(urgency: finishedInTime ? .low : .high)
    }
}

@objc(iTermCompressibleCharacterBuffer)
class CompressibleCharacterBuffer: NSObject, UniqueWeakBoxable {
    override var debugDescription: String {
        return "<\(type(of: self)): \(it_addressString) compressed=\(isCompressed) size=\(size) idle=\(idleTime) “\(buffer.shortDebugDescription)”>"
    }

    private var buffer: Buffer = .uninitialized
    // The actual buffer space when uncompressed will be at least this amount.
    // See resize() for details.
    @objc private(set) var size: Int
    private var lastAccess = mach_absolute_time()
    lazy var uniqueWeakBox: UniqueWeakBox<CompressibleCharacterBuffer> = {
        UniqueWeakBox(self)
    }()

    // There is one context per thread on which CompressibleCharacterBuffer is used. It is
    // responsible for owning a CharacterBufferCompressor and providing CompressibleCharacterBuffer
    // objects to it when it becomes safe to compress them. All knowledge of the interaction between
    // dispatch queues and compressible buffers goes here.
    @objc(iTermCharacterBufferContext)
    class Context: NSObject {
        private var buffers = Set<CompressibleCharacterBuffer>()
        private static let key = DispatchSpecificKey<Context>()
        private let queue: DispatchQueue
        private var enqueued = false
        private let compressor: CharacterBufferCompressor

        static var instanceForCurrentQueue: Context {
            // If this crashes, it's becuse you didn't initialize a Context for the current dispatch queue.
            // Any queue where you plan to use CompressibleCharacterBuffer (and, ultimately, LineBuffer)
            // must have a Context assigned.
            DispatchQueue.getSpecific(key: key)!
        }

        @objc(ensureInstanceForQueue:) static func ensureInstance(forQueue queue: DispatchQueue) {
            if queue.getSpecific(key: key) == nil {
                let instance = Context(queue: queue)
                queue.setSpecific(key: Self.key, value: instance)
            }
        }

        private init(queue: DispatchQueue) {
            self.queue = queue
            compressor = CharacterBufferCompressor(queue)

            super.init()
        }

        fileprivate func insert(_ buffer: CompressibleCharacterBuffer) {
            dispatchPrecondition(condition: .onQueue(self.queue))

            buffers.insert(buffer)
            if !enqueued {
                enqueue()
            }
        }

        private func enqueue() {
            enqueued = true
            // Unsafe pointers to buffers are only valid until the next spin of the queue on which
            // they are used (since they're essentially autoreleased). Therefore it should be safe
            // to compress them using DispatchQueue.async.
            queue.async {
                self.enqueued = false
                self.moveBuffersToCompressor()
            }
        }

        func moveBuffersToCompressor() {
            for buffer in buffers {
                compressor.insert(buffer)
            }
            buffers.removeAll()
        }
    }


    @objc
    init(_ size: Int) {
        self.size = size
    }

    @objc(initWithUncompressedData:)
    init?(uncompressed data: Data) {
        size = data.count / MemoryLayout<screen_char_t>.stride
        buffer = .uncompressed(UnsafeReallocatableMutableBuffer(data))

        super.init()

        Context.instanceForCurrentQueue.insert(self)
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
        Context.instanceForCurrentQueue.insert(self)
        lastAccess = mach_absolute_time()
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
        Context.instanceForCurrentQueue.insert(self)
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

    func compress() {
        switch buffer {
        case .uninitialized, .compressed:
            return
        case .uncompressed(let buffer):
            let compressedBuffer = CompressedScreenCharBuffer(buffer, size: size)
            self.buffer = .compressed(compressedBuffer)
            size = compressedBuffer.count
        }
    }

    @objc var idleTime: TimeInterval {
        let now = NSDate.it_timeInterval(forAbsoluteTime: mach_absolute_time())
        return now - NSDate.it_timeInterval(forAbsoluteTime: lastAccess)
    }

    private func realize() -> UnsafeReallocatableMutableBuffer<screen_char_t> {
        let underlying = UnsafeReallocatableMutableBuffer<screen_char_t>(count: size)
        buffer = .uncompressed(underlying)
        return underlying
    }

    @objc
    var isCompressed: Bool {
        switch buffer {
        case .compressed:
            return true
        case .uninitialized, .uncompressed:
            return false
        }
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

    /// Use this only for compressed buffers. It's faster than decompressing and then counting.
    @objc
    func numberOfFullLines(offset: Int,
                           length: Int,
                           width: Int) -> Int {
        switch buffer {
        case .uninitialized:
            return 0
        case .uncompressed:
            fatalError("Not supported")
        case .compressed(var buffer):
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
