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
    // nil when the command was aborted rather than exiting, so it has no status.
    var exitCode: Int32?
    var url: URL
}

// Commands are saved in the chat database and sent to the companion app, and older builds of both
// decode `exitCode` as required. An aborted command is encoded with an exit code of 0, which is what
// those builds always wrote for one, plus an `aborted` flag they ignore.
extension TerminalCommand {
    private enum CodingKeys: String, CodingKey {
        case username, hostname, directory, command, output, exitCode, aborted, url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        directory = try container.decodeIfPresent(String.self, forKey: .directory)
        command = try container.decode(String.self, forKey: .command)
        output = try container.decode(String.self, forKey: .output)
        let aborted = try container.decodeIfPresent(Bool.self, forKey: .aborted) ?? false
        exitCode = aborted ? nil : try container.decodeIfPresent(Int32.self, forKey: .exitCode)
        url = try container.decode(URL.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encodeIfPresent(directory, forKey: .directory)
        try container.encode(command, forKey: .command)
        try container.encode(output, forKey: .output)
        try container.encode(exitCode ?? 0, forKey: .exitCode)
        if exitCode == nil {
            try container.encode(true, forKey: .aborted)
        }
        try container.encode(url, forKey: .url)
    }
}

extension String {
    var escapedForMarkdownCode: String {
        return replacingOccurrences(of: "`", with: "\\`")
    }
}
