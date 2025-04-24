//
//  iTermMutableStringProtocol.swift
//  iTerm2
//
//  Created by George Nachman on 4/21/25.
//

@objc
protocol iTermMutableStringProtocol {
    @objc(deleteRange:) func objcDelete(range: NSRange)
    @objc func objReplace(range: NSRange, with replacement: iTermString)
    @objc(appendString:) func append(string: iTermString)
    @objc func deleteFromStart(_ count: Int)
    @objc func deleteFromEnd(_ count: Int)
}

protocol iTermMutableStringProtocolSwift: iTermMutableStringProtocol {
    func delete(range: Range<Int>)
    func replace(range: Range<Int>, with replacement: iTermString)
    func insert(_ string: iTermString, at index: Int)
}

