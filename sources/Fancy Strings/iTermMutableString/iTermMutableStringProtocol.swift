//
//  iTermMutableStringProtocol.swift
//  iTerm2
//
//  Created by George Nachman on 4/21/25.
//

@objc
protocol iTermMutableStringProtocol: iTermString {
    @objc(deleteRange:) func objcDelete(range: NSRange)
    @objc(replaceRange:with:) func objcReplace(range: NSRange, with replacement: iTermString)
    @objc(appendString:) func append(string: iTermString)
    @objc func deleteFromStart(_ count: Int)
    @objc func deleteFromEnd(_ count: Int)
    // An immutable copy.
    func clone() -> iTermString
    @objc func resetRTLStatus()
    @objc func setRTLIndexes(_ indexSet: IndexSet)
    @objc func setExternalAttributes(_ eaIndex: iTermExternalAttributeIndexReading?,
                                     sourceRange: NSRange,
                                     destinationStartIndex: Int)

}

protocol iTermMutableStringProtocolSwift: iTermMutableStringProtocol {
    func delete(range: Range<Int>)
    func replace(range: Range<Int>, with replacement: iTermString)
    func insert(_ string: iTermString, at index: Int)
}

