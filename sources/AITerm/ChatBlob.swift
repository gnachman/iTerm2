//
//  ChatBlob.swift
//  iTerm2
//
//  Mac-only persistence for a chat's wire-fragment blobs: the verbatim
//  request-shape bytes of one role turn (a user turn, an assistant turn with its
//  [text, tool_use] blocks together, or a tool-result turn), captured from
//  validated traffic. Blobs are the transcript / source of truth for what gets
//  sent to the model; the Message table stays the display/UI log. Reconstructing
//  a request is splicing a chat's blobs together (ordered by seq) and wrapping a
//  freshly assembled envelope (system + tools + volatile) around them, so the
//  fragile per-turn reconstruction pipeline (aiMessagesForStructuredReplay ->
//  AIChatToolCallRepair -> coalesce/adjacency -> stabilizeSessionReferences ->
//  per-vendor serializer) is retired for blob-native chats.
//
//  A blob is only replayable under the exact protocol (iTermAIAPI) it was
//  captured for, so the protocol is stored with each blob (OpenAI alone has
//  several protocols with unrelated wire formats). Like Message.seq, `seq` is a
//  delete-immune monotonic ordinal (INTEGER PRIMARY KEY AUTOINCREMENT) the engine
//  owns; `blobID` is the stable identity that survives a fork-copy and that
//  Message.firstBlobRef points at.
//
//  Not shared with the iOS companion (the phone never sends LLM requests), so the
//  struct and its SQLite conformance both live here.
//

import Foundation

struct ChatBlob: iTermDatabaseInitializable {
    // Engine-assigned ordering; 0 until inserted (insertQuery does not bind it).
    var seq: Int64
    // Stable identity, distinct from seq: survives a fork-copy (which mints a
    // fresh blobID and remaps Message.firstBlobRef through it) and is what
    // Message.firstBlobRef references.
    var blobID: UUID
    var chatID: String
    // The protocol this fragment's bytes are valid under. A fragment captured
    // for one protocol is not replayable under another (see file header).
    var blobProtocol: iTermAIAPI
    var role: Role
    // The verbatim request-shape wire bytes for this one message.
    var payload: Data
    // Present on assistant fragments captured on the Responses protocol, so the
    // previous_response_id fast path can be used when the id is still valid;
    // blobs remain the stateless fallback when it is not.
    var responseID: String?

    // The wire role of a fragment. Distinct from Message's Participant: these are
    // request-message roles, and an assistant turn's tool call rides in the same
    // `assistant` fragment as its preamble text (so the [text, tool_use] pairing
    // is captured atomically, killing the reload-time preamble drop).
    enum Role: String {
        case user
        case assistant
        case tool
    }

    enum Columns: String {
        case seq
        case blobID
        case chatID
        case blobProtocol
        case role
        case payload
        case responseID
    }

    init(blobID: UUID = UUID(),
         chatID: String,
         blobProtocol: iTermAIAPI,
         role: Role,
         payload: Data,
         responseID: String? = nil,
         seq: Int64 = 0) {
        self.seq = seq
        self.blobID = blobID
        self.chatID = chatID
        self.blobProtocol = blobProtocol
        self.role = role
        self.payload = payload
        self.responseID = responseID
    }

    static func schema() -> String {
        """
        create table if not exists ChatBlob
            (\(Columns.seq.rawValue) integer primary key autoincrement,
             \(Columns.blobID.rawValue) text,
             \(Columns.chatID.rawValue) text not null,
             \(Columns.blobProtocol.rawValue) integer not null,
             \(Columns.role.rawValue) text not null,
             \(Columns.payload.rawValue) blob not null,
             \(Columns.responseID.rawValue) text)
        """
    }

    // seq is left to the engine (AUTOINCREMENT), exactly like Message.appendQuery.
    func insertQuery() -> (String, [Any?]) {
        ("""
         insert into ChatBlob
             (\(Columns.blobID.rawValue), \(Columns.chatID.rawValue),
              \(Columns.blobProtocol.rawValue), \(Columns.role.rawValue),
              \(Columns.payload.rawValue), \(Columns.responseID.rawValue))
         values (?, ?, ?, ?, ?, ?)
         """,
         [blobID.uuidString,
          chatID,
          Int(blobProtocol.rawValue),
          role.rawValue,
          payload,
          responseID as Any?])
    }

    /// A chat's blobs oldest-first (splice order). seq is the ordinal, so ASC
    /// yields the exact order the turns were captured.
    static func query(forChatID chatID: String) -> (String, [Any?]) {
        ("select * from ChatBlob where \(Columns.chatID.rawValue)=? order by \(Columns.seq.rawValue) asc",
         [chatID])
    }

    /// The chat's highest blob seq (0 if it has none).
    static func maxSeqQuery(chatID: String) -> (String, [Any?]) {
        ("select max(\(Columns.seq.rawValue)) as maxseq from ChatBlob where \(Columns.chatID.rawValue)=?",
         [chatID])
    }

    /// Delete a chat's blobs (used when a protocol switch forces a re-freeze, and
    /// on chat deletion). Returns the statement; the caller runs it in a
    /// transaction with the re-blob inserts so a switch is atomic.
    static func deleteQuery(forChatID chatID: String) -> (String, [Any?]) {
        ("delete from ChatBlob where \(Columns.chatID.rawValue)=?", [chatID])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let blobIDStr = result.string(forColumn: Columns.blobID.rawValue),
              let blobID = UUID(uuidString: blobIDStr),
              let chatID = result.string(forColumn: Columns.chatID.rawValue),
              let roleStr = result.string(forColumn: Columns.role.rawValue),
              let role = Role(rawValue: roleStr),
              let payload = result.data(forColumn: Columns.payload.rawValue) else {
            return nil
        }
        // A blob whose protocol this build doesn't understand (written by a newer
        // iTerm2) can't be replayed, so drop it on read rather than crash.
        let rawProtocol = result.longLongInt(forColumn: Columns.blobProtocol.rawValue)
        guard rawProtocol >= 0,
              let blobProtocol = iTermAIAPI(rawValue: UInt(rawProtocol)) else {
            return nil
        }
        self.seq = result.longLongInt(forColumn: Columns.seq.rawValue)
        self.blobID = blobID
        self.chatID = chatID
        self.blobProtocol = blobProtocol
        self.role = role
        self.payload = payload
        self.responseID = result.string(forColumn: Columns.responseID.rawValue)
    }
}
