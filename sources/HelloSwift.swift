//
//  HelloSwift.swift
//  iTerm2
//
//  Created by George Nachman on 2/12/18.
//

import Foundation

@objc(iTermHelloSwift) public class HelloSwift : NSObject {
    @objc(addFirst:second:) public func add(first: Int, second: Int) -> Int {
        return first + second
    }
}
