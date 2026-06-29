//
//  EfficientCodec.swift
//  iTerm2
//
//  Created by George Nachman on 5/3/25.
//

struct EfficientDecoder {
    private let data: Data
    private var offset = 0

    var bytesRemaining: Int { data.count - offset }

    init(_ data: Data) {
        self.data = data
    }

    var finished: Bool {
        return offset >= data.count
    }

    mutating func getScalar<T: DefaultInitializable>() throws -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else {
            throw EfficientDecoderError()
        }
        var result = T()
        withUnsafeMutableBytes(of: &result) { destBuffer in
            data.withUnsafeBytes { rawBuffer in
                let src = rawBuffer.baseAddress!
                    .advanced(by: offset)
                destBuffer.baseAddress!
                    .copyMemory(from: src,
                                byteCount: size)
            }
        }
        offset += size
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

    mutating func getData() throws -> Data {
        let length: Int32 = try getScalar()
        defer {
            offset += Int(length)
        }
        let end = offset + Int(length)
        if end > data.count {
            throw EfficientDecoderError()
        }
        return data.subdata(in: offset..<end)
    }

    mutating func getRawBytes() throws -> Data {
        if offset >= data.count {
            throw EfficientDecoderError()
        }
        defer {
            offset = data.count
        }
        return data.subdata(in: offset..<data.count)
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

    mutating func putData(_ data: Data) {
        putScalar(Int32(data.count))
        self.data.append(data)
    }

    mutating func putRawBytes(_ data: Data) {
        self.data.append(data)
    }

    mutating func putByteArray<T>(_ value: inout [T]) {
        putScalar(Int32(value.count))
        value.withUnsafeBufferPointer { temp in
            data.append(temp)
        }
    }

    mutating func putByteArray<T>(_ value: inout ArraySlice<T>) {
        putScalar(Int32(value.count))
        value.withUnsafeBufferPointer { temp in
            data.append(temp)
        }
    }
}

protocol EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder)
}

protocol TLVTag: RawRepresentable, Hashable where RawValue == Int32 {}

struct EfficientTLVEncoder<Tag: TLVTag> {
    private var encoder = EfficientEncoder()

    mutating func put<T>(tag: Tag, value: T) where T: EfficientEncodable {
        var temp = EfficientEncoder()
        value.encodeEfficiently(encoder: &temp)
        let data = temp.data

        encoder.putScalar(tag.rawValue)
        encoder.putData(data)
    }

    var data: Data {
        encoder.data
    }
}

struct EfficientTLVDecoder<Tag: TLVTag> {
    private var decoder: EfficientDecoder

    init(_ data: Data) {
        decoder = EfficientDecoder(data)
    }

    struct EncodedBlob {
        var tag: Tag
        var decoder: EfficientDecoder
    }

    mutating func next() throws -> EncodedBlob? {
        while !decoder.finished {
            guard let tag = Tag(rawValue: try decoder.getScalar()) else {
                continue
            }
            let data = try decoder.getData()
            return EncodedBlob(tag: tag, decoder: EfficientDecoder(data))
        }
        return nil
    }

    mutating func decodeAll(required: Set<Tag>) throws -> [Tag: EfficientDecoder] {
        var missing = required
        var result = [Tag: EfficientDecoder]()
        while let blob = try next() {
            result[blob.tag] = blob.decoder
            missing.remove(blob.tag)
        }
        if !missing.isEmpty {
            throw EfficientDecoderError("Missing keys \(Array(missing).map { "\($0)" }.joined(separator: ", "))")
        }
        return result
    }
}

extension Bool: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putScalar(self ? UInt8(1) : UInt8(0))
    }
}

extension Int: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putScalar(self)
    }
}

extension Int32: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putScalar(self)
    }
}

extension UInt16: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putScalar(self)
    }
}

extension Array: EfficientEncodable where Element: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        for element in self {
            var temp = EfficientEncoder()
            element.encodeEfficiently(encoder: &temp)
            encoder.putData(temp.data)
        }
    }
}

extension Array: EfficientDecodable where Element: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Array<Element> {
        var result = [Element]()
        while !decoder.finished {
            let data = try decoder.getData()
            var temp = EfficientDecoder(data)
            result.append(try Element.create(efficientDecoder: &temp))
        }
        return result
    }
}

extension Data: EfficientEncodable {
    func encodeEfficiently(encoder: inout EfficientEncoder) {
        encoder.putRawBytes(self)
    }
}

extension Data: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Data {
        return try decoder.getRawBytes()
    }
}


protocol EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Self
}

extension Bool: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Bool {
        let byte: UInt8 = try decoder.getScalar()
        return byte != 0
    }
}

extension Int: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Int {
        return try decoder.getScalar()
    }
}

extension Int32: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Int32 {
        return try decoder.getScalar()
    }
}

extension UInt16: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> UInt16 {
        return try decoder.getScalar()
    }
}

extension Bool: DefaultInitializable {
    init() {
        self = false
    }
}

extension EfficientEncoder {
    func tlvEncoder<Tag: TLVTag>() -> EfficientTLVEncoder<Tag> {
        return EfficientTLVEncoder<Tag>()
    }
}

extension EfficientDecoder {
    mutating func tlvDecoder<Tag: TLVTag>() -> EfficientTLVDecoder<Tag> {
        return EfficientTLVDecoder<Tag>(data)
    }
}

extension screen_char_t: EfficientDecodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> screen_char_t {
        return try decoder.getScalar()
    }
}


extension Data {
    func dumpTLV() {
        var decoder = EfficientDecoder(self)
        do {
            while !decoder.finished {
                let tag: Int32 = try decoder.getScalar()
                let data = try decoder.getData()
                print("tag \(tag)")
                print("\(data.count) bytes: " + data.stringOrHex + "\n")
            }
        } catch {
            print(error.localizedDescription)
        }
    }
}

extension Dictionary: EfficientDecodable & EfficientEncodable
where Key: EfficientDecodable & EfficientEncodable, Value: EfficientDecodable & EfficientEncodable {
    static func create(efficientDecoder decoder: inout EfficientDecoder) throws -> Dictionary<Key, Value> {
        var result = [Key: Value]()
        while !decoder.finished {
            let keyData = try decoder.getData()
            let valueData = try decoder.getData()

            var keyDecoder = EfficientDecoder(keyData)
            let key = try Key.create(efficientDecoder: &keyDecoder)

            var valueDecoder = EfficientDecoder(valueData)
            let value = try Value.create(efficientDecoder: &valueDecoder)

            result[key] = value
        }
        return result

    }

    func encodeEfficiently(encoder: inout EfficientEncoder) {
        for (key, value) in self {
            var temp = EfficientEncoder()
            key.encodeEfficiently(encoder: &temp)
            encoder.putData(temp.data)

            temp = EfficientEncoder()
            value.encodeEfficiently(encoder: &temp)
            encoder.putData(temp.data)
        }
    }
}
