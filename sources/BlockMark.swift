//
//  BlockMark.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/25/23.
//

import Foundation

@objc(iTermBlockMarkReading)
protocol BlockMarkReading: AnyObject, iTermMarkProtocol {
    var blockID: String { get }
}
@objc(iTermBlockMark)
class BlockMark: iTermMark, BlockMarkReading {
    @objc var blockID = UUID().uuidString
    @objc var type: String?

    @objc
    override init() {
        super.init()
    }

    required init!(dictionary dict: [AnyHashable : Any]!) {
        blockID = (dict["block ID"] as? String) ?? UUID().uuidString
        type = dict["type"] as? String
        super.init(dictionary: dict)
    }

    override func dictionaryValue() -> [AnyHashable : Any]! {
        var dict = super.dictionaryValue()!
        dict["block ID"] = blockID
        if let type {
            dict["type"] = type
        }
        return dict
    }
}
