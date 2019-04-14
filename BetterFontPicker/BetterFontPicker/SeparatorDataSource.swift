//
//  SeparatorDataSource.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/7/19.
//  Copyright © 2019 George Nachman. All rights reserved.
//

import Foundation

class SeparatorDataSource: NSObject, FontListDataSource {
    var filter = ""
    var isSeparator: Bool {
        return true
    }
    var names: [String] {
        return []
    }
    func reload() {
    }
}
