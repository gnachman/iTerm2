//
//  CompanionAlert+Database.swift
//  iTerm2
//
//  Mac-only persistence for a terminal "alert" surfaced to the paired phone by
//  the contentless-wakeup push (protocol revision >= 2). The phone never sees this
//  type, only the slim CompanionSyncAlertItem the host builds from a row. Like
//  Message.seq, `seq` is a global, monotonic, delete-immune cursor (INTEGER
//  PRIMARY KEY AUTOINCREMENT) the phone's alert floor tracks. Persisted (not an
//  in-memory ring) so an alert survives a Mac restart between the push and the
//  NSE's fetch.
//

import Foundation

struct CompanionAlertRecord {
    var seq: Int64
    var uniqueID: UUID
    /// Groups a session's alerts on the phone (the NSE computes the
    /// threadIdentifier as HMAC(roomSecret, "alert:" + threadKey) on-device).
    /// Today this is the source session's guid.
    var threadKey: String
    var title: String
    var body: String
    var createdDate: Date

    enum Columns: String {
        case seq
        case uniqueID
        case threadKey
        case title
        case body
        case createdDate
    }

    init(seq: Int64, uniqueID: UUID, threadKey: String, title: String, body: String, createdDate: Date) {
        self.seq = seq
        self.uniqueID = uniqueID
        self.threadKey = threadKey
        self.title = title
        self.body = body
        self.createdDate = createdDate
    }

    static func schema() -> String {
        """
        create table if not exists CompanionAlert
            (\(Columns.seq.rawValue) integer primary key autoincrement,
             \(Columns.uniqueID.rawValue) text,
             \(Columns.threadKey.rawValue) text not null,
             \(Columns.title.rawValue) text not null,
             \(Columns.body.rawValue) text not null,
             \(Columns.createdDate.rawValue) integer not null)
        """
    }

    func insertQuery() -> (String, [Any?]) {
        ("""
         insert into CompanionAlert
             (\(Columns.uniqueID.rawValue), \(Columns.threadKey.rawValue),
              \(Columns.title.rawValue), \(Columns.body.rawValue), \(Columns.createdDate.rawValue))
         values (?, ?, ?, ?, ?)
         """,
         [uniqueID.uuidString, threadKey, title, body, createdDate.timeIntervalSince1970])
    }

    /// Oldest-first window of alerts with seq greater than `sinceSeq`. ASC so the
    /// alert floor drains contiguously from the bottom (advancing only to what was
    /// covered); a window sized at/above the store's prune cap means alerts never
    /// truncate, so none are ever silently skipped past the floor.
    static func alertsSinceQuery(seq: Int64, limit: Int) -> (String, [Any?]) {
        ("""
         select * from CompanionAlert
         where \(Columns.seq.rawValue)>?
         order by \(Columns.seq.rawValue) asc limit ?
         """,
         [seq, limit])
    }

    /// The store's highest alert seq (0 if empty).
    static func maxSeqQuery() -> (String, [Any?]) {
        ("select max(\(Columns.seq.rawValue)) as maxseq from CompanionAlert", [])
    }

    /// Keep only the newest `keep` rows (bounded store); delete the rest.
    static func pruneQuery(keep: Int) -> (String, [Any?]) {
        ("""
         delete from CompanionAlert
         where \(Columns.seq.rawValue) not in
             (select \(Columns.seq.rawValue) from CompanionAlert
              order by \(Columns.seq.rawValue) desc limit ?)
         """,
         [keep])
    }

    init?(dbResultSet result: iTermDatabaseResultSet) {
        guard let uniqueIDStr = result.string(forColumn: Columns.uniqueID.rawValue),
              let uniqueID = UUID(uuidString: uniqueIDStr),
              let threadKey = result.string(forColumn: Columns.threadKey.rawValue),
              let title = result.string(forColumn: Columns.title.rawValue),
              let body = result.string(forColumn: Columns.body.rawValue),
              let createdDate = result.date(forColumn: Columns.createdDate.rawValue) else {
            return nil
        }
        self.seq = result.longLongInt(forColumn: Columns.seq.rawValue)
        self.uniqueID = uniqueID
        self.threadKey = threadKey
        self.title = title
        self.body = body
        self.createdDate = createdDate
    }
}
