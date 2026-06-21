//
//  CompanionPushRelay.swift
//  iTerm2
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in sibling files.
//
//  Where the push relay Worker lives. The phone registers its APNs token
//  there ( /register ) and the Mac sends notifications through it ( /push ).
//  Deploy with `wrangler deploy` in Companion/PushRelay, then point this at
//  the printed URL.
//

import Foundation

enum CompanionPushRelay {
    static let baseURL = URL(string: "https://iterm2-push-relay.gnachman.workers.dev")!

    static var registerURL: URL { baseURL.appendingPathComponent("register") }
    static var pushURL: URL { baseURL.appendingPathComponent("push") }
    /// Content-free push that wakes the Notification Service Extension.
    static var mutablePushURL: URL { baseURL.appendingPathComponent("push/mutable") }
}
