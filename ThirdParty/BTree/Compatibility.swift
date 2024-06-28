//
//  Compatibility.swift
//  BTree
//
//  Created by Károly Lőrentey on 2016-11-05.
//  Copyright © 2016–2017 Károly Lőrentey.
//

private func unavailable() -> Never {
    fatalError("Unavailable function cannot be called")
}

extension BTree {
    @available(*, unavailable, renamed: "union(_:by:)",
    message: "Use union with the .groupingMatches strategy instead.")
    public func distinctUnion(_ other: BTree) -> BTree { unavailable() }
}
