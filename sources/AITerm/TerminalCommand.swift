//
//  TerminalCommand.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only). Split from ToolCodecierge.swift so the
//  companion can render terminalCommand chat messages.
//

import Foundation

struct TerminalCommand: Codable {
    var username: String?
    var hostname: String?
    var directory: String?
    var command: String
    var output: String
    var exitCode: Int32
    var url: URL
}

extension String {
    var escapedForMarkdownCode: String {
        return replacingOccurrences(of: "`", with: "\\`")
    }
}
