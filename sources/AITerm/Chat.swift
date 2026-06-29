//
//  Chat.swift
//  iTerm2
//
//  Created by George Nachman on 2/25/25.
//
//  NOTE: This file is also compiled into the iTerm2 Companion iOS app. Keep it
//  platform-neutral (Foundation only); Mac-only code goes in a sibling file
//  (the database conformance lives in Chat+Database.swift).
//

import Foundation

struct Chat: Codable {
    var id = UUID().uuidString
    var title: String
    var creationDate = Date()
    var lastModifiedDate = Date()

    // Mutually exclusive with session/browser binding. When true the
    // chat is in orchestrator mode (workgroup-claim tools, async
    // watchers); when false the chat is session-bound (AITerm:
    // Link/Unlink Session, RemoteCommand tools, hosted vector
    // stores). The user can flip the mode at runtime via a menu item
    // or grant the agent's request_orchestration_enable tool call;
    // the toggle is responsible for clearing the fields that don't
    // belong in the other mode.
    var orchestrationEnabled: Bool = false
    var terminalSessionGuid: String?
    var browserSessionGuid: String?
    var permissions: String
    var vectorStore: String?

    // Targets this chat is allowed to write to via the orchestrator
    // tools (send_text / interrupt / add_workgroup_clipping for
    // workgroup-shaped targets; session_execute_command and friends
    // for raw-session targets). Each entry is either a real workgroup
    // instance ID OR a synthetic single-session scope of the form
    // "session:<sessionGuid>" (see
    // WorkgroupIntrospection.syntheticWorkgroupIDPrefix). Empty on
    // AITerm-style single-session chats; non-empty on orchestrator
    // chats. Persisted so approval survives restarts.
    var claimedScopes: [String] = []

    // Async watchers registered via the orchestrator's register_watch
    // tool. Empty for non-orchestrator chats.
    var watchers: [WorkgroupWatcher] = []

    // Small square PNG generated from the title by ChatIconGenerator,
    // shown circle-clipped in the chat list. Nil until the first
    // AI-generated title arrives or when generation fails; the list
    // shows a default icon then.
    //
    // Known tradeoff: fetchAllQuery() selects * and DatabaseBackedArray
    // keeps every row resident, so all icon blobs (roughly 3-15KB each)
    // load eagerly and stay in memory. The blob also rides along on
    // every row rewrite: each message bump is a DELETE + INSERT of the
    // full row, so a busy chat rewrites its icon to the WAL once per
    // message event. Fine at realistic chat counts; if chats in the
    // thousands become common, project this column out of the list
    // query (and the hot row) and fetch per chat on demand.
    var icon: Data?
}
