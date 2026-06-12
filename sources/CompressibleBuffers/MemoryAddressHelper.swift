//
//  MemoryAddressHelper.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/26/23.
//

import Foundation

func earlierInMemory<T: AnyObject>(_ lhs: T, _ rhs: T) -> T {
    let lhsAddress = Unmanaged.passUnretained(lhs).toOpaque()
    let rhsAddress = Unmanaged.passUnretained(rhs).toOpaque()
    return lhsAddress <= rhsAddress ? lhs : rhs
}

func laterInMemory<T: AnyObject>(_ lhs: T, _ rhs: T) -> T {
    let lhsAddress = Unmanaged.passUnretained(lhs).toOpaque()
    let rhsAddress = Unmanaged.passUnretained(rhs).toOpaque()
    return lhsAddress > rhsAddress ? lhs : rhs
}

