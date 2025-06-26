//
//  MimeTypeUtilities.swift
//  iTerm2
//
//  Created by George Nachman on 6/26/25.
//

import Foundation

class MimeTypeUtilities {
    static func extensionForMimeType(_ mimeType: String) -> String {
        let mimeToExtension = extensionToMime.lossilyInverted
        
        if let fileExtension = mimeToExtension[mimeType.lowercased()] {
            return fileExtension
        }
        
        let cleanMimeType = mimeType.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mimeType
        if let fileExtension = mimeToExtension[cleanMimeType.lowercased()] {
            return fileExtension
        }
        
        switch cleanMimeType.lowercased() {
        case let mime where mime.hasPrefix("image/"):
            return "img"
        case let mime where mime.hasPrefix("video/"):
            return "vid"
        case let mime where mime.hasPrefix("audio/"):
            return "aud"
        case let mime where mime.hasPrefix("text/"):
            return "txt"
        case let mime where mime.hasPrefix("application/"):
            return "bin"
        default:
            return "dat"
        }
    }
}