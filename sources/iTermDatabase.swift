//
//  iTermDatabase.swift
//  iTerm2
//
//  Created by George Nachman on 6/20/25.
//

extension iTermDatabase {
    func executeUpdate(_ sql: String, withArguments args: [Any?]) throws {
        try executeUpdate(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }

    @discardableResult
    func executeQuery(_ sql: String, withArguments args: [Any?]) throws -> iTermDatabaseResultSet? {
        return try executeQuery(sql, withNonOptionalArguments: args.map {
            if let value = $0 {
                value
            } else {
                NSNull()
            }
        })
    }
}
