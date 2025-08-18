//
//  Database.swift
//  iTerm2
//
//  Created by George Nachman on 6/19/25.
//

protocol iTermDatabaseInitializable {
    init?(dbResultSet: iTermDatabaseResultSet)
}

struct Migration {
    var query: String
    var args: [String]
}

protocol iTermDatabaseElement: iTermDatabaseInitializable {
    static func schema() -> String
    static func tableInfoQuery() -> String
    func appendQuery() -> (String, [Any?])
    func updateQuery() -> (String, [Any?])
    func removeQuery() -> (String, [Any?])
}
