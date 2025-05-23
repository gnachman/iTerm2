//
//  SubData.swift
//  StyleMap
//
//  Created by George Nachman on 4/18/25.
//

/// Like SubString but for Data
struct SubData {
    private var _data: Data
    private(set) var range: Range<Int>
    var count: Int { range.count }
    var data: Data {
        Data(_data[range])
    }
    init() {
        _data = Data()
        range = 0..<0
    }
    init(data: Data, range: Range<Int>) {
        self._data = data
        self.range = range
    }

    subscript(_ subrange: Range<Int>) -> SubData {
        let expanded = (range.lowerBound + subrange.lowerBound)..<(range.lowerBound + subrange.upperBound)
        return SubData(data: _data, range: expanded)
    }

    subscript(_ i: Int) -> UInt8 {
        return _data[i]
    }

    mutating func append(_ other: Data) {
        if range.lowerBound != 0 || range.upperBound != _data.count {
            _data = _data[range]
        }
        _data.append(other)
        range = 0..<_data.count
    }
    mutating func deleteFromEnd(count: Int) {
        range = range.lowerBound..<(range.upperBound - count)
    }
}

extension SubData: Sequence {
    func makeIterator() -> AnyIterator<UInt8> {
        var index = range.lowerBound
        return AnyIterator {
            guard index < range.upperBound else {
                return nil
            }
            let byte = self._data[index]
            index += 1
            return byte
        }
    }
}


extension SubData: Equatable {
    static func ==(lhs: SubData, rhs: SubData) -> Bool {
        if lhs.range.count != rhs.range.count {
            return false
        }
        return lhs._data.withUnsafeBytes { (urbp_l: UnsafeRawBufferPointer) in
            return rhs._data.withUnsafeBytes { (urbp_r: UnsafeRawBufferPointer) in
                return memcmp(urbp_l.baseAddress!.advanced(by: lhs.range.lowerBound),
                              urbp_r.baseAddress!.advanced(by: rhs.range.lowerBound),
                              lhs.range.count) == 0
            }
        }
    }
}
