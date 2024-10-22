//
//  AddressString.swift
//  iTerm2
//
//  Created by George Nachman on 10/22/24.
//

func addressString(_ object: Any?) -> String {
    guard let object else {
        return "(nil)"
    }
    let mirror = Mirror(reflecting: object)
    if mirror.displayStyle == .class {
        // Object is a class instance (reference type)
        let ptr = Unmanaged.passUnretained(object as AnyObject).toOpaque()
        return String(format: "%p", UInt(bitPattern: ptr))
    } else {
        return "[value type]]"
    }
}

