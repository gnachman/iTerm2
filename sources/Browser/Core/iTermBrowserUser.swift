//
//  iTermBrowserUser.swift
//  iTerm2
//
//  Created by George Nachman on 6/26/25.
//


enum iTermBrowserUser: Hashable, Equatable {
    case regular(id: UUID)
    case devNull
}

extension iTermBrowserUser: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .regular(id: let id):
            return "iTermBrowserUser.regular(\(id))"
        case .devNull:
            return "iTermBrowserUser.devNull"
        }
    }
}
