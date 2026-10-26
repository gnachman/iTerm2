//
//  TmuxGateway+Replies.swift
//  iTerm2SharedARC
//
//  Closure-based replies for Swift callers of TmuxGateway. The gateway holds a command's reply
//  target until tmux answers, so the closure lives exactly as long as the command is outstanding.
//

import Foundation

extension TmuxGateway {
    /// Errors are tolerated: the closure gets nil when tmux reports an error.
    func send(_ command: String, reply: @escaping (String?) -> Void) {
        sendCommand(command,
                    responseTarget: TmuxGatewayReply(reply),
                    responseSelector: #selector(TmuxGatewayReply.handle(_:)),
                    responseObject: nil,
                    flags: 1)  // kTmuxGatewayCommandShouldTolerateErrors
    }

    /// Sends `commands` as one command list, which tmux runs without interleaving another client's
    /// commands, and calls `replies` once with each command's reply (nil for an error, or for a
    /// command skipped because an earlier one in the list failed).
    func sendList(_ commands: [String], replies: @escaping ([String?]) -> Void) {
        guard !commands.isEmpty else {
            replies([])
            return
        }
        var collected = [String?]()
        let dictionaries = commands.map { command in
            dictionary(forCommand: command,
                       responseTarget: TmuxGatewayReply { reply in
                           collected.append(reply)
                           if collected.count == commands.count {
                               replies(collected)
                           }
                       },
                       responseSelector: #selector(TmuxGatewayReply.handle(_:)),
                       responseObject: nil,
                       flags: 1)!  // kTmuxGatewayCommandShouldTolerateErrors
        }
        sendCommandList(dictionaries)
    }

    /// See TmuxWorkgroupCommands for what a guarded command is.
    func sendGuarded(_ command: String, outcome: @escaping (TmuxWorkgroupCommands.GuardOutcome) -> Void) {
        sendGuardedCommand(command,
                           responseTarget: TmuxGatewayReply { reply in
                               outcome(TmuxWorkgroupCommands.GuardOutcome(branchReply: reply))
                           },
                           responseSelector: #selector(TmuxGatewayReply.handle(_:)),
                           responseObject: nil)
    }
}

private final class TmuxGatewayReply: NSObject {
    private let block: (String?) -> Void

    init(_ block: @escaping (String?) -> Void) {
        self.block = block
    }

    @objc func handle(_ reply: String?) {
        block(reply)
    }
}
