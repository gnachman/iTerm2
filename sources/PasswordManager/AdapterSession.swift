//
//  AdapterSession.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/3/26.
//

import Foundation

/// The login session a password manager adapter is using, and the rules for recovering when
/// the adapter rejects one.
///
/// Every login gets a new generation number. Commands remember the generation they were built
/// with, so a rejection can be matched to the session it was actually about. That matters
/// when several commands are in flight: one may log in again while another, built with the
/// old session, is still running and then fails.
struct AdapterSession {
    /// What to do after the adapter rejects a session.
    enum Recovery: Equatable {
        /// Build the command again and run it. Building logs in first if there is no session.
        case retry
        /// Logging in again won’t help: the password manager rejected a session it had just
        /// issued, before it ever worked. Show the error instead of prompting in a loop.
        case stop
    }

    private(set) var token: String?
    private(set) var generation = 0
    /// Whether the current session has been accepted by the adapter at least once.
    private(set) var accepted = false

    /// A login succeeded with a new session. Adapters without sessions return no token, in which
    /// case every command logs in first, as before.
    mutating func loggedIn(token: String?) {
        self.token = token
        generation += 1
        accepted = false
    }

    /// Forget the session, for example when the configuration is reset.
    mutating func clear() {
        token = nil
        accepted = false
    }

    /// The adapter got past checking the session that `generation` refers to. That proves the
    /// session works even if the command then failed for another reason. Nil means unknown,
    /// treated as the current session.
    mutating func noteAccepted(generation commandGeneration: Int?) {
        if (commandGeneration ?? generation) == generation {
            accepted = true
        }
    }

    /// The adapter rejected the session that `generation` refers to. Nil means unknown, treated
    /// as the current session.
    mutating func noteRejected(generation commandGeneration: Int?) -> Recovery {
        guard (commandGeneration ?? generation) == generation, token != nil else {
            // An older session, or one already dropped. Whatever replaced it may be fine, so
            // leave it alone and try again with it.
            return .retry
        }
        let hadWorked = accepted
        clear()
        return hadWorked ? .retry : .stop
    }
}
