//
//  iTermRectArray.swift
//  iTerm2
//
//  Created by George Nachman on 3/30/25.
//

@objc(iTermRectArray)
class iTermRectArray: NSObject {
    fileprivate var values = [NSRect]()

    override var description: String {
        "<\(Self.self): \(it_addressString): " + values.map { "\($0)" }.joined(separator: ", ") + ">"
    }

    override var debugDescription: String {
        description
    }

    @objc
    override init() {
        values = []
        super.init()
    }

    init(_ values: [NSRect]) {
        self.values = values
    }

    @objc var count: Int { values.count }
    @objc(rectAtIndex:)
    func rect(at i: Int) -> NSRect {
        values[i]
    }

    @objc(shiftedBy:)
    func shifted(by offset: NSPoint) -> iTermRectArray {
        return iTermRectArray(values.map { $0 + offset })
    }

    @objc(enumerateWithBlock:)
    func enumerate(block: (NSRect) -> ()) {
        for rect in values {
            block(rect)
        }
    }
}


@objc(iTermMutableRectArray)
class iTermMutableRectArray: iTermRectArray {
    @objc
    override init() {
        super.init()
    }
    @objc(append:)
    func append(_ rect: NSRect) {
        values.append(rect)
    }
}
