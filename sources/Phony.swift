//
//  Phony.swift
//  iTerm2
//
//  Created by George Nachman on 6/23/21.
//

import Foundation
import iTerm2SharedARC

@objc public class Phony: NSObject {
    @objc(IExist) public func IExist() {
        print("I exist")
        HelloWorld().Hello()
    }
}
