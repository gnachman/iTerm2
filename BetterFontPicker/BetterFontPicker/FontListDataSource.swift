//
//  FontListDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

@objc(BFPFontListDataSource)
public protocol FontListDataSource: NSObjectProtocol {
    var isSeparator: Bool { get }
    var names: [String] { get }
    var filter: String { get set }
    func reload()
}
