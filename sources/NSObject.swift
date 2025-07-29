//
//  NSObject.swift
//  iTerm2
//
//  Created by George Nachman on 7/28/25.
//

extension NSObject {
    func standardDescription(with components: [String]) -> String {
        let start = "<\(NSStringFromClass(Self.self)): \(it_addressString)"
        let end = ">"
        let mid = if components.isEmpty {
            ""
        } else {
            " " + components.joined(separator: " ")
        }
        return start + mid + end
    }
}
